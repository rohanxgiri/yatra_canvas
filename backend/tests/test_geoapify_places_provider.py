"""Unit tests for GeoapifyPlacesProvider with mocked HTTP."""

import json
import pytest
import httpx
from app.schemas import DiscoveryCategory
from app.services.geoapify_places_provider import (
    GeoapifyPlacesProvider,
    GeoapifyPlacesTimeoutError,
    GeoapifyPlacesUnavailableError,
)


@pytest.mark.anyio
async def test_geoapify_places_unconfigured():
    provider = GeoapifyPlacesProvider(None)
    assert not provider.is_configured
    results = await provider.search_nearby_places(
        latitude=9.9312,
        longitude=76.2673,
        category=DiscoveryCategory.TOURISM,
    )
    assert results == []


@pytest.mark.anyio
async def test_geoapify_places_parses_features():
    fake_payload = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "place_id": "geo_kochi_beach_1",
                    "name": "Fort Kochi Beach",
                    "lat": 9.9658,
                    "lon": 76.2421,
                    "categories": ["tourism", "tourism.attraction"],
                    "website": "https://keralatourism.org",
                },
            },
            {
                "type": "Feature",
                "properties": {
                    "place_id": "geo_chinese_nets_2",
                    "name": "Chinese Fishing Nets",
                    "lat": 9.9675,
                    "lon": 76.2435,
                    "categories": ["tourism", "heritage"],
                    "wiki_and_media": {"wikidata": "Q123456"},
                },
            },
        ],
    }

    def handler(request: httpx.Request) -> httpx.Response:
        assert "v2/places" in str(request.url)
        assert "apiKey=fake_key" in str(request.url)
        return httpx.Response(200, json=fake_payload)

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = GeoapifyPlacesProvider(
            api_key="fake_key",
            client=client,
        )
        places = await provider.search_nearby_places(
            latitude=9.9312,
            longitude=76.2673,
            category=DiscoveryCategory.TOURISM,
        )

    assert len(places) == 2
    assert places[0].name == "Fort Kochi Beach"
    assert places[0].external_place_id == "geoapify-geo_kochi_beach_1"
    assert places[0].tags["website"] == "https://keralatourism.org"

    assert places[1].name == "Chinese Fishing Nets"
    assert places[1].tags["wikidata"] == "Q123456"


@pytest.mark.anyio
async def test_geoapify_places_handles_timeout():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.TimeoutException("mock timeout")

    transport = httpx.MockTransport(handler)
    async with httpx.AsyncClient(transport=transport) as client:
        provider = GeoapifyPlacesProvider(
            api_key="fake_key",
            client=client,
        )
        with pytest.raises(GeoapifyPlacesTimeoutError):
            await provider.search_nearby_places(
                latitude=9.9312,
                longitude=76.2673,
                category=DiscoveryCategory.FOOD,
            )
