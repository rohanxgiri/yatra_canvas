from uuid import uuid4

import httpx
import pytest

from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_image_provider import PlaceImageContext
from app.services.wikimedia_image_provider import WikimediaImageProvider


def context(*, qid="Q5839", name="Hawa Mahal"):
    return PlaceImageContext(
        place_id=uuid4(),
        name=name,
        raw_category="heritage",
        normalized_category=NormalizedPlaceCategory.LANDMARK,
        latitude=26.9239,
        longitude=75.8267,
        city="Jaipur",
        state="Rajasthan",
        country="India",
        wikidata_id=qid,
    )


@pytest.mark.anyio
async def test_wikidata_p18_preserves_commons_attribution_and_license() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "www.wikidata.org":
            return httpx.Response(
                200,
                json={
                    "entities": {
                        "Q5839": {
                            "claims": {
                                "P18": [
                                    {
                                        "mainsnak": {
                                            "datavalue": {"value": "Hawa Mahal.jpg"}
                                        }
                                    }
                                ]
                            }
                        }
                    }
                },
            )
        return httpx.Response(
            200,
            json={
                "query": {
                    "pages": {
                        "1": {
                            "title": "File:Hawa Mahal.jpg",
                            "imageinfo": [
                                {
                                    "url": "https://upload.wikimedia.org/full.jpg",
                                    "thumburl": "https://upload.wikimedia.org/thumb.jpg",
                                    "descriptionurl": "https://commons.wikimedia.org/wiki/File:Hawa_Mahal.jpg",
                                    "user": "Photographer",
                                    "extmetadata": {
                                        "Artist": {"value": "<b>A. Author</b>"},
                                        "LicenseShortName": {"value": "CC BY-SA 4.0"},
                                        "LicenseUrl": {
                                            "value": "https://creativecommons.org/licenses/by-sa/4.0/"
                                        },
                                        "Credit": {"value": "Own work"},
                                    },
                                }
                            ],
                        }
                    }
                }
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        image = await WikimediaImageProvider(client=client).resolve(context())
    assert image is not None
    assert image.author == "A. Author"
    assert image.license == "CC BY-SA 4.0"
    assert image.attribution == "Own work"


@pytest.mark.anyio
async def test_weak_fuzzy_wikipedia_match_is_rejected() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.params["gsrsearch"] == "Hawa Mahal, Jaipur, Rajasthan, India"
        return httpx.Response(
            200,
            json={
                "query": {
                    "pages": {
                        "1": {
                            "index": 1,
                            "title": "Jaipur unrelated district",
                            "pageimage": "Other.jpg",
                        }
                    }
                }
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        image = await WikimediaImageProvider(client=client).resolve(
            context(qid=None, name="Hawa Mahal")
        )
    assert image is None
