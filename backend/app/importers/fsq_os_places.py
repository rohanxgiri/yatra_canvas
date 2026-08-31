"""Idempotent local-file importer for Foursquare Open Source Places.

The importer intentionally accepts only CSV and JSONL so the backend does not
need a heavyweight dataframe dependency. Files should be filtered/exported
locally; each record is still checked against the configured Indian city before
any database lookup or mutation.
"""

from collections.abc import Iterator, Mapping
import csv
from dataclasses import asdict, dataclass
from datetime import date, datetime, timezone
from difflib import SequenceMatcher
import json
from math import asin, cos, isfinite, radians, sin, sqrt
from pathlib import Path
from typing import Any

from sqlalchemy import func
from sqlmodel import Session, select

from app.importers.city_config import ImportCity, get_import_city, normalize_text
from app.models import City, Place, PlaceCategory, PlaceImportReview, PlaceSource


FSQ_PROVIDER = "fsq_os_places"
FSQ_LICENCE = "Apache-2.0"
FSQ_SOURCE_URL = "https://foursquare.com/placemakers/review-place/{place_id}"


@dataclass(frozen=True)
class FSQPlaceRecord:
    fsq_place_id: str
    name: str
    latitude: float
    longitude: float
    address: str | None
    locality: str
    region: str | None
    postcode: str | None
    country: str
    telephone: str | None
    website: str | None
    email: str | None
    social_identifiers: dict[str, str]
    category_ids: tuple[str, ...]
    category_labels: tuple[str, ...]
    date_created: date | None
    date_refreshed: date | None
    date_closed: date | None
    unresolved_flags: tuple[str, ...]


@dataclass
class FSQImportSummary:
    parsed: int = 0
    inserts: int = 0
    updates: int = 0
    matches: int = 0
    ambiguous: int = 0
    skipped: int = 0
    invalid: int = 0
    closed: int = 0

    def as_dict(self) -> dict[str, int]:
        return asdict(self)


@dataclass(frozen=True)
class _Candidate:
    place: Place
    distance_meters: float
    name_similarity: float
    category_compatible: bool


