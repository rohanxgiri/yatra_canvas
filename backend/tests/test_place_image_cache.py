import asyncio
import json
from datetime import datetime, timedelta, timezone
from statistics import median
from time import perf_counter
from uuid import uuid4

import httpx
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import Settings
from app.models import City, Place, PlaceImageCache
from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_image_provider import (
    PlaceImageCandidate,
    PlaceImageContext,
    PlaceImageSourceContext,
    place_image_identity_key,
    place_image_search_query,
)
from app.services.place_image_service import (
    PlaceImageResolver,
    build_place_reads,
    get_cached_place_images,
)


class FakeResolver(PlaceImageResolver):
    def __init__(self, settings, candidate, *, provider_delay_seconds: float = 0):
        super().__init__(settings)
        self.candidate = candidate
        self.calls = 0
        self.provider_delay_seconds = provider_delay_seconds
        self.provider_durations_ms: list[float] = []

    async def _resolve_context(self, context, providers):
        started = perf_counter()
        self.calls += 1
        if self.provider_delay_seconds:
            await asyncio.sleep(self.provider_delay_seconds)
        self.provider_durations_ms.append((perf_counter() - started) * 1000)
        return self.candidate, False


class StubProvider:
    def __init__(self, *, candidate=None, error=None):
        self.candidate = candidate
        self.error = error
        self.calls = 0

    async def resolve(self, context):
        self.calls += 1
        if self.error is not None:
            raise self.error
        return self.candidate


def percentile(values: list[float], percentile_value: float) -> float:
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(len(ordered) * percentile_value))
    return ordered[index]


def settings() -> Settings:
    return Settings(
        DATABASE_URL="postgresql://user:pass@localhost/db",
        PLACE_IMAGE_TIMEOUT_SECONDS=1,
        PLACE_IMAGE_CONCURRENCY=4,
    )


def seed(session: Session, count: int = 1):
    city = City(
        name="Jaipur",
        state="Rajasthan",
        country="India",
        latitude=26.91,
        longitude=75.79,
    )
    session.add(city)
    places = [
        Place(
            city_id=city.id,
            name=f"Place {i}",
            category="heritage",
            latitude=26.91 + i / 10000,
            longitude=75.79,
        )
        for i in range(count)
    ]
    session.add_all(places)
    session.commit()
    return places


def image_candidate(provider: str = "wikimedia") -> PlaceImageCandidate:
    return PlaceImageCandidate(
        url="https://img/place.jpg",
        thumbnail_url=None,
        provider=provider,
        provider_place_id="File:Place.jpg",
        source_url="https://commons.example",
        attribution="Credit",
        author="Author",
        license="CC BY",
        license_url="https://license.example",
    )


def image_context(
    *,
    name: str,
    latitude: float,
    longitude: float,
    sources: tuple[PlaceImageSourceContext, ...] = (),
) -> PlaceImageContext:
    return PlaceImageContext(
        place_id=uuid4(),
        name=name,
        raw_category="tourism",
        normalized_category=NormalizedPlaceCategory.LANDMARK,
        latitude=latitude,
        longitude=longitude,
        city="Shillong",
        state="Meghalaya",
        country="India",
        wikidata_id=None,
        sources=sources,
    )


def test_place_image_identity_is_provider_specific_with_coordinate_fallback() -> None:
    source_a = image_context(
        name="Don Bosco Square",
        latitude=25.578,
        longitude=91.893,
        sources=(
            PlaceImageSourceContext(
                source="openstreetmap",
                external_place_id="node/1001",
            ),
        ),
    )
    source_b = image_context(
        name="Soldier Statue Point",
        latitude=25.579,
        longitude=91.894,
        sources=(
            PlaceImageSourceContext(
                source="openstreetmap",
                external_place_id="node/1002",
            ),
        ),
    )
    fallback_a = image_context(
        name="Unnamed View Point",
        latitude=25.570001,
        longitude=91.880001,
    )
    fallback_b = image_context(
        name="Unnamed View Point",
        latitude=25.571001,
        longitude=91.881001,
    )

    assert place_image_identity_key(source_a) == "provider:openstreetmap:node/1001"
    assert place_image_identity_key(source_a) != place_image_identity_key(source_b)
    assert place_image_identity_key(fallback_a) != place_image_identity_key(fallback_b)
    assert (
        place_image_search_query(source_a)
        == "Don Bosco Square, Shillong, Meghalaya, India"
    )


@pytest.mark.anyio
async def test_invalid_image_http_response_is_rejected() -> None:
    context = image_context(
        name="Don Bosco Square",
        latitude=25.578,
        longitude=91.893,
    )
    candidate = image_candidate()

    def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-type": "text/html"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        valid = await PlaceImageResolver._candidate_url_is_image(
            client,
            context,
            candidate,
        )

    assert valid is False


