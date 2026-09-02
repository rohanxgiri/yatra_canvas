"""Cache fallback behavior for OpenStreetMap place discovery."""

import asyncio
from collections.abc import Generator

import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import Settings
from app.models import City, Place, PlaceTag
from app.schemas import DiscoveryCategory
from app.services.openstreetmap_discovery_service import (
    OpenStreetMapDiscoveryService,
)
from app.services.openstreetmap_places_service import (
    OpenStreetMapNearbyPlace,
    OpenStreetMapPlacesUnavailableError,
)


class UnavailableProvider:
    async def search_nearby_places(self, **_: object) -> list[object]:
        raise OpenStreetMapPlacesUnavailableError(
            "OpenStreetMap discovery is temporarily unavailable."
        )


class BatchProvider:
    def __init__(self) -> None:
        self.calls = 0

    async def search_nearby_places_for_categories(
        self,
        *,
        categories: list[DiscoveryCategory],
        **_: object,
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        self.calls += 1
        assert categories == [DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE]
        shared = OpenStreetMapNearbyPlace(
            external_place_id="node/42",
            source_url="https://www.openstreetmap.org/node/42",
            name="Historic Restaurant",
            latitude=32.24,
            longitude=77.18,
            tags={"amenity": "restaurant", "historic": "yes"},
        )
        return {
            DiscoveryCategory.FOOD: [shared],
            DiscoveryCategory.HERITAGE: [shared],
        }


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


def _service() -> OpenStreetMapDiscoveryService:
    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    return OpenStreetMapDiscoveryService(settings, UnavailableProvider())  # type: ignore[arg-type]


def _city(session: Session) -> City:
    city = City(
        name="Manali",
        state="Himachal Pradesh",
        country="India",
        latitude=32.2454608,
        longitude=77.1872926,
    )
    session.add(city)
    session.commit()
    session.refresh(city)
    return city


def test_stored_places_are_served_when_overpass_refresh_fails(
    session: Session,
) -> None:
    city = _city(session)
    place = Place(
        city_id=city.id,
        name="Hadimba Devi Temple",
        category="religious",
        latitude=32.2483855,
        longitude=77.1809861,
        review_count=0,
    )
    session.add(place)
    session.flush()
    session.add(PlaceTag(place_id=place.id, tag="religious"))
    session.commit()

    result = asyncio.run(
        _service().discover(
            session=session,
            city=city,
            category=DiscoveryCategory.RELIGIOUS,
        )
    )

    assert [item.name for item in result] == ["Hadimba Devi Temple"]


def test_provider_failure_is_preserved_without_stored_places(
    session: Session,
) -> None:
    city = _city(session)

    with pytest.raises(OpenStreetMapPlacesUnavailableError):
        asyncio.run(
            _service().discover(
                session=session,
                city=city,
                category=DiscoveryCategory.RELIGIOUS,
            )
        )


def test_uncached_categories_are_fetched_once_and_persisted_with_all_tags(
    session: Session,
) -> None:
    city = _city(session)
    provider = BatchProvider()
    settings = Settings(DATABASE_URL="postgresql://example.invalid/yatra")
    service = OpenStreetMapDiscoveryService(settings, provider)  # type: ignore[arg-type]

    result = asyncio.run(
        service.discover_many(
            session=session,
            city=city,
            categories=[DiscoveryCategory.FOOD, DiscoveryCategory.HERITAGE],
        )
    )

    assert provider.calls == 1
    assert [place.name for place in result[DiscoveryCategory.FOOD]] == [
        "Historic Restaurant"
    ]
    assert [place.name for place in result[DiscoveryCategory.HERITAGE]] == [
        "Historic Restaurant"
    ]
    place = result[DiscoveryCategory.FOOD][0]
    tags = session.exec(select(PlaceTag.tag).where(PlaceTag.place_id == place.id)).all()
    assert set(tags) == {"food", "heritage"}
