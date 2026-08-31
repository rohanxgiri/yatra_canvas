"""Geoapify normalization, safety, and cache tests with mocked HTTP."""

import asyncio
import logging

import httpx
import pytest

from app.services.geoapify_service import (
    GeoapifyConfigurationError,
    GeoapifyInvalidRequestError,
    GeoapifyRateLimitError,
    GeoapifyService,
    GeoapifyTimeoutError,
    GeoapifyUnavailableError,
)


def _payload() -> dict[str, object]:
    return {
        "results": [
            {
                "place_id": "geoapify-hotel-imperial",
                "name": "Hotel Imperial",
                "formatted": "Hotel Imperial, Ujjain, Madhya Pradesh, India",
                "lat": 23.1801,
                "lon": 75.7812,
                "city": "Ujjain",
                "state": "Madhya Pradesh",
                "country_code": "in",
                "result_type": "amenity",
            }
        ]
    }


def test_success_india_filter_location_bias_and_normalization() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/geocode/autocomplete"
        assert request.url.params["filter"] == "countrycode:in"
        assert request.url.params["bias"] == "proximity:75.7885,23.1765"
        assert request.url.params["type"] == "amenity"
        assert request.url.params["limit"] == "5"
        return httpx.Response(200, json=_payload())

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GeoapifyService("secret-key", client=client)
            results = await service.autocomplete(
                "Hotel Imperial",
                location_type="amenity",
                country_code="in",
                latitude=23.1765,
                longitude=75.7885,
                limit=5,
            )
        assert results[0].provider == "geoapify"
        assert results[0].provider_place_id == "geoapify-hotel-imperial"
        assert results[0].formatted_address.startswith("Hotel Imperial")

    asyncio.run(run())


def test_empty_results_and_cache_hit() -> None:
    calls = 0

    async def handler(_: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(200, json={"results": []})

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GeoapifyService(
                "secret-key", client=client, cache_ttl_seconds=60
            )
            first = await service.autocomplete(
                "nothing",
                location_type=None,
                country_code="in",
                latitude=None,
                longitude=None,
                limit=5,
            )
            second = await service.autocomplete(
                "  nothing  ",
                location_type=None,
                country_code="IN",
                latitude=None,
                longitude=None,
                limit=5,
            )
        assert first == second == []
        assert calls == 1

    asyncio.run(run())


@pytest.mark.parametrize(
    "kwargs",
    [
        {"query": "ab"},
        {"query": "valid", "country_code": "india"},
        {"query": "valid", "latitude": 23.1},
        {"query": "valid", "limit": 11},
    ],
)
def test_invalid_query_parameters(kwargs: dict[str, object]) -> None:
    values = {
        "query": "valid",
        "location_type": None,
        "country_code": "in",
        "latitude": None,
        "longitude": None,
        "limit": 5,
        **kwargs,
    }
    with pytest.raises(GeoapifyInvalidRequestError):
        asyncio.run(GeoapifyService("secret-key").autocomplete(**values))


def test_missing_key_is_safe_and_not_logged(caplog: pytest.LogCaptureFixture) -> None:
    caplog.set_level(logging.DEBUG)
    with pytest.raises(GeoapifyConfigurationError) as captured:
        asyncio.run(
            GeoapifyService(None).autocomplete(
                "Ujjain hotel",
                location_type=None,
                country_code="in",
                latitude=None,
                longitude=None,
                limit=5,
            )
        )
    assert "api" not in str(captured.value).casefold()
    assert "secret-key" not in caplog.text


@pytest.mark.parametrize(
    ("status_code", "error_type"),
    [
        (400, GeoapifyInvalidRequestError),
        (401, GeoapifyConfigurationError),
        (403, GeoapifyConfigurationError),
        (429, GeoapifyRateLimitError),
        (500, GeoapifyUnavailableError),
    ],
)
def test_http_failures_are_normalized(
    status_code: int, error_type: type[Exception]
) -> None:
    async def handler(_: httpx.Request) -> httpx.Response:
        return httpx.Response(
            status_code,
            headers={"Retry-After": "7"},
            json={"message": "raw upstream detail must not escape"},
        )

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GeoapifyService("secret-key", client=client)
            with pytest.raises(error_type) as captured:
                await service.autocomplete(
                    "Ujjain hotel",
                    location_type=None,
                    country_code="in",
                    latitude=None,
                    longitude=None,
                    limit=5,
                )
            assert "raw upstream" not in str(captured.value)
            if isinstance(captured.value, GeoapifyRateLimitError):
                assert captured.value.retry_after == "7"

    asyncio.run(run())


def test_timeout_is_normalized() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("timed out with secret-key", request=request)

    async def run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as client:
            service = GeoapifyService("secret-key", client=client)
            with pytest.raises(GeoapifyTimeoutError) as captured:
                await service.autocomplete(
                    "Ujjain hotel",
                    location_type=None,
                    country_code="in",
                    latitude=None,
                    longitude=None,
                    limit=5,
                )
            assert "secret-key" not in str(captured.value)

    asyncio.run(run())
