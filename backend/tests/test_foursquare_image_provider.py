from uuid import uuid4

import httpx
import pytest

from app.services.foursquare_image_provider import FoursquareImageProvider
from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_image_provider import PlaceImageContext


def context(*, name: str = "Tapri Central", category=NormalizedPlaceCategory.CAFE):
    return PlaceImageContext(
        place_id=uuid4(),
        name=name,
        raw_category="cafes",
        normalized_category=category,
        latitude=26.9124,
        longitude=75.7873,
        city="Jaipur",
        state="Rajasthan",
        country="India",
        wikidata_id=None,
    )


def search_result(**overrides):
    result = {
        "fsq_place_id": "fsq-1",
        "name": "Tapri Central",
        "latitude": 26.9125,
        "longitude": 75.7874,
        "categories": [{"name": "Café"}],
        "location": {"locality": "Jaipur"},
    }
    result.update(overrides)
    return result


@pytest.mark.anyio
async def test_exact_nearby_match_selects_exterior_photo_and_filters_logo() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == "Bearer secret"
        if request.url.path.endswith("/places/search"):
            assert (
                request.url.params["query"] == "Tapri Central, Jaipur, Rajasthan, India"
            )
            assert request.url.params["ll"] == "26.9124,75.7873"
            assert request.url.params["radius"] == "500"
            return httpx.Response(200, json={"results": [search_result()]})
        return httpx.Response(
            200,
            json=[
                {"classification": "logos", "url": "https://img/logo.jpg"},
                {"classification": "food_or_drink", "url": "https://img/food.jpg"},
                {
                    "classification": "outdoor_building",
                    "url": "https://img/exterior.jpg",
                },
            ],
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        image = await FoursquareImageProvider(
            "secret", base_url="https://places-api.foursquare.com", client=client
        ).resolve(context())

    assert image is not None
    assert image.url == "https://img/exterior.jpg"
    assert image.provider_place_id == "fsq-1"


@pytest.mark.anyio
async def test_similar_nearby_name_is_accepted() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.path.endswith("/places/search"):
            return httpx.Response(
                200, json={"results": [search_result(name="Tapri Central Cafe")]}
            )
        return httpx.Response(200, json=[{"prefix": "https://img/", "suffix": ".jpg"}])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        image = await FoursquareImageProvider(
            "secret", base_url="https://places-api.foursquare.com", client=client
        ).resolve(context())
    assert image is not None
    assert image.url == "https://img/original.jpg"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "candidate",
    [
        search_result(latitude=26.9190, longitude=75.7873),
        search_result(categories=[{"name": "Hospital"}]),
        search_result(location={"locality": "Delhi"}),
    ],
)
async def test_wrong_branch_far_category_or_locality_is_rejected(candidate) -> None:
    photo_called = False

    def handler(request: httpx.Request) -> httpx.Response:
        nonlocal photo_called
        if request.url.path.endswith("/places/search"):
            return httpx.Response(200, json={"results": [candidate]})
        photo_called = True
        return httpx.Response(200, json=[])

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        image = await FoursquareImageProvider(
            "secret", base_url="https://places-api.foursquare.com", client=client
        ).resolve(context())
    assert image is None
    assert photo_called is False


@pytest.mark.anyio
async def test_missing_key_or_no_result_degrades_to_none() -> None:
    async with httpx.AsyncClient(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"results": []})
        )
    ) as client:
        assert (
            await FoursquareImageProvider(
                None, base_url="https://example", client=client
            ).resolve(context())
            is None
        )
        assert (
            await FoursquareImageProvider(
                "key", base_url="https://example", client=client
            ).resolve(context())
            is None
        )
