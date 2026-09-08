"""Tests for canonical multi-source Place identity resolution and provenance."""

import asyncio
from collections.abc import Generator
from datetime import datetime, timezone

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import Settings
from app.models import City, Place, PlaceOpeningHours, PlaceSource, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.canonical_place_service import (
    CanonicalNearbyCandidate,
    CanonicalPlaceService,
    extract_wikidata_id,
    is_category_compatible,
    is_conservative_name_match,
)
from app.services.openstreetmap_discovery_service import OpenStreetMapDiscoveryService
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
        name="Manali",
        state="Himachal Pradesh",
        country="India",
        latitude=32.2432,
        longitude=77.1892,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


def test_wikidata_id_extraction():
    # From tags
    assert extract_wikidata_id("node/123", {"wikidata": "Q4285885"}) == "Q4285885"
    assert extract_wikidata_id("node/123", {"wikidata_id": "q4285885"}) == "Q4285885"
    # From external_place_id directly
    assert extract_wikidata_id("Q4285885") == "Q4285885"
    assert extract_wikidata_id("q12345") == "Q12345"
    # Invalid or non-QID
    assert extract_wikidata_id("node/12345") is None
    assert extract_wikidata_id("way/67890", {"name": "Test"}) is None


def test_category_compatibility():
    assert is_category_compatible("tourism", "tourism") is True
    assert is_category_compatible("heritage", "tourism") is True
    assert is_category_compatible("heritage", "religious") is True
    assert is_category_compatible("food", "cafes") is True
    assert is_category_compatible("food", "markets") is True

    assert is_category_compatible("religious", "food") is False
    assert is_category_compatible("tourism", "cafes") is False
    assert is_category_compatible("heritage", "food") is False


def test_conservative_name_match():
    # Identical
    assert is_conservative_name_match("Hadimba Temple", "Hadimba Temple") is True
    # Minor noise token differences
    assert is_conservative_name_match("The Hadimba Temple", "Hadimba Temple") is True
    assert is_conservative_name_match("Hadimba Devi Temple", "Hadimba Temple") is True
    # Disqualifying specifier prevents merge
    assert (
        is_conservative_name_match("Hadimba Temple North", "Hadimba Temple South")
        is False
    )
    assert is_conservative_name_match("Terminal 1", "Terminal 2") is False
    assert is_conservative_name_match("Gate 1", "Gate 2") is False
    # Different places altogether
    assert is_conservative_name_match("Taj Mahal Palace", "Taj Mahal Cafe") is False
    assert is_conservative_name_match("Manu Temple", "Vashisht Temple") is False


def test_cold_city_batch_preserves_identity_provenance_tags_and_hours(
    session: Session,
    sample_city: City,
) -> None:
    now = datetime.now(timezone.utc)
    service = CanonicalPlaceService()
    audiala = OpenStreetMapNearbyPlace(
        external_place_id="Q12345",
        source_url="https://example.test/audiala/Q12345",
        name="River Temple",
        latitude=sample_city.latitude,
        longitude=sample_city.longitude,
        tags={"wikidata": "Q12345", "opening_hours": "Mo-Su 09:00-17:00"},
    )
    geoapify = OpenStreetMapNearbyPlace(
        external_place_id="geo-place-1",
        source_url="https://example.test/geo-place-1",
        name="River Temple",
        latitude=sample_city.latitude,
        longitude=sample_city.longitude,
        tags={"wikidata": "Q12345"},
    )

    service.create_cold_city_batch(
        session,
        sample_city,
        [
            CanonicalNearbyCandidate(
                category=DiscoveryCategory.RELIGIOUS,
                nearby=audiala,
                source_name="audiala",
                licence_identifier="CC BY 4.0",
            ),
            CanonicalNearbyCandidate(
                category=DiscoveryCategory.HERITAGE,
                nearby=geoapify,
                source_name="geoapify",
                licence_identifier="Geoapify-Proprietary",
            ),
        ],
        fetched_at=now,
    )
    session.commit()

    places = session.exec(select(Place)).all()
    assert len(places) == 1
    assert places[0].wikidata_id == "Q12345"
    assert places[0].raw_opening_hours == "Mo-Su 09:00-17:00"
    assert places[0].is_heritage is True
    assert len(session.exec(select(PlaceSource)).all()) == 2
    assert {tag.tag for tag in session.exec(select(PlaceTag)).all()} == {
        "religious",
        "heritage",
    }
    assert len(session.exec(select(PlaceOpeningHours)).all()) == 7


def test_repeated_same_source_ingestion_is_idempotent_osm(
    session: Session, sample_city: City
):
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    osm_candidate = OpenStreetMapNearbyPlace(
        external_place_id="node/1001",
        source_url="https://www.openstreetmap.org/node/1001",
        name="Hidimba Devi Temple",
        latitude=32.2482,
        longitude=77.1805,
        tags={"amenity": "place_of_worship", "religion": "hindu"},
    )

    # First ingestion
    p1, s1 = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.RELIGIOUS,
        nearby=osm_candidate,
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    # Second ingestion with updated metadata
    p2, s2 = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.RELIGIOUS,
        nearby=osm_candidate,
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id == p2.id
    assert s1.id == s2.id
    assert len(session.exec(select(Place)).all()) == 1
    assert len(session.exec(select(PlaceSource)).all()) == 1


