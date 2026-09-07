"""Tests for opening-hours ingestion, parsing, normalization, persistence, and helpers."""

from collections.abc import Generator
from datetime import date, datetime, time, timezone
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.models import City, Place, PlaceOpeningHours, PlaceSource
from app.schemas import DiscoveryCategory, PlaceRead
from app.services.canonical_place_service import CanonicalPlaceService
from app.services.opening_hours_parser import (
    DAY_NAMES,
    OpeningHoursParser,
    OpeningHoursStatus,
    TimeInterval,
)
from app.services.openstreetmap_places_service import OpenStreetMapNearbyPlace


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


@pytest.fixture
def sample_city(session: Session) -> City:
    city = City(
        name="Madurai",
        state="Tamil Nadu",
        country="India",
        latitude=9.9252,
        longitude=78.1198,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


# ---------------------------------------------------------------------------
# Parser Unit Tests
# ---------------------------------------------------------------------------

def test_single_daily_interval():
    """Requirement 1: single daily interval."""
    raw = "Mo-Fr 09:00-17:00"
    parsed = OpeningHoursParser.parse(raw)

    assert parsed.status == OpeningHoursStatus.KNOWN
    assert parsed.raw_text == raw

    # Monday through Friday (0..4) should have single interval 09:00-17:00
    for day_idx in range(5):
        day = parsed.days[day_idx]
        assert day.status == OpeningHoursStatus.KNOWN
        assert len(day.intervals) == 1
        assert day.intervals[0].open == "09:00"
        assert day.intervals[0].close == "17:00"

    # Saturday and Sunday (5, 6) should be closed (no intervals)
    assert parsed.days[5].status == OpeningHoursStatus.CLOSED
    assert len(parsed.days[5].intervals) == 0
    assert parsed.days[6].status == OpeningHoursStatus.CLOSED
    assert len(parsed.days[6].intervals) == 0


def test_multiple_intervals_in_one_day_split_schedule():
    """Requirement 2 & 17: multiple intervals in one day (e.g. 09:00-11:00, 14:00-22:00)."""
    raw = "Mo 09:00-11:00,14:00-22:00; Tu 09:00-18:00"
    parsed = OpeningHoursParser.parse(raw)

    assert parsed.status == OpeningHoursStatus.KNOWN
    mon = parsed.days[0]
    assert mon.status == OpeningHoursStatus.KNOWN
    assert len(mon.intervals) == 2
    assert mon.intervals[0].open == "09:00"
    assert mon.intervals[0].close == "11:00"
    assert mon.intervals[1].open == "14:00"
    assert mon.intervals[1].close == "22:00"

    tue = parsed.days[1]
    assert tue.status == OpeningHoursStatus.KNOWN
    assert len(tue.intervals) == 1
    assert tue.intervals[0].open == "09:00"
    assert tue.intervals[0].close == "18:00"

    # Verify helper behaves correctly on split schedule
    # 2026-09-07 is Monday
    dt_morning = datetime(2026, 9, 7, 10, 0)
    dt_lunch = datetime(2026, 9, 7, 12, 30)
    dt_evening = datetime(2026, 9, 7, 16, 0)
    dt_night = datetime(2026, 9, 7, 23, 0)

    assert parsed.is_open_at(dt_morning) is True
    assert parsed.is_open_at(dt_lunch) is False  # between split intervals
    assert parsed.is_open_at(dt_evening) is True
    assert parsed.is_open_at(dt_night) is False


def test_weekday_ranges():
    """Requirement 3: weekday ranges (e.g. Mo-Sa 10:00-19:00)."""
    raw = "Mo-Sa 10:00-19:00"
    parsed = OpeningHoursParser.parse(raw)

    assert parsed.status == OpeningHoursStatus.KNOWN
    for day_idx in range(6):  # Monday to Saturday
        day = parsed.days[day_idx]
        assert day.status == OpeningHoursStatus.KNOWN
        assert len(day.intervals) == 1
        assert day.intervals[0].open == "10:00"
        assert day.intervals[0].close == "19:00"

    # Sunday
    assert parsed.days[6].status == OpeningHoursStatus.CLOSED


def test_closed_off_days():
    """Requirement 4: closed/off days."""
    raw = "Mo-Fr 09:00-18:00; Sa-Su off"
    parsed = OpeningHoursParser.parse(raw)

    assert parsed.status == OpeningHoursStatus.KNOWN
    assert parsed.days[5].status == OpeningHoursStatus.CLOSED
    assert len(parsed.days[5].intervals) == 0
    assert parsed.days[6].status == OpeningHoursStatus.CLOSED
    assert len(parsed.days[6].intervals) == 0

    # Explicit global closed
    closed_parsed = OpeningHoursParser.parse("closed")
    assert closed_parsed.status == OpeningHoursStatus.CLOSED
    assert all(d.status == OpeningHoursStatus.CLOSED for d in closed_parsed.days.values())

    off_parsed = OpeningHoursParser.parse("off")
    assert off_parsed.status == OpeningHoursStatus.CLOSED


def test_unknown_missing_hours():
    """Requirement 5: unknown/missing hours."""
    for empty_val in [None, "", "   ", "\n"]:
        parsed = OpeningHoursParser.parse(empty_val)
        assert parsed.status == OpeningHoursStatus.UNKNOWN
        assert all(d.status == OpeningHoursStatus.UNKNOWN for d in parsed.days.values())
        assert all(len(d.intervals) == 0 for d in parsed.days.values())


def test_malformed_string_safe():
    """Requirement 6 & 7: malformed opening-hours string does not crash and marks UNKNOWN."""
    malformed_inputs = [
        "not an opening hour string at all",
        "Mo 25:00-26:00",
        "!!! @@ ### $$$",
        "Mo-Fr invalid_time",
        "123456789",
    ]
    for raw in malformed_inputs:
        parsed = OpeningHoursParser.parse(raw)
        assert parsed.status == OpeningHoursStatus.UNKNOWN
        assert parsed.raw_text == raw
        assert all(d.status == OpeningHoursStatus.UNKNOWN for d in parsed.days.values())


def test_unknown_is_not_interpreted_as_open():
    """Requirement 8: UNKNOWN must never be interpreted as open (indeterminate None)."""
    parsed = OpeningHoursParser.parse("not a valid time")
    dt = datetime(2026, 9, 7, 12, 0)

    # is_open_at must return None, NOT True
    result = parsed.is_open_at(dt)
    assert result is None
    assert result is not True

    # can_visit_between must return None, NOT True
    visit_result = parsed.can_visit_between(
        datetime(2026, 9, 7, 10, 0),
        datetime(2026, 9, 7, 12, 0),
    )
    assert visit_result is None
    assert visit_result is not True


def test_overnight_hours_handling():
    """Overnight schedule: 18:00-02:00 splits across midnight."""
    raw = "Mo 18:00-02:00"
    parsed = OpeningHoursParser.parse(raw)

    assert parsed.status == OpeningHoursStatus.KNOWN
    # Monday (day 0) gets 18:00-24:00
    mon_intervals = parsed.days[0].intervals
    assert any(i.open == "18:00" and i.close == "24:00" for i in mon_intervals)

    # Tuesday (day 1) gets 00:00-02:00
    tue_intervals = parsed.days[1].intervals
    assert any(i.open == "00:00" and i.close == "02:00" for i in tue_intervals)

    # Monday 20:00 is open
    assert parsed.is_open_at(datetime(2026, 9, 7, 20, 0)) is True
    # Tuesday 01:00 is open
    assert parsed.is_open_at(datetime(2026, 9, 8, 1, 0)) is True
    # Tuesday 03:00 is closed
    assert parsed.is_open_at(datetime(2026, 9, 8, 3, 0)) is False


def test_twenty_four_seven_handling():
    """24/7 hours handling."""
    for raw in ["24/7", "open 24/7", "all day"]:
        parsed = OpeningHoursParser.parse(raw)
        assert parsed.status == OpeningHoursStatus.KNOWN
        assert all(len(d.intervals) == 1 for d in parsed.days.values())
        assert all(d.intervals[0].open == "00:00" and d.intervals[0].close == "24:00" for d in parsed.days.values())
        assert parsed.is_open_at(datetime(2026, 9, 7, 3, 30)) is True


def test_helper_methods():
    """Section 11: helper methods get_intervals_for_day, can_visit_between, get_next_opening."""
    raw = "Mo-Fr 09:00-18:00; Sa 10:00-14:00"
    parsed = OpeningHoursParser.parse(raw)

    # get_intervals_for_day
    # 2026-09-07 is Monday
    mon_intervals = parsed.get_intervals_for_day(date(2026, 9, 7))
    assert len(mon_intervals) == 1
    assert mon_intervals[0].open == "09:00"

    # can_visit_between
    # Fits within 09:00-18:00
    assert parsed.can_visit_between(
        datetime(2026, 9, 7, 10, 0),
        datetime(2026, 9, 7, 12, 0),
    ) is True
    # Exceeds closing time
    assert parsed.can_visit_between(
        datetime(2026, 9, 7, 17, 0),
        datetime(2026, 9, 7, 19, 0),
    ) is False

    # get_next_opening
    # On Sunday morning (closed), next opening should be Monday 09:00
    sunday_morning = datetime(2026, 9, 6, 10, 0)
    next_open = parsed.get_next_opening(sunday_morning)
    assert next_open is not None
    assert next_open == datetime(2026, 9, 7, 9, 0)


# ---------------------------------------------------------------------------
# Canonical Place Service & Persistence Tests
# ---------------------------------------------------------------------------

def test_osm_provider_preserves_opening_hours_and_persists(
    session: Session, sample_city: City
):
    """Requirement 9 & 10: OSM provider preserves opening_hours tag and persists."""
    service = CanonicalPlaceService()
    raw_hours = "Mo-Fr 09:00-11:00,14:00-22:00; Sa 10:00-18:00; Su off"

    nearby = OpenStreetMapNearbyPlace(
        external_place_id="node/12345",
        name="Meenakshi Sundareswarar Temple",
        latitude=9.9195,
        longitude=78.1193,
        source_url="https://www.openstreetmap.org/node/12345",
        tags={
            "name": "Meenakshi Sundareswarar Temple",
            "opening_hours": raw_hours,
            "phone": "+91 452 234 4360",
        },
    )

    place, place_source = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        nearby=nearby,
        source_name="openstreetmap",
        licence_identifier="ODbL",
    )
    session.commit()

    # Verify place entity fields
    assert place.raw_opening_hours == raw_hours
    assert place.opening_hours_status == "KNOWN"
    assert place_source.raw_opening_hours == raw_hours

    # Verify PlaceOpeningHours rows in database
    hours_rows = session.exec(
        select(PlaceOpeningHours)
        .where(PlaceOpeningHours.place_id == place.id)
        .order_by(PlaceOpeningHours.day_of_week)
    ).all()

    assert len(hours_rows) == 7

    # Monday (day 0): split schedule
    mon_row = hours_rows[0]
    assert mon_row.day_of_week == 0
    assert mon_row.status == "KNOWN"
    assert mon_row.intervals == [
        {"open": "09:00", "close": "11:00"},
        {"open": "14:00", "close": "22:00"},
    ]

    # Saturday (day 5)
    sat_row = hours_rows[5]
    assert sat_row.day_of_week == 5
    assert sat_row.status == "KNOWN"
    assert sat_row.intervals == [{"open": "10:00", "close": "18:00"}]

    # Sunday (day 6): off / closed
    sun_row = hours_rows[6]
    assert sun_row.day_of_week == 6
    assert sun_row.status == "CLOSED"
    assert sun_row.intervals == []


