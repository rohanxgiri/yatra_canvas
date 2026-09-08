"""OpenStreetMap/Overpass POI normalization, quotas, radii, and failure tests."""

import asyncio
from urllib.parse import parse_qs

import httpx
import pytest

from app.schemas import DiscoveryCategory
from app.services.openstreetmap_places_service import (
    OpenStreetMapPlacesRateLimitError,
    OpenStreetMapPlacesService,
    OpenStreetMapPlacesTimeoutError,
    OpenStreetMapPlacesUnavailableError,
)
from app.services.provider_circuit_breaker import CircuitState, ProviderCircuitBreaker


def test_search_builds_bounded_query_and_normalizes_nodes_ways_and_relations() -> None:
    """Test B: Verify node, way, and relation OSM objects are all correctly normalized with coordinates."""

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "POST"
        assert request.url.path == "/api/interpreter"
        values = parse_qs(request.content.decode())
        query = values["data"][0]
        assert '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park|aquarium)$"]' in query
        assert "out center" in query
        return httpx.Response(
            200,
            json={
                "elements": [
                    {
                        "type": "node",
                        "id": 101,
                        "lat": 28.6129,
                        "lon": 77.2295,
                        "tags": {"name": "India Gate Node", "tourism": "attraction"},
                    },
                    {
                        "type": "way",
                        "id": 202,
                        "center": {"lat": 28.6562, "lon": 77.2410},
                        "tags": {"name": "Red Fort Way", "tourism": "attraction"},
                    },
                    {
                        "type": "relation",
                        "id": 303,
                        "center": {"lat": 28.5933, "lon": 77.2507},
                        "tags": {"name": "Humayun's Tomb Relation", "tourism": "attraction"},
                    },
                    {
                        "type": "node",
                        "id": 404,
                        "lat": 28.6,
                        "lon": 77.2,
                        "tags": {},
                    },
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
            )
            results = await service.search_nearby_places(
                latitude=28.6139,
                longitude=77.2090,
                category=DiscoveryCategory.TOURISM,
                limit=60,
            )
        assert len(results) == 3
        assert [item.external_place_id for item in results] == [
            "node/101",
            "way/202",
            "relation/303",
        ]
        assert results[0].latitude == pytest.approx(28.6129)
        assert results[0].longitude == pytest.approx(77.2295)
        assert results[1].latitude == pytest.approx(28.6562)
        assert results[1].longitude == pytest.approx(77.2410)
        assert results[1].source_url == "https://www.openstreetmap.org/way/202"
        assert results[2].latitude == pytest.approx(28.5933)
        assert results[2].longitude == pytest.approx(77.2507)
        assert results[2].source_url == "https://www.openstreetmap.org/relation/303"

    asyncio.run(run())


def test_independent_category_quotas_prevent_food_from_starving_attractions() -> None:
    """Test A: Ensure large food result counts cannot prevent tourism/heritage candidates from being returned."""

    queries: list[str] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        query = parse_qs(request.content.decode())["data"][0]
        queries.append(query)

        if '["amenity"~"^(restaurant|fast_food|food_court)$"]' in query:
            elements = [
                {
                    "type": "node",
                    "id": 1000 + i,
                    "lat": 28.61 + i * 0.001,
                    "lon": 77.21 + i * 0.001,
                    "tags": {"name": f"Restaurant {i}", "amenity": "restaurant"},
                }
                for i in range(50)
            ]
            return httpx.Response(200, json={"elements": elements})

        if '["tourism"~' in query:
            return httpx.Response(
                200,
                json={
                    "elements": [
                        {
                            "type": "way",
                            "id": 2001,
                            "center": {"lat": 28.6129, "lon": 77.2295},
                            "tags": {"name": "India Gate", "tourism": "attraction"},
                        },
                        {
                            "type": "relation",
                            "id": 2002,
                            "center": {"lat": 28.6562, "lon": 77.2410},
                            "tags": {"name": "Red Fort", "tourism": "attraction"},
                        },
                    ]
                },
            )

        if '["historic"]' in query:
            return httpx.Response(
                200,
                json={
                    "elements": [
                        {
                            "type": "relation",
                            "id": 3001,
                            "center": {"lat": 28.5933, "lon": 77.2507},
                            "tags": {"name": "Humayun's Tomb", "historic": "monument"},
                        },
                    ]
                },
            )

        return httpx.Response(200, json={"elements": []})

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
            )
            results = await service.search_nearby_places_for_categories(
                latitude=28.6139,
                longitude=77.2090,
                categories=[
                    DiscoveryCategory.FOOD,
                    DiscoveryCategory.TOURISM,
                    DiscoveryCategory.HERITAGE,
                ],
            )

        assert len(queries) == 3
        assert len(results[DiscoveryCategory.FOOD]) == 50
        assert len(results[DiscoveryCategory.TOURISM]) == 2
        assert len(results[DiscoveryCategory.HERITAGE]) == 1
        assert results[DiscoveryCategory.TOURISM][0].name == "India Gate"
        assert results[DiscoveryCategory.TOURISM][1].name == "Red Fort"
        assert results[DiscoveryCategory.HERITAGE][0].name == "Humayun's Tomb"

    asyncio.run(run())


def test_category_specific_radii_used_in_queries() -> None:
    """Test D: Ensure category-specific radii are applied to the bounding box calculations."""

    queries_by_category: dict[str, str] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        query = parse_qs(request.content.decode())["data"][0]
        if '["tourism"' in query:
            queries_by_category["tourism"] = query
        elif '["historic"]' in query:
            queries_by_category["heritage"] = query
        elif '["amenity"~"^(restaurant' in query:
            queries_by_category["food"] = query
        return httpx.Response(200, json={"elements": []})

    async def run() -> None:
        category_radii = {
            DiscoveryCategory.TOURISM: 15_000,
            DiscoveryCategory.HERITAGE: 15_000,
            DiscoveryCategory.FOOD: 8_000,
        }
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                category_radii=category_radii,
                client=client,
            )
            await service.search_nearby_places_for_categories(
                latitude=28.6139,
                longitude=77.2090,
                categories=[
                    DiscoveryCategory.TOURISM,
                    DiscoveryCategory.HERITAGE,
                    DiscoveryCategory.FOOD,
                ],
            )

        assert "tourism" in queries_by_category
        assert "food" in queries_by_category

        def extract_lat_span(q: str) -> float:
            import re
            m = re.search(r"(?:relation|way|node)\(([\d\.,]+)\)", q)
            assert m is not None
            bbox_str = m.group(1)
            lat_min, _, lat_max, _ = [float(x) for x in bbox_str.split(",")]
            return lat_max - lat_min

        tourism_lat_span = extract_lat_span(queries_by_category["tourism"])
        food_lat_span = extract_lat_span(queries_by_category["food"])

        assert tourism_lat_span > food_lat_span
        assert pytest.approx(tourism_lat_span / food_lat_span, rel=0.05) == (15_000 / 8_000)

    asyncio.run(run())