def test_repeated_same_source_ingestion_is_idempotent_audiala(
    session: Session, sample_city: City
):
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    audiala_candidate = OpenStreetMapNearbyPlace(
        external_place_id="Q4285885",
        source_url="https://en.wikipedia.org/wiki/Hidimba_Devi_Temple",
        name="Hidimba Devi Temple",
        latitude=32.2482,
        longitude=77.1805,
        tags={"audiala:category": "sight", "wikidata": "Q4285885"},
    )

    # First ingestion
    p1, s1 = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        nearby=audiala_candidate,
        source_name="audiala",
        licence_identifier="CC BY 4.0",
        fetched_at=now,
    )
    session.commit()

    # Second ingestion
    p2, s2 = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        nearby=audiala_candidate,
        source_name="audiala",
        licence_identifier="CC BY 4.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id == p2.id
    assert s1.id == s2.id
    assert len(session.exec(select(Place)).all()) == 1
    assert len(session.exec(select(PlaceSource)).all()) == 1


def test_shared_wikidata_id_across_osm_and_audiala_resolves_to_one_place(
    session: Session, sample_city: City
):
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    # 1. OSM candidate with wikidata tag
    osm_place = OpenStreetMapNearbyPlace(
        external_place_id="node/1001",
        source_url="https://www.openstreetmap.org/node/1001",
        name="Hidimba Devi Temple",
        latitude=32.248200,
        longitude=77.180500,
        tags={"wikidata": "Q4285885", "amenity": "place_of_worship"},
    )

    # 2. Audiala candidate with wikidata external_place_id
    audiala_place = OpenStreetMapNearbyPlace(
        external_place_id="Q4285885",
        source_url="https://en.wikipedia.org/wiki/Hidimba_Devi_Temple",
        name="Hidimba Temple",
        latitude=32.248205,
        longitude=77.180495,
        tags={"wikidata": "Q4285885", "audiala:category": "sight"},
    )

    place_osm, source_osm = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.RELIGIOUS,
        nearby=osm_place,
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    place_aud, source_aud = service.resolve_or_create_nearby_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        nearby=audiala_place,
        source_name="audiala",
        licence_identifier="CC BY 4.0",
        fetched_at=now,
    )
    session.commit()

    # Must resolve to the exact same canonical Place!
    assert place_osm.id == place_aud.id
    assert place_osm.wikidata_id == "Q4285885"
    assert len(session.exec(select(Place)).all()) == 1

    # Exactly 2 PlaceSources, one for each provider
    sources = session.exec(select(PlaceSource)).all()
    assert len(sources) == 2
    sources_by_provider = {s.source: s for s in sources}
    assert "openstreetmap" in sources_by_provider
    assert "audiala" in sources_by_provider

    # Provenance and licensing intact
    assert sources_by_provider["openstreetmap"].licence_identifier == "ODbL-1.0"
    assert sources_by_provider["openstreetmap"].external_place_id == "node/1001"
    assert sources_by_provider["audiala"].licence_identifier == "CC BY 4.0"
    assert sources_by_provider["audiala"].external_place_id == "Q4285885"


def test_nearby_venues_with_different_names_remain_separate(
    session: Session, sample_city: City
):
    """Two different shops/venues 30m apart must NOT accidentally merge."""
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    # Place A
    p1, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.FOOD,
        name="Chopsticks Restaurant",
        latitude=32.24300,
        longitude=77.18900,
        external_place_id="node/2001",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    # Place B 25 meters away
    p2, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.FOOD,
        name="Johnson's Cafe",
        latitude=32.24320,
        longitude=77.18910,
        external_place_id="node/2002",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id != p2.id
    assert len(session.exec(select(Place)).all()) == 2


def test_same_name_geographically_distant_pois_remain_separate(
    session: Session, sample_city: City
):
    """Two branches with identical name kilometers apart must remain separate."""
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    # Branch 1
    p1, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.CAFES,
        name="Cafe 1947",
        latitude=32.2430,
        longitude=77.1890,
        external_place_id="node/3001",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    # Branch 2 located 5km away
    p2, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.CAFES,
        name="Cafe 1947",
        latitude=32.2850,
        longitude=77.2200,
        external_place_id="node/3002",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id != p2.id
    assert len(session.exec(select(Place)).all()) == 2