def test_provider_without_hours_remains_unknown(
    session: Session, sample_city: City
):
    """Requirement 11: provider result without hours remains UNKNOWN."""
    service = CanonicalPlaceService()

    nearby = OpenStreetMapNearbyPlace(
        external_place_id="node/99999",
        name="Gandhi Memorial Museum Park",
        latitude=9.9300,
        longitude=78.1300,
        source_url="https://www.openstreetmap.org/node/99999",
        tags={"name": "Gandhi Memorial Museum Park"},  # No opening_hours
    )

    place, place_source = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        nearby=nearby,
        source_name="openstreetmap",
        licence_identifier="ODbL",
    )
    session.commit()

    assert place.raw_opening_hours is None
    assert place.opening_hours_status == "UNKNOWN"
    assert place_source.raw_opening_hours is None


def test_place_read_api_serialization(session: Session, sample_city: City):
    """Requirement 9 & 16: PlaceRead exposes opening_hours dictionary matching API contract."""
    service = CanonicalPlaceService()
    raw_hours = "Mo 09:00-11:00,14:00-22:00; Tu 09:00-18:00"

    nearby = OpenStreetMapNearbyPlace(
        external_place_id="node/88888",
        name="Thirumalai Nayakkar Mahal",
        latitude=9.9150,
        longitude=78.1230,
        source_url="https://www.openstreetmap.org/node/88888",
        tags={"opening_hours": raw_hours},
    )

    place, _ = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        nearby=nearby,
        source_name="openstreetmap",
        licence_identifier="ODbL",
    )
    session.commit()

    # Validate PlaceRead from ORM Place instance
    place_read = PlaceRead.model_validate(place)

    assert place_read.opening_hours_status == "KNOWN"
    assert place_read.raw_opening_hours == raw_hours
    assert isinstance(place_read.opening_hours, dict)

    # Monday intervals
    mon_intervals = place_read.opening_hours["monday"]
    assert len(mon_intervals) == 2
    assert mon_intervals[0].open == "09:00"
    assert mon_intervals[0].close == "11:00"
    assert mon_intervals[1].open == "14:00"
    assert mon_intervals[1].close == "22:00"

    # Tuesday intervals
    tue_intervals = place_read.opening_hours["tuesday"]
    assert len(tue_intervals) == 1
    assert tue_intervals[0].open == "09:00"
    assert tue_intervals[0].close == "18:00"

    # Wednesday is empty list (closed)
    assert place_read.opening_hours["wednesday"] == []