def test_category_limits_applied_independently() -> None:
    """Test E: Ensure each category query respects its own configured limit."""

    limits_seen: dict[str, str] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        query = parse_qs(request.content.decode())["data"][0]
        if '["tourism"' in query:
            limits_seen["tourism"] = query
        elif '["amenity"="place_of_worship"]' in query:
            limits_seen["religious"] = query
        elif '["amenity"~"^(restaurant' in query:
            limits_seen["food"] = query
        return httpx.Response(200, json={"elements": []})

    async def run() -> None:
        category_limits = {
            DiscoveryCategory.TOURISM: 60,
            DiscoveryCategory.RELIGIOUS: 40,
            DiscoveryCategory.FOOD: 50,
        }
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                category_limits=category_limits,
                client=client,
            )
            await service.search_nearby_places_for_categories(
                latitude=28.6139,
                longitude=77.2090,
                categories=[
                    DiscoveryCategory.TOURISM,
                    DiscoveryCategory.RELIGIOUS,
                    DiscoveryCategory.FOOD,
                ],
            )

        assert "out center 42;" in limits_seen["tourism"]
        assert "out center 21;" in limits_seen["tourism"]
        assert "out center 28;" in limits_seen["religious"]
        assert "out center 14;" in limits_seen["religious"]
        assert "out center 50;" in limits_seen["food"]

    asyncio.run(run())


