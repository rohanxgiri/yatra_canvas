"""OpenStreetMap/Overpass POI normalization and failure tests."""

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


def test_search_builds_bounded_query_and_normalizes_nodes_and_ways() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.method == "POST"
        assert request.url.path == "/api/interpreter"
        values = parse_qs(request.content.decode())
        query = values["data"][0]
        assert "nwr(24.506856,73.607232,24.650586,73.765282)" in query
        assert '["amenity"="place_of_worship"]' in query
        assert '["building"' not in query
        assert "out center 40;" in query
        assert "apiKey" not in query
        return httpx.Response(
            200,
            json={
                "elements": [
                    {
                        "type": "node",
                        "id": 101,
                        "lat": 24.58,
                        "lon": 73.68,
                        "tags": {"name": "Temple One", "amenity": "place_of_worship"},
                    },
                    {
                        "type": "way",
                        "id": 202,
                        "center": {"lat": 24.59, "lon": 73.69},
                        "tags": {"name:en": "Temple Two", "historic": "temple"},
                    },
                    {
                        "type": "node",
                        "id": 203,
                        "lat": 24.6,
                        "lon": 73.7,
                        "tags": {
                            "name": "Business incorrectly tagged as worship",
                            "amenity": "place_of_worship",
                            "religion": "Keeping_U_First",
                        },
                    },
                    {"type": "node", "id": 303, "lat": 1, "lon": 2, "tags": {}},
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
                latitude=24.578721,
                longitude=73.6862571,
                category=DiscoveryCategory.RELIGIOUS,
            )
        assert [item.external_place_id for item in results] == [
            "node/101",
            "way/202",
        ]
        assert results[1].source_url == "https://www.openstreetmap.org/way/202"

    asyncio.run(run())


def test_multi_category_search_uses_one_query_and_classifies_results() -> None:
    request_count = 0

    async def handler(request: httpx.Request) -> httpx.Response:
        nonlocal request_count
        request_count += 1
        query = parse_qs(request.content.decode())["data"][0]
        assert '["amenity"~"^(restaurant|fast_food|food_court)$"]' in query
        assert (
            '["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park)$"]'
            in query
        )
        assert '["historic"]' in query
        assert "out center 100;" in query
        return httpx.Response(
            200,
            json={
                "elements": [
                    {
                        "type": "node",
                        "id": 1,
                        "lat": 32.24,
                        "lon": 77.18,
                        "tags": {"name": "Cafe Restaurant", "amenity": "restaurant"},
                    },
                    {
                        "type": "way",
                        "id": 2,
                        "center": {"lat": 32.25, "lon": 77.19},
                        "tags": {"name": "River Park", "leisure": "park"},
                    },
                    {
                        "type": "node",
                        "id": 3,
                        "lat": 32.26,
                        "lon": 77.2,
                        "tags": {
                            "name": "Historic Museum",
                            "tourism": "museum",
                            "historic": "yes",
                        },
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
            results = await service.search_nearby_places_for_categories(
                latitude=32.245,
                longitude=77.187,
                categories=[
                    DiscoveryCategory.FOOD,
                    DiscoveryCategory.TOURISM,
                    DiscoveryCategory.HERITAGE,
                ],
            )

        assert [item.name for item in results[DiscoveryCategory.FOOD]] == [
            "Cafe Restaurant"
        ]
        assert [item.name for item in results[DiscoveryCategory.TOURISM]] == [
            "River Park",
            "Historic Museum",
        ]
        assert [item.name for item in results[DiscoveryCategory.HERITAGE]] == [
            "Historic Museum"
        ]

    asyncio.run(run())
    assert request_count == 1


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
