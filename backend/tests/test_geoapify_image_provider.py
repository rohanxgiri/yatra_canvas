from uuid import uuid4

import httpx
import pytest

from app.services.geoapify_image_provider import GeoapifyImageProvider
from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_image_provider import PlaceImageContext, PlaceImageSourceContext


def context(identifiers=None):
    return PlaceImageContext(
        place_id=uuid4(),
        name="Hawa Mahal",
        raw_category="heritage",
        normalized_category=NormalizedPlaceCategory.LANDMARK,
        latitude=26.9239,
        longitude=75.8267,
        city="Jaipur",
        state="Rajasthan",
        country="India",
        wikidata_id="Q5839",
        sources=(PlaceImageSourceContext(source="geoapify", external_place_id="geoapify-abc", identifiers=identifiers or {}),),
    )


@pytest.mark.anyio
async def test_reuses_imported_geoapify_image_without_details_call() -> None:
    calls = 0
    def handler(_: httpx.Request) -> httpx.Response:
        nonlocal calls
        calls += 1
        return httpx.Response(500)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await GeoapifyImageProvider("key", base_url="https://api.geoapify.com", client=client).resolve(
            context({"geoapify_image": "https://images.example/hawa.jpg"})
        )
    assert result is not None
    assert result.url == "https://images.example/hawa.jpg"
    assert calls == 0


@pytest.mark.anyio
async def test_uses_place_details_only_when_existing_payload_has_no_image() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v2/place-details"
        assert request.url.params["id"] == "abc"
        return httpx.Response(200, json={"features": [{"properties": {"wiki_and_media": {"image": "https://images.example/details.jpg"}}}]})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        result = await GeoapifyImageProvider("key", base_url="https://api.geoapify.com", client=client).resolve(context())
    assert result is not None
    assert result.url.endswith("details.jpg")
