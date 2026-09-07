"""Canonical multi-source Place identity resolution and provenance service.

Resolves place identity across multiple providers (e.g., OpenStreetMap, Audiala)
into a single canonical Place record while maintaining complete provider-specific
provenance, licensing, and metadata in PlaceSource records.
"""

from datetime import datetime, timezone
import logging
import math
import re
from typing import Any, Final
from uuid import UUID

from sqlmodel import Session, select

from app.models import City, Place, PlaceOpeningHours, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.opening_hours_parser import OpeningHoursParser
from app.services.place_deduplication_service import (
    haversine_distance_meters,
    normalize_name_for_dedupe,
)
from app.services.place_importance_scorer import PlaceImportanceScorer

logger = logging.getLogger(__name__)

WIKIDATA_QID_PATTERN: Final[re.Pattern] = re.compile(r"^Q\d+$")

# Conservative distance threshold for geographic fallback matching
MAX_FALLBACK_DISTANCE_METERS: Final[float] = 100.0

# Compatible category pairs for fallback matching
COMPATIBLE_CATEGORY_PAIRS: Final[list[set[str]]] = [
    {"heritage", "tourism"},
    {"heritage", "religious"},
    {"food", "cafes"},
    {"food", "markets"},
]

# Generic Indian honorifics or qualifiers that often vary between data sources
ALLOWED_HONORIFIC_OR_QUALIFIER_VARIANTS: Final[set[str]] = {
    "devi",
    "ji",
    "shree",
    "shri",
    "sri",
    "baba",
    "swami",
    "saint",
    "st",
    "mandir",
    "temple",
}


def extract_wikidata_id(
    external_place_id: str | None = None,
    tags: dict[str, str] | None = None,
) -> str | None:
    """Extract and validate a Wikidata QID from tags or external ID."""
    if tags:
        for key in ("wikidata", "wikidata_id"):
            val = tags.get(key)
            if val and isinstance(val, str):
                cleaned = val.strip().upper()
                if WIKIDATA_QID_PATTERN.match(cleaned):
                    return cleaned

    if external_place_id and isinstance(external_place_id, str):
        cleaned = external_place_id.strip().upper()
        if WIKIDATA_QID_PATTERN.match(cleaned):
            return cleaned

    return None


def is_category_compatible(cat1: str, cat2: str) -> bool:
    """Check if two categories can refer to the same physical entity."""
    c1 = cat1.casefold().strip()
    c2 = cat2.casefold().strip()
    if c1 == c2:
        return True
    category_set = {c1, c2}
    return any(category_set.issubset(pair) for pair in COMPATIBLE_CATEGORY_PAIRS)


def is_conservative_name_match(name1: str, name2: str) -> bool:
    """Check if two names refer to the same venue with high confidence.

    Prefers false negatives over incorrect merges.
    """
    n1 = normalize_name_for_dedupe(name1)
    n2 = normalize_name_for_dedupe(name2)
    if not n1 or not n2:
        return False
    if n1 == n2:
        return True

    tokens1 = [t for t in n1.split() if t]
    tokens2 = [t for t in n2.split() if t]
    if tokens1 == tokens2:
        return True

    set1 = set(tokens1)
    set2 = set(tokens2)
    if set1 == set2:
        return True

    # Subset matching: only allowed when length difference <= 1 and min tokens >= 2,
    # and the differing token is a recognized benign variant (e.g. "Devi", "Mandir")
    if len(set1) >= 2 and len(set2) >= 2:
        diff = set1 ^ set2
        if len(diff) <= 1 and diff.issubset(ALLOWED_HONORIFIC_OR_QUALIFIER_VARIANTS):
            if set1.issubset(set2) or set2.issubset(set1):
                return True

    return False


