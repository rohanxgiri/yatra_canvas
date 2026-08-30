"""Focused tests for Google Places request construction and normalization."""

import asyncio

import httpx
import pytest

from app.services.google_places_service import (
    GooglePlaceNotFoundError,
    GooglePlacesService,
    GooglePlacesTimeoutError,
)


def test_autocomplete_cities_normalizes_predictions() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/places:autocomplete"
        assert request.headers["X-Goog-Api-Key"] == "test-key"
        body = request.read().decode()
        assert '"includedPrimaryTypes":["(cities)"]' in body
        assert '"includedRegionCodes":["in"]' in body
        return httpx.Response(
            200,
            json={
                "suggestions": [
                    {
                        "placePrediction": {
                            "placeId": "google-gandhinagar",
                            "text": {
                                "text": "Gandhinagar, Gujarat, India"
                            },
                            "structuredFormat": {
                                "mainText": {"text": "Gandhinagar"}
                            },
                        }
                    }
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GooglePlacesService("test-key", client=client)
            suggestions = await service.autocomplete_cities("gandhi")

        assert [item.model_dump() for item in suggestions] == [
            {
                "google_place_id": "google-gandhinagar",
                "name": "Gandhinagar",
                "description": "Gandhinagar, Gujarat, India",
            }
        ]

    asyncio.run(run())


def test_place_details_extracts_city_fields() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/places/google-gandhinagar"
        assert request.headers["X-Goog-FieldMask"] == (
            "id,displayName,addressComponents,location"
        )
        return httpx.Response(
            200,
            json={
                "id": "google-gandhinagar",
                "displayName": {"text": "Gandhinagar"},
                "addressComponents": [
                    {
                        "longText": "Gujarat",
                        "types": ["administrative_area_level_1"],
                    },
                    {"longText": "India", "types": ["country"]},
                ],
                "location": {"latitude": 23.2156, "longitude": 72.6369},
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GooglePlacesService("test-key", client=client)
            details = await service.get_place_details("google-gandhinagar")

        assert details.model_dump() == {
            "name": "Gandhinagar",
            "state": "Gujarat",
            "country": "India",
            "latitude": 23.2156,
            "longitude": 72.6369,
            "google_place_id": "google-gandhinagar",
        }

    asyncio.run(run())


def test_google_timeout_is_normalized() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out", request=request)

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GooglePlacesService("test-key", client=client)
            with pytest.raises(GooglePlacesTimeoutError):
                await service.autocomplete_cities("gandhi")

    asyncio.run(run())


def test_invalid_place_id_is_normalized() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"message": "Not found"}})

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GooglePlacesService("test-key", client=client)
            with pytest.raises(GooglePlaceNotFoundError):
                await service.get_place_details("missing-place")

    asyncio.run(run())