@pytest.mark.anyio
async def test_display_thumbnail_is_the_url_validated_for_flutter() -> None:
    context = image_context(
        name="Don Bosco Square",
        latitude=25.578,
        longitude=91.893,
    )
    candidate = PlaceImageCandidate(
        url="https://img.test/full.jpg",
        thumbnail_url="https://img.test/broken-thumbnail.jpg",
        provider="wikimedia",
        provider_place_id="File:Don Bosco Square.jpg",
        source_url="https://commons.example",
        attribution="Credit",
        author="Author",
        license="CC BY",
        license_url="https://license.example",
    )

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/broken-thumbnail.jpg"
        return httpx.Response(200, headers={"content-type": "text/html"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        valid = await PlaceImageResolver._candidate_url_is_image(
            client,
            context,
            candidate,
        )

    assert valid is False


@pytest.mark.anyio
async def test_resolved_cache_persists_across_fresh_database_sessions() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        resolver = FakeResolver(settings(), image_candidate())
        await resolver.resolve_many(session, [place_id])

    with Session(engine) as fresh_session:
        row = fresh_session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id == place_id)
        ).one()
        assert row.status == "resolved"
        assert row.provider == "wikimedia"
        assert row.url == "https://img/place.jpg"
        assert row.fetched_at is not None
        assert row.expires_at > row.fetched_at


@pytest.mark.anyio
async def test_negative_cache_persists_across_fresh_database_sessions() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        resolver = FakeResolver(settings(), None)
        await resolver.resolve_many(session, [place_id])

    with Session(engine) as fresh_session:
        row = fresh_session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id == place_id)
        ).one()
        assert row.status == "not_found"
        assert row.provider is None
        assert row.url is None
        assert row.fetched_at is not None
        assert row.expires_at > row.fetched_at


@pytest.mark.anyio
async def test_valid_negative_cache_prevents_provider_lookup() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        initial_resolver = FakeResolver(settings(), None)
        await initial_resolver.resolve_many(session, [place_id])

    with Session(engine) as fresh_session:
        resolver = FakeResolver(settings(), image_candidate())
        result = await resolver.resolve_many(fresh_session, [place_id])
        assert resolver.calls == 0
        assert result[place_id].status == "not_found"


@pytest.mark.anyio
async def test_expired_negative_cache_allows_provider_lookup() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        initial_resolver = FakeResolver(settings(), None)
        await initial_resolver.resolve_many(session, [place_id])

    with Session(engine) as session:
        row = session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id == place_id)
        ).one()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        session.add(row)
        session.commit()

    with Session(engine) as fresh_session:
        resolver = FakeResolver(settings(), image_candidate())
        result = await resolver.resolve_many(fresh_session, [place_id])
        assert resolver.calls == 1
        assert result[place_id].status == "resolved"


@pytest.mark.anyio
async def test_valid_resolved_cache_prevents_provider_lookup() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        initial_resolver = FakeResolver(settings(), image_candidate())
        await initial_resolver.resolve_many(session, [place_id])

    with Session(engine) as fresh_session:
        resolver = FakeResolver(settings(), None)
        result = await resolver.resolve_many(fresh_session, [place_id])
        assert resolver.calls == 0
        assert result[place_id].status == "resolved"


@pytest.mark.anyio
async def test_expired_resolved_cache_is_returned_stale_and_refreshable() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        place_id = seed(session)[0].id
        initial_resolver = FakeResolver(settings(), image_candidate())
        await initial_resolver.resolve_many(session, [place_id])

    with Session(engine) as session:
        row = session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id == place_id)
        ).one()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        session.add(row)
        session.commit()

    with Session(engine) as fresh_session:
        cached, refresh_ids = get_cached_place_images(fresh_session, [place_id])
        assert cached[place_id].status == "resolved"
        assert refresh_ids == {place_id}

        resolver = FakeResolver(settings(), image_candidate("geoapify"))
        result = await resolver.resolve_many(fresh_session, [place_id])
        assert resolver.calls == 1
        assert result[place_id].provider == "geoapify"


@pytest.mark.anyio
async def test_positive_and_negative_cache_entries_are_reused() -> None:
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    candidate = PlaceImageCandidate(
        url="https://img/place.jpg",
        thumbnail_url=None,
        provider="wikimedia",
        provider_place_id="File:Place.jpg",
        source_url="https://commons.example",
        attribution="Credit",
        author="Author",
        license="CC BY",
        license_url="https://license.example",
    )
    with Session(engine) as session:
        places = seed(session, 2)
        positive = FakeResolver(settings(), candidate)
        await positive.resolve_many(session, [places[0].id])
        await positive.resolve_many(session, [places[0].id])
        assert positive.calls == 1

        negative = FakeResolver(settings(), None)
        await negative.resolve_many(session, [places[1].id])
        await negative.resolve_many(session, [places[1].id])
        assert negative.calls == 1
        rows = session.exec(select(PlaceImageCache)).all()
        assert {row.status for row in rows} == {"resolved", "not_found"}


