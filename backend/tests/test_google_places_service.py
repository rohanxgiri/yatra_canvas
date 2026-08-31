"""Focused tests for Google Places request construction and normalization."""

import asyncio

import httpx
import pytest

from app.services.google_places_service import (
    GooglePlaceNotFoundError,
    GooglePlacesConfigurationError,
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
                            "text": {"text": "Gandhinagar, Gujarat, India"},
                            "structuredFormat": {"mainText": {"text": "Gandhinagar"}},
                        }
                    }
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
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
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
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


def test_hotel_autocomplete_restricts_types_and_normalizes_predictions() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/places:autocomplete"
        body = request.read().decode()
        assert '"includedRegionCodes":["in"]' in body
        assert (
            '"includedPrimaryTypes":["hotel","lodging","hostel",'
            '"guest_house","resort_hotel"]'
        ) in body
        return httpx.Response(
            200,
            json={
                "suggestions": [
                    {
                        "placePrediction": {
                            "placeId": "google-hotel-imperial",
                            "text": {"text": "Hotel Imperial, Ujjain, India"},
                            "structuredFormat": {
                                "mainText": {"text": "Hotel Imperial"}
                            },
                        }
                    }
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GooglePlacesService("test-key", client=client)
            suggestions = await service.autocomplete_locations(
                "imperial", hotel_only=True
            )

        assert [item.model_dump() for item in suggestions] == [
            {
                "google_place_id": "google-hotel-imperial",
                "name": "Hotel Imperial",
                "description": "Hotel Imperial, Ujjain, India",
            }
        ]

    asyncio.run(run())


def test_location_details_extracts_start_coordinates() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/places/google-hotel-imperial"
        assert request.headers["X-Goog-FieldMask"] == "id,displayName,location"
        return httpx.Response(
            200,
            json={
                "id": "google-hotel-imperial",
                "displayName": {"text": "Hotel Imperial"},
                "location": {"latitude": 23.1801, "longitude": 75.7812},
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GooglePlacesService("test-key", client=client)
            details = await service.get_location_details("google-hotel-imperial")

        assert details.model_dump() == {
            "google_place_id": "google-hotel-imperial",
            "name": "Hotel Imperial",
            "latitude": 23.1801,
            "longitude": 75.7812,
        }

    asyncio.run(run())


def test_nearby_search_constructs_request_and_normalizes_places() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/places:searchNearby"
        assert request.headers["X-Goog-Api-Key"] == "test-key"
        assert "places.userRatingCount" in request.headers["X-Goog-FieldMask"]
        body = request.read().decode()
        assert '"includedTypes":["hindu_temple","mosque"]' in body
        assert '"radius":10000' in body
        assert '"rankPreference":"POPULARITY"' in body
        return httpx.Response(
            200,
            json={
                "places": [
                    {
                        "id": "google-mahakal",
                        "displayName": {"text": "Mahakaleshwar Temple"},
                        "location": {
                            "latitude": 23.1828,
                            "longitude": 75.7682,
                        },
                        "rating": 4.8,
                        "userRatingCount": 15000,
                        "primaryType": "hindu_temple",
                        "types": ["hindu_temple", "place_of_worship"],
                    }
                ]
            },
        )

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GooglePlacesService("test-key", client=client)
            places = await service.search_nearby_places(
                latitude=23.1765,
                longitude=75.7885,
                included_types=("hindu_temple", "mosque"),
                radius_meters=10000,
            )

        assert [item.model_dump() for item in places] == [
            {
                "google_place_id": "google-mahakal",
                "name": "Mahakaleshwar Temple",
                "latitude": 23.1828,
                "longitude": 75.7682,
                "rating": 4.8,
                "review_count": 15000,
                "primary_type": "hindu_temple",
                "types": ["hindu_temple", "place_of_worship"],
            }
        ]

    asyncio.run(run())


def test_google_timeout_is_normalized() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out", request=request)

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GooglePlacesService("test-key", client=client)
            with pytest.raises(GooglePlacesTimeoutError):
                await service.autocomplete_cities("gandhi")

    asyncio.run(run())


def test_missing_google_places_key_fails_without_a_request() -> None:
    with pytest.raises(GooglePlacesConfigurationError) as captured:
        asyncio.run(GooglePlacesService(None).autocomplete_cities("Ujjain"))

    assert str(captured.value) == ("Google Places is not configured on the backend.")


def test_invalid_place_id_is_normalized() -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(404, json={"error": {"message": "Not found"}})

    async def run() -> None:
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            service = GooglePlacesService("test-key", client=client)
            with pytest.raises(GooglePlaceNotFoundError):
                await service.get_place_details("missing-place")

    asyncio.run(run())