class FSQPlacesImporter:
    """Import FSQ OS Places while preserving canonical/manual place data.

    Matching is deliberately conservative: an automatic merge requires one
    and only one nearby place with an exact normalized name and a compatible
    broad category. Fuzzy names or multiple viable candidates are review work.
    The distance threshold is configurable because dense city centres and
    large campuses need different tolerances. A merge only attaches source and
    category rows; it never overwrites the canonical place's curated fields.
    """

    def __init__(
        self,
        *,
        distance_threshold_meters: float = 75.0,
        batch_size: int = 250,
    ) -> None:
        if distance_threshold_meters <= 0:
            raise ValueError("Distance threshold must be positive.")
        if batch_size <= 0:
            raise ValueError("Batch size must be positive.")
        self.distance_threshold_meters = distance_threshold_meters
        self.batch_size = batch_size

    def run(
        self,
        session: Session,
        *,
        source: Path,
        city_slug: str,
        dry_run: bool = False,
        limit: int | None = None,
    ) -> FSQImportSummary:
        if limit is not None and limit <= 0:
            raise ValueError("Limit must be positive when supplied.")
        city_config = get_import_city(city_slug)
        city = self._get_or_create_city(session, city_config)
        summary = FSQImportSummary()
        places = list(
            session.exec(select(Place).where(Place.city_id == city.id)).all()
        )

        try:
            for raw in read_source_records(source):
                if limit is not None and summary.parsed >= limit:
                    break
                summary.parsed += 1
                try:
                    record = parse_record(raw)
                except (TypeError, ValueError):
                    summary.invalid += 1
                    summary.skipped += 1
                    continue

                # This check happens before source/candidate database queries.
                if not _is_india(record.country) or not city_config.matches_locality(
                    record.locality
                ):
                    summary.skipped += 1
                    continue

                existing_source = session.exec(
                    select(PlaceSource).where(
                        PlaceSource.source == FSQ_PROVIDER,
                        PlaceSource.external_place_id == record.fsq_place_id,
                    )
                ).first()
                if existing_source is not None:
                    self._update_source(existing_source, record)
                    self._sync_categories(session, existing_source.place_id, record)
                    summary.updates += 1
                elif record.date_closed is not None:
                    # Keep closure metadata on already-known sources, but do not
                    # create a new canonical POI that is already marked closed.
                    summary.closed += 1
                    summary.skipped += 1
                else:
                    candidates = self._candidates(session, places, record)
                    high_confidence = [
                        candidate
                        for candidate in candidates
                        if candidate.name_similarity == 1.0
                        and candidate.category_compatible
                    ]
                    if len(high_confidence) == 1 and len(candidates) == 1:
                        place = high_confidence[0].place
                        self._add_source(session, place.id, record)
                        self._sync_categories(session, place.id, record)
                        summary.matches += 1
                    elif candidates:
                        self._upsert_review(session, city.id, record, candidates)
                        summary.ambiguous += 1
                    else:
                        place = self._create_place(city.id, record)
                        session.add(place)
                        session.flush()
                        places.append(place)
                        self._add_source(session, place.id, record)
                        self._sync_categories(session, place.id, record)
                        summary.inserts += 1

                if not dry_run and summary.parsed % self.batch_size == 0:
                    session.commit()

            if dry_run:
                session.rollback()
            else:
                session.commit()
        except Exception:
            session.rollback()
            raise
        return summary

    @staticmethod
    def _get_or_create_city(session: Session, config: ImportCity) -> City:
        city = session.exec(
            select(City).where(func.lower(City.name) == config.name.lower())
        ).first()
        if city is not None:
            return city
        city = City(
            name=config.name,
            state=config.state,
            country=config.country,
            latitude=config.latitude,
            longitude=config.longitude,
        )
        session.add(city)
        session.flush()
        return city

    def _candidates(
        self,
        session: Session,
        places: list[Place],
        record: FSQPlaceRecord,
    ) -> list[_Candidate]:
        record_name = normalize_text(record.name)
        record_category = _broad_category(record.category_labels)
        candidates: list[_Candidate] = []
        for place in places:
            distance = _haversine_meters(
                record.latitude,
                record.longitude,
                place.latitude,
                place.longitude,
            )
            if distance > self.distance_threshold_meters:
                continue
            similarity = SequenceMatcher(
                None, record_name, normalize_text(place.name)
            ).ratio()
            if similarity < 0.88:
                continue
            # One provider record per canonical place is enforced in the
            # existing schema. A second FSQ candidate must be reviewed.
            has_fsq_source = session.exec(
                select(PlaceSource).where(
                    PlaceSource.place_id == place.id,
                    PlaceSource.source == FSQ_PROVIDER,
                )
            ).first()
            category_compatible = _categories_compatible(
                record_category, normalize_text(place.category)
            )
            candidates.append(
                _Candidate(
                    place=place,
                    distance_meters=distance,
                    name_similarity=similarity,
                    category_compatible=category_compatible
                    and has_fsq_source is None,
                )
            )
        return candidates

    @staticmethod
    def _create_place(city_id: Any, record: FSQPlaceRecord) -> Place:
        return Place(
            city_id=city_id,
            name=record.name,
            category=_broad_category(record.category_labels) or "other",
            latitude=record.latitude,
            longitude=record.longitude,
            rating=None,
            review_count=0,
            is_popular=False,
            is_heritage=_broad_category(record.category_labels) == "heritage",
            is_local_speciality=False,
            last_fetched_at=datetime.now(timezone.utc),
        )

    def _add_source(
        self, session: Session, place_id: Any, record: FSQPlaceRecord
    ) -> None:
        now = datetime.now(timezone.utc)
        source = PlaceSource(
            place_id=place_id,
            source=FSQ_PROVIDER,
            external_place_id=record.fsq_place_id,
            last_fetched_at=now,
            imported_at=now,
        )
        self._update_source(source, record)
        session.add(source)

    @staticmethod
    def _update_source(
        source: PlaceSource,
        record: FSQPlaceRecord,
    ) -> None:
        now = datetime.now(timezone.utc)
        source.source_url = FSQ_SOURCE_URL.format(place_id=record.fsq_place_id)
        source.licence_identifier = FSQ_LICENCE
        source.address = record.address
        source.locality = record.locality
        source.region = record.region
        source.postcode = record.postcode
        source.country_code = _country_code(record.country)
        source.telephone = record.telephone
        source.website = record.website
        source.email = record.email
        source.social_identifiers = record.social_identifiers
        source.source_date_created = record.date_created
        source.source_date_refreshed = record.date_refreshed
        source.source_date_closed = record.date_closed
        source.unresolved_flags = list(record.unresolved_flags)
        source.last_fetched_at = now
        # imported_at records first ingestion; last_fetched_at changes on reruns.

    @staticmethod
    def _sync_categories(
        session: Session, place_id: Any, record: FSQPlaceRecord
    ) -> None:
        labels = list(record.category_labels)
        for index, category_id in enumerate(record.category_ids):
            label = labels[index] if index < len(labels) else None
            existing = session.exec(
                select(PlaceCategory).where(
                    PlaceCategory.place_id == place_id,
                    PlaceCategory.source == FSQ_PROVIDER,
                    PlaceCategory.external_category_id == category_id,
                )
            ).first()
            if existing is None:
                session.add(
                    PlaceCategory(
                        place_id=place_id,
                        source=FSQ_PROVIDER,
                        external_category_id=category_id,
                        label=label,
                    )
                )
            elif label:
                existing.label = label

    @staticmethod
    def _upsert_review(
        session: Session,
        city_id: Any,
        record: FSQPlaceRecord,
        candidates: list[_Candidate],
    ) -> None:
        review = session.exec(
            select(PlaceImportReview).where(
                PlaceImportReview.provider == FSQ_PROVIDER,
                PlaceImportReview.external_place_id == record.fsq_place_id,
            )
        ).first()
        now = datetime.now(timezone.utc)
        if review is None:
            review = PlaceImportReview(
                city_id=city_id,
                provider=FSQ_PROVIDER,
                external_place_id=record.fsq_place_id,
                reason="ambiguous_nearby_match",
                updated_at=now,
            )
            session.add(review)
        review.status = "pending"
        review.candidate_place_ids = [str(item.place.id) for item in candidates]
        review.match_details = {
            str(item.place.id): {
                "distance_meters": round(item.distance_meters, 2),
                "name_similarity": round(item.name_similarity, 4),
                "category_compatible": item.category_compatible,
            }
            for item in candidates
        }
        review.source_snapshot = {
            "name": record.name,
            "latitude": record.latitude,
            "longitude": record.longitude,
            "locality": record.locality,
            "category_ids": list(record.category_ids),
            "category_labels": list(record.category_labels),
        }
        review.updated_at = now