def test_conservative_fallback_merges_matching_names_within_threshold(
    session: Session, sample_city: City
):
    """Even without Wikidata ID, identical/similar venue within 100m merges under fallback."""
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    p1, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        name="Vashisht Hot Springs",
        latitude=32.26120,
        longitude=77.18830,
        external_place_id="provider_a/101",
        source_name="provider_a",
        licence_identifier="Custom-1.0",
        fetched_at=now,
    )
    session.commit()

    # Provider B candidate 15m away with matching name and compatible category (heritage ~ tourism)
    p2, s2 = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.HERITAGE,
        name="The Vashisht Hot Springs",
        latitude=32.26130,
        longitude=77.18835,
        external_place_id="provider_b/202",
        source_name="provider_b",
        licence_identifier="Custom-2.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id == p2.id
    assert len(session.exec(select(Place)).all()) == 1
    assert len(session.exec(select(PlaceSource)).all()) == 2


def test_incompatible_categories_do_not_merge(session: Session, sample_city: City):
    """Venues within 30m with identical names but incompatible categories do NOT merge."""
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    # Food venue
    p1, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.FOOD,
        name="Shiva Temple Complex Canteen",
        latitude=32.25000,
        longitude=77.18000,
        external_place_id="osm/1",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    # Religious venue at the same location
    p2, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.RELIGIOUS,
        name="Shiva Temple Complex Canteen",
        latitude=32.25005,
        longitude=77.18005,
        external_place_id="osm/2",
        source_name="openstreetmap",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id != p2.id
    assert len(session.exec(select(Place)).all()) == 2


def test_disqualifying_specifiers_prevent_merge(session: Session, sample_city: City):
    """Numbered gates or terminals within 50m must NOT merge."""
    service = CanonicalPlaceService()
    now = datetime.now(timezone.utc)

    p1, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        name="Fort Complex Gate 1",
        latitude=32.24000,
        longitude=77.18000,
        external_place_id="src1/1",
        source_name="source_1",
        licence_identifier="ODbL-1.0",
        fetched_at=now,
    )
    p2, _ = service.resolve_or_create_place(
        session=session,
        city=sample_city,
        category=DiscoveryCategory.TOURISM,
        name="Fort Complex Gate 2",
        latitude=32.24020,
        longitude=77.18010,
        external_place_id="src2/2",
        source_name="source_2",
        licence_identifier="CC BY 4.0",
        fetched_at=now,
    )
    session.commit()

    assert p1.id != p2.id
    assert len(session.exec(select(Place)).all()) == 2


def test_discovery_service_integration_osm_and_audiala_merge(
    session: Session, sample_city: City
):
    """Full integration test with OpenStreetMapDiscoveryService.

    Both OSM and Audiala return the same venue (Hidimba Devi Temple) with Wikidata Q4285885.
    Expected: Exactly 1 Place row, 2 PlaceSources, both category tags attached.
    """
    settings = Settings(
        DATABASE_URL="postgresql://example.invalid/yatra",
    )

    class MockOsmProvider:
        async def search_nearby_places_for_categories(self, **_: object):
            return {
                DiscoveryCategory.RELIGIOUS: [
                    OpenStreetMapNearbyPlace(
                        external_place_id="node/9999",
                        source_url="https://www.openstreetmap.org/node/9999",
                        name="Hidimba Devi Temple",
                        latitude=32.2482,
                        longitude=77.1805,
                        tags={"wikidata": "Q4285885", "amenity": "place_of_worship"},
                    )
                ]
            }

    class MockAudialaProvider:
        async def search_nearby_places_for_categories(self, **_: object):
            return {
                DiscoveryCategory.HERITAGE: [
                    OpenStreetMapNearbyPlace(
                        external_place_id="Q4285885",
                        source_url="https://en.wikipedia.org/wiki/Hidimba_Devi_Temple",
                        name="Hidimba Temple",
                        latitude=32.2482,
                        longitude=77.1805,
                        tags={"wikidata": "Q4285885", "audiala:category": "sight"},
                    )
                ]
            }

    canonical_service = CanonicalPlaceService()
    discovery_service = OpenStreetMapDiscoveryService(
        settings=settings,
        provider=MockOsmProvider(),  # type: ignore[arg-type]
        audiala_provider=MockAudialaProvider(),  # type: ignore[arg-type]
        canonical_service=canonical_service,
    )

    results = asyncio.run(
        discovery_service.discover_many(
            session=session,
            city=sample_city,
            categories=[DiscoveryCategory.RELIGIOUS, DiscoveryCategory.HERITAGE],
        )
    )

    places = session.exec(select(Place)).all()
    assert len(places) == 1
    canonical_place = places[0]
    assert canonical_place.wikidata_id == "Q4285885"

    sources = session.exec(select(PlaceSource)).all()
    assert len(sources) == 2
    sources_by_name = {s.source: s for s in sources}
    assert "openstreetmap" in sources_by_name
    assert "audiala" in sources_by_name
    assert sources_by_name["openstreetmap"].licence_identifier == "ODbL-1.0"
    assert sources_by_name["audiala"].licence_identifier == "CC BY 4.0"

    # Both tags should be linked to the single canonical place
    tags = session.exec(
        select(PlaceTag).where(PlaceTag.place_id == canonical_place.id)
    ).all()
    tag_names = {t.tag for t in tags}
    assert DiscoveryCategory.RELIGIOUS.value in tag_names
    assert DiscoveryCategory.HERITAGE.value in tag_names