class CanonicalPlaceService:
    """Central service resolving place identity and managing multi-source provenance."""

    def resolve_or_create_place(
        self,
        session: Session,
        city: City,
        category: DiscoveryCategory | str,
        *,
        name: str,
        latitude: float,
        longitude: float,
        external_place_id: str,
        source_name: str,
        licence_identifier: str,
        source_url: str | None = None,
        tags: dict[str, str] | None = None,
        telephone: str | None = None,
        website: str | None = None,
        wikidata_id: str | None = None,
        raw_opening_hours: str | None = None,
        fetched_at: datetime | None = None,
    ) -> tuple[Place, PlaceSource]:
        """Resolve candidate place to a canonical Place row and upsert PlaceSource.

        Identity resolution hierarchy:
        1. Existing source identity: (source_name, external_place_id)
        2. Strong global identifier: Wikidata QID (from tags or external_place_id)
        3. Conservative geographic fallback: distance <= 100m, compatible category,
           conservative name match
        4. New canonical Place creation
        """
        now = fetched_at or datetime.now(timezone.utc)
        cat_str = category.value if isinstance(category, DiscoveryCategory) else str(category)
        is_heritage_cat = cat_str == DiscoveryCategory.HERITAGE.value

        # Extract effective raw opening hours
        effective_raw_opening_hours = (
            raw_opening_hours
            or (tags.get("opening_hours") if tags else None)
        )
        if effective_raw_opening_hours and isinstance(effective_raw_opening_hours, str):
            effective_raw_opening_hours = effective_raw_opening_hours.strip() or None

        # Extract strong Wikidata ID
        effective_wikidata_id = wikidata_id or extract_wikidata_id(
            external_place_id=external_place_id,
            tags=tags,
        )

        # Extract prominence score and raw metrics
        prominence = PlaceImportanceScorer.extract_prominence_from_tags(tags)
        raw_metrics = PlaceImportanceScorer.extract_metrics_from_tags(tags)
        if prominence == 0.0 and effective_wikidata_id:
            audiala_prom = PlaceImportanceScorer.lookup_audiala_prominence(effective_wikidata_id)
            if audiala_prom is not None:
                prominence = audiala_prom
                raw_metrics = PlaceImportanceScorer.lookup_audiala_metrics(effective_wikidata_id)

        # ---------------------------------------------------------------------
        # Rule 1: Existing Provider Identity (source, external_place_id)
        # ---------------------------------------------------------------------
        existing_source = session.exec(
            select(PlaceSource).where(
                PlaceSource.source == source_name,
                PlaceSource.external_place_id == external_place_id,
            )
        ).first()

        if existing_source is not None:
            place = session.get(Place, existing_source.place_id)
            if place is not None:
                # Update source metadata
                existing_source.last_fetched_at = now
                if source_url:
                    existing_source.source_url = self._bounded(source_url, 1000)
                if telephone:
                    existing_source.telephone = self._bounded(telephone, 80)
                if website:
                    existing_source.website = self._bounded(website, 1000)
                if effective_wikidata_id and not existing_source.wikidata_id:
                    existing_source.wikidata_id = effective_wikidata_id
                if raw_metrics:
                    existing_source.social_identifiers = {
                        **existing_source.social_identifiers,
                        **raw_metrics,
                    }
                if effective_raw_opening_hours:
                    existing_source.raw_opening_hours = effective_raw_opening_hours

                # Update canonical place metadata if missing
                if effective_wikidata_id and not place.wikidata_id:
                    place.wikidata_id = effective_wikidata_id
                if is_heritage_cat:
                    place.is_heritage = True
                if prominence > 0.0:
                    if place.importance_score is None or prominence > place.importance_score:
                        place.importance_score = prominence
                place.last_fetched_at = now

                # Ingest opening hours if provided and place doesn't already have them
                if effective_raw_opening_hours:
                    place.raw_opening_hours = effective_raw_opening_hours
                    place.opening_hours_status = self._upsert_place_opening_hours(
                        session, place.id, effective_raw_opening_hours
                    )
                elif not place.opening_hours_status:
                    place.opening_hours_status = "UNKNOWN"

                session.flush()
                self._ensure_place_tag(session, place.id, cat_str)
                return place, existing_source

        # ---------------------------------------------------------------------
        # Rule 2: Shared Strong Global Identifier (Wikidata QID)
        # ---------------------------------------------------------------------
        if effective_wikidata_id:
            # Check for Place with matching wikidata_id in the same city
            matched_place = session.exec(
                select(Place).where(
                    Place.city_id == city.id,
                    Place.wikidata_id == effective_wikidata_id,
                )
            ).first()

            # Check if an existing PlaceSource in the same city shares this wikidata_id
            if matched_place is None:
                matched_source = session.exec(
                    select(PlaceSource)
                    .join(Place, Place.id == PlaceSource.place_id)
                    .where(
                        Place.city_id == city.id,
                        PlaceSource.wikidata_id == effective_wikidata_id,
                    )
                ).first()
                if matched_source is not None:
                    matched_place = session.get(Place, matched_source.place_id)

            # Check if an existing PlaceSource has source="audiala" and external_place_id == wikidata_id
            if matched_place is None:
                matched_audiala = session.exec(
                    select(PlaceSource)
                    .join(Place, Place.id == PlaceSource.place_id)
                    .where(
                        Place.city_id == city.id,
                        PlaceSource.source == "audiala",
                        PlaceSource.external_place_id == effective_wikidata_id,
                    )
                ).first()
                if matched_audiala is not None:
                    matched_place = session.get(Place, matched_audiala.place_id)

            if matched_place is not None:
                logger.info(
                    "Resolved canonical Place via Wikidata QID=%s: place_id=%s ('%s')",
                    effective_wikidata_id,
                    matched_place.id,
                    matched_place.name,
                )
                if not matched_place.wikidata_id:
                    matched_place.wikidata_id = effective_wikidata_id
                if is_heritage_cat:
                    matched_place.is_heritage = True
                if prominence > 0.0:
                    if matched_place.importance_score is None or prominence > matched_place.importance_score:
                        matched_place.importance_score = prominence
                matched_place.last_fetched_at = now

                source = self._upsert_place_source(
                    session=session,
                    place_id=matched_place.id,
                    source_name=source_name,
                    external_place_id=external_place_id,
                    licence_identifier=licence_identifier,
                    wikidata_id=effective_wikidata_id,
                    source_url=source_url,
                    telephone=telephone,
                    website=website,
                    social_identifiers=raw_metrics,
                    raw_opening_hours=effective_raw_opening_hours,
                    fetched_at=now,
                )

                if effective_raw_opening_hours and (
                    not matched_place.raw_opening_hours
                    or matched_place.opening_hours_status == "UNKNOWN"
                ):
                    matched_place.raw_opening_hours = effective_raw_opening_hours
                    matched_place.opening_hours_status = self._upsert_place_opening_hours(
                        session, matched_place.id, effective_raw_opening_hours
                    )
                elif not matched_place.opening_hours_status:
                    matched_place.opening_hours_status = "UNKNOWN"

                session.flush()
                self._ensure_place_tag(session, matched_place.id, cat_str)
                return matched_place, source

        # ---------------------------------------------------------------------
        # Rule 3: Conservative Geographic & Name Fallback Matching
        # ---------------------------------------------------------------------
        # Bounding box candidate query (~100m)
        lat_delta = (MAX_FALLBACK_DISTANCE_METERS + 20.0) / 111_000.0
        lon_delta = (MAX_FALLBACK_DISTANCE_METERS + 20.0) / (
            111_000.0 * max(0.2, math.cos(math.radians(latitude)))
        )

        candidates = session.exec(
            select(Place).where(
                Place.city_id == city.id,
                Place.latitude >= latitude - lat_delta,
                Place.latitude <= latitude + lat_delta,
                Place.longitude >= longitude - lon_delta,
                Place.longitude <= longitude + lon_delta,
            )
        ).all()

        matched_fallback_place: Place | None = None
        for candidate in candidates:
            dist = haversine_distance_meters(
                latitude, longitude, candidate.latitude, candidate.longitude
            )
            if dist > MAX_FALLBACK_DISTANCE_METERS:
                continue

            if not is_category_compatible(cat_str, candidate.category):
                continue

            if is_conservative_name_match(name, candidate.name):
                matched_fallback_place = candidate
                break

        if matched_fallback_place is not None:
            logger.info(
                "Resolved canonical Place via conservative fallback: place_id=%s ('%s' ~ '%s')",
                matched_fallback_place.id,
                matched_fallback_place.name,
                name,
            )
            if effective_wikidata_id and not matched_fallback_place.wikidata_id:
                matched_fallback_place.wikidata_id = effective_wikidata_id
            if is_heritage_cat:
                matched_fallback_place.is_heritage = True
            if prominence > 0.0:
                if matched_fallback_place.importance_score is None or prominence > matched_fallback_place.importance_score:
                    matched_fallback_place.importance_score = prominence
            matched_fallback_place.last_fetched_at = now

            source = self._upsert_place_source(
                session=session,
                place_id=matched_fallback_place.id,
                source_name=source_name,
                external_place_id=external_place_id,
                licence_identifier=licence_identifier,
                wikidata_id=effective_wikidata_id,
                source_url=source_url,
                telephone=telephone,
                website=website,
                social_identifiers=raw_metrics,
                raw_opening_hours=effective_raw_opening_hours,
                fetched_at=now,
            )

            if effective_raw_opening_hours and (
                not matched_fallback_place.raw_opening_hours
                or matched_fallback_place.opening_hours_status == "UNKNOWN"
            ):
                matched_fallback_place.raw_opening_hours = effective_raw_opening_hours
                matched_fallback_place.opening_hours_status = self._upsert_place_opening_hours(
                    session, matched_fallback_place.id, effective_raw_opening_hours
                )
            elif not matched_fallback_place.opening_hours_status:
                matched_fallback_place.opening_hours_status = "UNKNOWN"

            session.flush()
            self._ensure_place_tag(session, matched_fallback_place.id, cat_str)
            return matched_fallback_place, source

        # ---------------------------------------------------------------------
        # Rule 4: New Canonical Place Creation
        # ---------------------------------------------------------------------
        oh_status = "UNKNOWN"
        if effective_raw_opening_hours:
            parsed_hours = OpeningHoursParser.parse(effective_raw_opening_hours)
            oh_status = parsed_hours.status.value

        new_place = Place(
            city_id=city.id,
            name=name,
            category=cat_str,
            latitude=latitude,
            longitude=longitude,
            rating=None,
            review_count=0,
            is_popular=False,
            is_heritage=is_heritage_cat,
            is_local_speciality=False,
            wikidata_id=effective_wikidata_id,
            importance_score=prominence if prominence > 0.0 else None,
            last_fetched_at=now,
            opening_hours_status=oh_status,
            raw_opening_hours=effective_raw_opening_hours,
        )
        session.add(new_place)
        session.flush()

        if effective_raw_opening_hours:
            self._upsert_place_opening_hours(
                session, new_place.id, effective_raw_opening_hours
            )

        source = self._upsert_place_source(
            session=session,
            place_id=new_place.id,
            source_name=source_name,
            external_place_id=external_place_id,
            licence_identifier=licence_identifier,
            wikidata_id=effective_wikidata_id,
            source_url=source_url,
            telephone=telephone,
            website=website,
            social_identifiers=raw_metrics,
            raw_opening_hours=effective_raw_opening_hours,
            fetched_at=now,
        )
        session.flush()
        self._ensure_place_tag(session, new_place.id, cat_str)
        return new_place, source

    def resolve_or_create_nearby_place(
        self,
        session: Session,
        city: City,
        category: DiscoveryCategory,
        nearby: Any,
        source_name: str,
        licence_identifier: str,
        fetched_at: datetime | None = None,
    ) -> tuple[Place, PlaceSource]:
        """Convenience wrapper accepting an OpenStreetMapNearbyPlace instance."""
        tags = getattr(nearby, "tags", {}) or {}
        raw_hours = tags.get("opening_hours")
        return self.resolve_or_create_place(
            session=session,
            city=city,
            category=category,
            name=nearby.name,
            latitude=nearby.latitude,
            longitude=nearby.longitude,
            external_place_id=nearby.external_place_id,
            source_name=source_name,
            licence_identifier=licence_identifier,
            source_url=getattr(nearby, "source_url", None),
            tags=tags,
            telephone=self._bounded(tags.get("phone"), 80),
            website=self._bounded(tags.get("website"), 1000),
            wikidata_id=extract_wikidata_id(nearby.external_place_id, tags),
            raw_opening_hours=raw_hours,
            fetched_at=fetched_at,
        )

    def _upsert_place_source(
        self,
        session: Session,
        place_id: UUID,
        source_name: str,
        external_place_id: str,
        licence_identifier: str,
        wikidata_id: str | None,
        source_url: str | None,
        telephone: str | None,
        website: str | None,
        fetched_at: datetime,
        social_identifiers: dict[str, str] | None = None,
        raw_opening_hours: str | None = None,
    ) -> PlaceSource:
        """Upsert PlaceSource record respecting database uniqueness constraints."""
        # Check by (source, external_place_id)
        source = session.exec(
            select(PlaceSource).where(
                PlaceSource.source == source_name,
                PlaceSource.external_place_id == external_place_id,
            )
        ).first()

        if source is not None:
            source.place_id = place_id
            source.last_fetched_at = fetched_at
            if wikidata_id and not source.wikidata_id:
                source.wikidata_id = wikidata_id
            if licence_identifier:
                source.licence_identifier = licence_identifier
            if source_url:
                source.source_url = self._bounded(source_url, 1000)
            if telephone:
                source.telephone = self._bounded(telephone, 80)
            if website:
                source.website = self._bounded(website, 1000)
            if social_identifiers:
                source.social_identifiers = {
                    **source.social_identifiers,
                    **social_identifiers,
                }
            if raw_opening_hours:
                source.raw_opening_hours = raw_opening_hours
            return source

        # Check by (place_id, source)
        source = session.exec(
            select(PlaceSource).where(
                PlaceSource.place_id == place_id,
                PlaceSource.source == source_name,
            )
        ).first()

        if source is not None:
            source.external_place_id = external_place_id
            source.last_fetched_at = fetched_at
            if wikidata_id and not source.wikidata_id:
                source.wikidata_id = wikidata_id
            if licence_identifier:
                source.licence_identifier = licence_identifier
            if source_url:
                source.source_url = self._bounded(source_url, 1000)
            if telephone:
                source.telephone = self._bounded(telephone, 80)
            if website:
                source.website = self._bounded(website, 1000)
            if social_identifiers:
                source.social_identifiers = {
                    **source.social_identifiers,
                    **social_identifiers,
                }
            if raw_opening_hours:
                source.raw_opening_hours = raw_opening_hours
            return source

        new_source = PlaceSource(
            place_id=place_id,
            source=source_name,
            external_place_id=external_place_id,
            wikidata_id=wikidata_id,
            licence_identifier=licence_identifier,
            source_url=self._bounded(source_url, 1000),
            telephone=self._bounded(telephone, 80),
            website=self._bounded(website, 1000),
            social_identifiers=social_identifiers or {},
            raw_opening_hours=raw_opening_hours,
            last_fetched_at=fetched_at,
        )
        session.add(new_source)
        return new_source

    def _upsert_place_opening_hours(
        self,
        session: Session,
        place_id: UUID,
        raw_opening_hours: str | None,
    ) -> str:
        """Parse raw opening hours, upsert PlaceOpeningHours records, and return overall status."""
        parsed = OpeningHoursParser.parse(raw_opening_hours)
        now = datetime.now(timezone.utc)

        existing_hours = session.exec(
            select(PlaceOpeningHours).where(PlaceOpeningHours.place_id == place_id)
        ).all()
        by_day = {h.day_of_week: h for h in existing_hours}

        for day_idx, schedule in parsed.days.items():
            existing = by_day.get(day_idx)
            intervals_data = schedule.intervals_dicts()
            if existing is not None:
                existing.status = schedule.status.value
                existing.intervals = intervals_data
                existing.updated_at = now
            else:
                new_entry = PlaceOpeningHours(
                    place_id=place_id,
                    day_of_week=day_idx,
                    status=schedule.status.value,
                    intervals=intervals_data,
                    created_at=now,
                    updated_at=now,
                )
                session.add(new_entry)

        return parsed.status.value

    @staticmethod
    def _ensure_place_tag(session: Session, place_id: UUID, tag: str) -> None:
        """Ensure PlaceTag exists for the given place and category tag."""
        existing = session.exec(
            select(PlaceTag).where(
                PlaceTag.place_id == place_id,
                PlaceTag.tag == tag,
            )
        ).first()
        if existing is None:
            session.add(PlaceTag(place_id=place_id, tag=tag))

    @staticmethod
    def _bounded(value: str | None, max_len: int) -> str | None:
        if value is None:
            return None
        stripped = value.strip()
        if not stripped:
            return None
        return stripped[:max_len]