def read_source_records(path: Path) -> Iterator[Mapping[str, Any]]:
    if not path.is_file():
        raise ValueError(f"FSQ source file does not exist: {path}")
    suffix = path.suffix.casefold()
    if suffix == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as source:
            yield from csv.DictReader(source)
        return
    if suffix in {".jsonl", ".ndjson"}:
        with path.open("r", encoding="utf-8") as source:
            for line_number, line in enumerate(source, start=1):
                if not line.strip():
                    continue
                try:
                    value = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise ValueError(
                        f"Invalid JSONL at line {line_number}."
                    ) from exc
                if not isinstance(value, dict):
                    raise ValueError(
                        f"JSONL line {line_number} must contain an object."
                    )
                yield value
        return
    raise ValueError("FSQ source must be a .csv, .jsonl, or .ndjson file.")


def parse_record(raw: Mapping[str, Any]) -> FSQPlaceRecord:
    place_id = _required_text(raw.get("fsq_place_id"), "fsq_place_id")
    name = _required_text(raw.get("name"), "name")
    latitude = _coordinate(raw.get("latitude"), "latitude", -90, 90)
    longitude = _coordinate(raw.get("longitude"), "longitude", -180, 180)
    locality = _required_text(raw.get("locality"), "locality")
    country = _required_text(raw.get("country"), "country")
    category_ids = tuple(
        _parse_list(raw.get("fsq_category_ids") or raw.get("category_ids"))
    )
    category_labels = tuple(
        _parse_list(
            raw.get("fsq_category_labels") or raw.get("category_labels")
        )
    )
    return FSQPlaceRecord(
        fsq_place_id=place_id,
        name=name,
        latitude=latitude,
        longitude=longitude,
        address=_optional_text(raw.get("address")),
        locality=locality,
        region=_optional_text(raw.get("region")),
        postcode=_optional_text(raw.get("postcode")),
        country=country,
        telephone=_optional_text(raw.get("tel") or raw.get("telephone")),
        website=_optional_text(raw.get("website")),
        email=_optional_text(raw.get("email")),
        social_identifiers={
            key: value
            for key in ("facebook_id", "instagram", "twitter")
            if (value := _optional_text(raw.get(key))) is not None
        },
        category_ids=category_ids,
        category_labels=category_labels,
        date_created=_parse_date(raw.get("date_created")),
        date_refreshed=_parse_date(raw.get("date_refreshed")),
        date_closed=_parse_date(raw.get("date_closed")),
        unresolved_flags=tuple(_parse_list(raw.get("unresolved_flags"))),
    )