@pytest.mark.anyio
async def test_same_city_category_pois_keep_distinct_cache_rows() -> None:
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        places = seed(session, 2)
        first = image_candidate()
        second = PlaceImageCandidate(
            url="https://img/second-place.jpg",
            thumbnail_url=None,
            provider="wikimedia",
            provider_place_id="File:Second Place.jpg",
            source_url="https://commons.example/second",
            attribution="Credit",
            author="Author",
            license="CC BY",
            license_url="https://license.example",
        )
        await FakeResolver(settings(), first).resolve_many(session, [places[0].id])
        await FakeResolver(settings(), second).resolve_many(session, [places[1].id])

        rows = session.exec(select(PlaceImageCache)).all()
        place_ids = {place.id for place in places}

    assert len(rows) == 2
    assert {row.place_id for row in rows} == place_ids
    assert {row.url for row in rows} == {
        "https://img/place.jpg",
        "https://img/second-place.jpg",
    }


@pytest.mark.anyio
async def test_timeout_retries_then_falls_through_to_the_next_provider() -> None:
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    resolver = PlaceImageResolver(settings())
    with Session(engine) as session:
        place = seed(session)[0]
        context = resolver._load_contexts(session, {place.id})[0]
        timeout_provider = StubProvider(error=httpx.ReadTimeout("timed out"))
        wikimedia_provider = StubProvider(candidate=image_candidate())
        candidate, had_error = await resolver._resolve_context(
            context,
            {
                "geoapify": timeout_provider,
                "wikimedia": wikimedia_provider,
                "foursquare": StubProvider(),
            },
        )

    assert candidate is not None
    assert candidate.provider == "wikimedia"
    assert had_error is True
    assert timeout_provider.calls == 2
    assert wikimedia_provider.calls == 1


@pytest.mark.anyio
async def test_malformed_responses_from_all_providers_degrade_to_no_image() -> None:
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    resolver = PlaceImageResolver(settings())
    with Session(engine) as session:
        place = seed(session)[0]
        context = resolver._load_contexts(session, {place.id})[0]
        providers = {
            name: StubProvider(error=ValueError("malformed response"))
            for name in ("geoapify", "wikimedia", "foursquare")
        }
        candidate, had_error = await resolver._resolve_context(context, providers)

    assert candidate is None
    assert had_error is True
    assert all(provider.calls == 1 for provider in providers.values())


def test_provider_priority_is_category_aware() -> None:
    resolver = PlaceImageResolver(settings())
    assert resolver._provider_order(NormalizedPlaceCategory.CAFE) == (
        "foursquare",
        "geoapify",
        "wikimedia",
    )
    assert resolver._provider_order(NormalizedPlaceCategory.FOREST) == (
        "geoapify",
        "wikimedia",
        "foursquare",
    )


@pytest.mark.anyio
async def test_expired_entry_refreshes_and_jaipur_20_warm_cache_is_faster() -> None:
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    candidate = PlaceImageCandidate(
        url="https://img/place.jpg",
        thumbnail_url=None,
        provider="geoapify",
        provider_place_id=None,
        source_url=None,
        attribution=None,
        author=None,
        license=None,
        license_url=None,
    )
    with Session(engine) as session:
        places = seed(session, 20)
        foreground_durations_ms: list[float] = []
        for _ in range(30):
            foreground_start = perf_counter()
            reads, refresh_ids = build_place_reads(session, places)
            foreground_durations_ms.append((perf_counter() - foreground_start) * 1000)
            assert len(reads) == 20
            assert len(refresh_ids) == 20

        resolver = FakeResolver(settings(), candidate, provider_delay_seconds=0.01)
        cold_start = perf_counter()
        await resolver.resolve_many(session, [place.id for place in places])
        cold_ms = (perf_counter() - cold_start) * 1000
        assert resolver.calls == 20

        warm_start = perf_counter()
        warm_result = await resolver.resolve_many(
            session, [place.id for place in places]
        )
        warm_ms = (perf_counter() - warm_start) * 1000
        assert resolver.calls == 20
        assert warm_ms < cold_ms
        assert len(warm_result) == 20

        benchmark = {
            "city": "Jaipur",
            "poi_count": 20,
            "foreground_image_layer_p50_ms": round(median(foreground_durations_ms), 3),
            "foreground_image_layer_p95_ms": round(
                percentile(foreground_durations_ms, 0.95), 3
            ),
            "cold_image_resolution_ms": round(cold_ms, 3),
            "warm_cache_resolution_ms": round(warm_ms, 3),
            "provider_latency_p50_ms": round(median(resolver.provider_durations_ms), 3),
            "provider_latency_p95_ms": round(
                percentile(resolver.provider_durations_ms, 0.95), 3
            ),
            "cold_provider_calls": resolver.calls,
            "warm_additional_provider_calls": 0,
            "warm_cache_hit_rate_percent": 100,
        }
        print(f"PLACE_IMAGE_BENCHMARK={json.dumps(benchmark, sort_keys=True)}")

        # The foreground API path only performs the batched cache lookup. Provider
        # I/O is background work and the warm pass must perform no provider calls.
        assert benchmark["foreground_image_layer_p95_ms"] < 50
        assert benchmark["warm_additional_provider_calls"] == 0

        row = session.exec(select(PlaceImageCache)).first()
        row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        session.commit()
        await resolver.resolve_many(session, [row.place_id])
        assert resolver.calls == 21
