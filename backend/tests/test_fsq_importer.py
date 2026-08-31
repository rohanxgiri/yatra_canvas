"""FSQ OS Places mapping, matching, and transaction tests."""

from collections.abc import Generator
from datetime import datetime, timezone
import json
from pathlib import Path

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.importers.fsq_os_places import FSQPlacesImporter, parse_record
from app.models import City, Place, PlaceImportReview, PlaceSource


@pytest.fixture
def session() -> Generator[Session, None, None]:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as value:
        yield value
    SQLModel.metadata.drop_all(engine)


def _record(**overrides: object) -> dict[str, object]:
    value: dict[str, object] = {
        "fsq_place_id": "fsq-mahakal",
        "name": "Mahakaleshwar Temple",
        "latitude": 23.1828,
        "longitude": 75.7682,
        "address": "Jaisinghpura",
        "locality": "Ujjain",
        "region": "Madhya Pradesh",
        "postcode": "456001",
        "country": "IN",
        "tel": "+91 00000 00000",
        "website": "https://example.test",
        "email": "hello@example.test",
        "facebook_id": "mahakal",
        "instagram": "mahakal_ujjain",
        "twitter": "mahakal",
        "fsq_category_ids": ["temple-category"],
        "fsq_category_labels": ["Hindu Temple"],
        "date_created": "2010-01-02",
        "date_refreshed": "2026-08-01",
        "date_closed": None,
        "unresolved_flags": ["address_needs_review"],
    }
    value.update(overrides)
    return value


def _source(tmp_path: Path, *records: dict[str, object]) -> Path:
    path = tmp_path / "places.jsonl"
    path.write_text(
        "".join(f"{json.dumps(record)}\n" for record in records),
        encoding="utf-8",
    )
    return path


def _city(session: Session) -> City:
    city = City(
        name="Ujjain",
        state="Madhya Pradesh",
        country="India",
        latitude=23.1765,
        longitude=75.7885,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


def test_valid_record_mapping_and_missing_optional_fields() -> None:
    mapped = parse_record(_record())
    assert mapped.fsq_place_id == "fsq-mahakal"
    assert mapped.category_ids == ("temple-category",)
    assert mapped.social_identifiers["instagram"] == "mahakal_ujjain"
    assert mapped.date_refreshed is not None

    minimal = parse_record(
        _record(
            address=None,
            tel=None,
            website=None,
            email=None,
            facebook_id=None,
            instagram=None,
            twitter=None,
            fsq_category_ids=None,
            fsq_category_labels=None,
            unresolved_flags=None,
        )
    )
    assert minimal.address is None
    assert minimal.social_identifiers == {}
    assert minimal.category_ids == ()


@pytest.mark.parametrize(
    ("field", "value"),
    [("latitude", 91), ("latitude", "NaN"), ("longitude", -181)],
)
def test_invalid_coordinates_are_rejected(field: str, value: object) -> None:
    with pytest.raises(ValueError):
        parse_record(_record(**{field: value}))


def test_city_filtering_closed_places_and_dry_run(
    session: Session, tmp_path: Path
) -> None:
    source = _source(
        tmp_path,
        _record(fsq_place_id="outside", locality="Indore"),
        _record(fsq_place_id="closed", date_closed="2025-01-01"),
        _record(fsq_place_id="valid"),
    )
    summary = FSQPlacesImporter().run(
        session,
        source=source,
        city_slug="ujjain",
        dry_run=True,
    )
    assert summary.parsed == 3
    assert summary.inserts == 1
    assert summary.closed == 1
    assert summary.skipped == 2
    assert session.exec(select(City)).all() == []
    assert session.exec(select(Place)).all() == []


def test_repeated_import_is_idempotent_and_updates_source(
    session: Session, tmp_path: Path
) -> None:
    importer = FSQPlacesImporter(batch_size=1)
    first = importer.run(
        session,
        source=_source(tmp_path, _record()),
        city_slug="ujjain",
    )
    assert first.inserts == 1
    stored_source = session.exec(select(PlaceSource)).one()
    imported_at = stored_source.imported_at

    updated_path = tmp_path / "updated.jsonl"
    updated_path.write_text(
        json.dumps(_record(website="https://updated.example.test")) + "\n",
        encoding="utf-8",
    )
    second = importer.run(session, source=updated_path, city_slug="ujjain")
    assert second.updates == 1
    assert len(session.exec(select(Place)).all()) == 1
    assert len(session.exec(select(PlaceSource)).all()) == 1
    stored_source = session.exec(select(PlaceSource)).one()
    assert stored_source.website == "https://updated.example.test"
    assert stored_source.imported_at == imported_at


def test_high_confidence_osm_match_preserves_manual_fields(
    session: Session, tmp_path: Path
) -> None:
    city = _city(session)
    place = Place(
        city_id=city.id,
        name="Mahakaleshwar Temple",
        category="religious",
        latitude=23.18281,
        longitude=75.76821,
        rating=4.9,
        review_count=123,
        is_popular=True,
        is_heritage=True,
        is_local_speciality=False,
    )
    session.add(place)
    session.commit()
    session.refresh(place)
    session.add(
        PlaceSource(
            place_id=place.id,
            source="osm",
            external_place_id="node/123",
            licence_identifier="ODbL-1.0",
            last_fetched_at=datetime.now(timezone.utc),
        )
    )
    session.commit()

    summary = FSQPlacesImporter().run(
        session,
        source=_source(tmp_path, _record()),
        city_slug="ujjain",
    )
    assert summary.matches == 1
    session.refresh(place)
    assert place.rating == 4.9
    assert place.review_count == 123
    assert place.is_popular is True
    assert len(session.exec(select(PlaceSource)).all()) == 2


def test_ambiguous_nearby_match_creates_review(
    session: Session, tmp_path: Path
) -> None:
    city = _city(session)
    session.add_all(
        [
            Place(
                city_id=city.id,
                name="Mahakaleshwar Temple",
                category="religious",
                latitude=23.18280,
                longitude=75.76820,
            ),
            Place(
                city_id=city.id,
                name="Mahakaleshwar Temple",
                category="religious",
                latitude=23.18285,
                longitude=75.76825,
            ),
        ]
    )
    session.commit()

    summary = FSQPlacesImporter().run(
        session,
        source=_source(tmp_path, _record()),
        city_slug="ujjain",
    )
    assert summary.ambiguous == 1
    review = session.exec(select(PlaceImportReview)).one()
    assert review.status == "pending"
    assert len(review.candidate_place_ids) == 2
    assert len(session.exec(select(Place)).all()) == 2


def test_existing_fsq_source_records_closure(
    session: Session, tmp_path: Path
) -> None:
    importer = FSQPlacesImporter()
    importer.run(
        session,
        source=_source(tmp_path, _record()),
        city_slug="ujjain",
    )
    closed_path = tmp_path / "closed.jsonl"
    closed_path.write_text(
        json.dumps(_record(date_closed="2026-08-30")) + "\n",
        encoding="utf-8",
    )
    summary = importer.run(session, source=closed_path, city_slug="ujjain")
    assert summary.updates == 1
    assert session.exec(select(PlaceSource)).one().source_date_closed is not None