def _required_text(value: Any, field: str) -> str:
    normalized = _optional_text(value)
    if normalized is None:
        raise ValueError(f"{field} is required.")
    return normalized


def _optional_text(value: Any) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    return normalized or None


def _coordinate(value: Any, field: str, minimum: float, maximum: float) -> float:
    try:
        coordinate = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field} must be numeric.") from exc
    if not isfinite(coordinate) or not minimum <= coordinate <= maximum:
        raise ValueError(f"{field} is outside its valid range.")
    return coordinate


def _parse_date(value: Any) -> date | None:
    normalized = _optional_text(value)
    if normalized is None:
        return None
    try:
        return date.fromisoformat(normalized[:10])
    except ValueError as exc:
        raise ValueError("FSQ date fields must use ISO-8601 dates.") from exc


def _parse_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, (list, tuple, set)):
        return [str(item).strip() for item in value if str(item).strip()]
    normalized = str(value).strip()
    if not normalized:
        return []
    if normalized.startswith("["):
        try:
            parsed = json.loads(normalized)
        except json.JSONDecodeError as exc:
            raise ValueError("List fields must contain valid JSON arrays.") from exc
        if not isinstance(parsed, list):
            raise ValueError("List fields must contain JSON arrays.")
        return [str(item).strip() for item in parsed if str(item).strip()]
    separator = "|" if "|" in normalized else ";" if ";" in normalized else ","
    return [item.strip() for item in normalized.split(separator) if item.strip()]


def _country_code(value: str) -> str:
    normalized = normalize_text(value)
    return "in" if normalized in {"in", "ind", "india"} else normalized[:2]


def _is_india(value: str) -> bool:
    return normalize_text(value) in {"in", "ind", "india"}


def _broad_category(labels: tuple[str, ...]) -> str:
    value = " ".join(normalize_text(label) for label in labels)
    mappings = {
        "religious": ("temple", "mosque", "church", "shrine", "religious"),
        "food": ("restaurant", "cafe", "food", "bakery", "tea room"),
        "heritage": ("historic", "heritage", "monument", "museum", "palace"),
        "lodging": ("hotel", "hostel", "resort", "guest house", "lodging"),
        "nature": ("park", "garden", "nature", "lake"),
        "shopping": ("shop", "market", "mall"),
    }
    for broad, keywords in mappings.items():
        if any(keyword in value for keyword in keywords):
            return broad
    return ""


def _categories_compatible(imported: str, existing: str) -> bool:
    if not imported or existing in {"", "other", "uncategorized"}:
        return True
    return imported == existing or imported in existing or existing in imported


def _haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    lat1_r, lon1_r, lat2_r, lon2_r = map(radians, (lat1, lon1, lat2, lon2))
    delta_lat = lat2_r - lat1_r
    delta_lon = lon2_r - lon1_r
    value = sin(delta_lat / 2) ** 2 + cos(lat1_r) * cos(lat2_r) * sin(
        delta_lon / 2
    ) ** 2
    return 2 * 6_371_000 * asin(sqrt(value))