def test_partial_provider_failure_isolation() -> None:
    """Test F: If heritage times out, food and tourism queries still succeed."""

    async def handler(request: httpx.Request) -> httpx.Response:
        query = parse_qs(request.content.decode())["data"][0]
        if '["historic"]' in query:
            raise httpx.ReadTimeout("Heritage query timed out", request=request)
        if '["tourism"' in query:
            return httpx.Response(
                200,
                json={
                    "elements": [
                        {
                            "type": "node",
                            "id": 1,
                            "lat": 28.61,
                            "lon": 77.21,
                            "tags": {"name": "National Museum", "tourism": "museum"},
                        }
                    ]
                },
            )
        return httpx.Response(
            200,
            json={
                "elements": [
                    {
                        "type": "node",
                        "id": 2,
                        "lat": 28.62,
                        "lon": 77.22,
                        "tags": {"name": "Karim's", "amenity": "restaurant"},
                    }
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
            )
            results = await service.search_nearby_places_for_categories(
                latitude=28.61,
                longitude=77.21,
                categories=[
                    DiscoveryCategory.FOOD,
                    DiscoveryCategory.TOURISM,
                    DiscoveryCategory.HERITAGE,
                ],
            )

        assert DiscoveryCategory.FOOD in results
        assert DiscoveryCategory.TOURISM in results
        assert DiscoveryCategory.HERITAGE not in results
        assert results[DiscoveryCategory.FOOD][0].name == "Karim's"
        assert results[DiscoveryCategory.TOURISM][0].name == "National Museum"

    asyncio.run(run())


def test_multi_category_requests_are_limited_to_three_in_flight() -> None:
    active_requests = 0
    peak_requests = 0
    request_count = 0

    async def handler(_: httpx.Request) -> httpx.Response:
        nonlocal active_requests, peak_requests, request_count
        request_count += 1
        active_requests += 1
        peak_requests = max(peak_requests, active_requests)
        await asyncio.sleep(0.01)
        active_requests -= 1
        return httpx.Response(200, json={"elements": []})

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
            )
            results = await service.search_nearby_places_for_categories(
                latitude=22.5726,
                longitude=88.3639,
                categories=list(DiscoveryCategory),
            )

        assert set(results) == set(DiscoveryCategory)

    asyncio.run(run())

    assert request_count == len(DiscoveryCategory)
    assert peak_requests == 3


def test_open_circuit_skips_category_waves_that_have_not_started() -> None:
    request_count = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        raise httpx.ReadTimeout("slow provider", request=request)

    async def run() -> None:
        breaker = ProviderCircuitBreaker(
            "overpass",
            failure_threshold=3,
            cooldown_seconds=60,
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
                circuit_breaker=breaker,
            )
            with pytest.raises(OpenStreetMapPlacesTimeoutError):
                await service.search_nearby_places_for_categories(
                    latitude=22.5726,
                    longitude=88.3639,
                    categories=list(DiscoveryCategory),
                )

        assert breaker.state == CircuitState.OPEN

    asyncio.run(run())

    assert request_count == 3


def test_rate_limit_timeout_and_invalid_payload_are_normalized() -> None:
    async def rate_limited(_: httpx.Request) -> httpx.Response:
        return httpx.Response(429, headers={"Retry-After": "20"})

    async def times_out(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    async def invalid(_: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"not_elements": []})

    async def call(handler: object) -> None:
        transport = httpx.MockTransport(handler)  # type: ignore[arg-type]
        async with httpx.AsyncClient(transport=transport) as client:
            service = OpenStreetMapPlacesService(
                "https://overpass.test/api/interpreter",
                client=client,
            )
            await service.search_nearby_places(
                latitude=24.57,
                longitude=73.68,
                category=DiscoveryCategory.HERITAGE,
            )

    with pytest.raises(OpenStreetMapPlacesRateLimitError) as rate_error:
        asyncio.run(call(rate_limited))
    assert rate_error.value.retry_after == "20"
    with pytest.raises(OpenStreetMapPlacesTimeoutError):
        asyncio.run(call(times_out))
    with pytest.raises(OpenStreetMapPlacesUnavailableError):
        asyncio.run(call(invalid))

