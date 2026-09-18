"""Optional Foursquare Places image adapter with conservative venue matching."""

from __future__ import annotations

import unicodedata
from difflib import SequenceMatcher

import httpx

from app.services.place_category_normalizer import NormalizedPlaceCategory
from app.services.place_deduplication_service import haversine_distance_meters
from app.services.place_image_provider import PlaceImageCandidate, PlaceImageContext

_CATEGORY_TERMS: dict[NormalizedPlaceCategory, tuple[str, ...]] = {
    NormalizedPlaceCategory.CAFE: ("cafe", "coffee", "tea"),
    NormalizedPlaceCategory.RESTAURANT: ("restaurant", "food", "dining"),
    NormalizedPlaceCategory.HOTEL: ("hotel", "lodging", "resort"),
    NormalizedPlaceCategory.MARKET_SHOPPING: ("market", "shopping", "store", "mall"),
    NormalizedPlaceCategory.PLACE_OF_WORSHIP: ("temple", "mosque", "church", "religious"),
    NormalizedPlaceCategory.MUSEUM: ("museum", "gallery"),
    NormalizedPlaceCategory.FORT_PALACE: ("historic", "palace", "fort", "landmark"),
    NormalizedPlaceCategory.LANDMARK: ("landmark", "historic", "attraction"),
}


def _fold(value: object) -> str:
    return "".join(
        character
        for character in unicodedata.normalize("NFKD", str(value).casefold())
        if not unicodedata.combining(character)
    )


class FoursquareImageProvider:
    name = "foursquare"

    def __init__(self, api_key: str | None, *, base_url: str, client: httpx.AsyncClient) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._base_url = base_url.rstrip("/")
        self._client = client

    async def resolve(self, context: PlaceImageContext) -> PlaceImageCandidate | None:
        if not self._api_key:
            return None
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "X-Places-Api-Version": "2025-06-17",
        }
        response = await self._client.get(
            f"{self._base_url}/places/search",
            headers=headers,
            params={
                "query": context.name,
                "ll": f"{context.latitude},{context.longitude}",
                "radius": 500,
                "limit": 5,
                "fields": "fsq_place_id,name,latitude,longitude,categories,location",
            },
        )
        response.raise_for_status()
        results = response.json().get("results", [])
        matched = self._best_match(context, results)
        if matched is None:
            return None
        place_id = matched.get("fsq_place_id")
        if not place_id:
            return None
        photo_response = await self._client.get(
            f"{self._base_url}/places/{place_id}/photos",
            headers=headers,
            params={"limit": 25, "sort": "NEWEST"},
        )
        photo_response.raise_for_status()
        photo = self._select_photo(photo_response.json())
        if photo is None:
            return None
        url = self._photo_url(photo)
        if not url:
            return None
        return PlaceImageCandidate(
            url=url,
            thumbnail_url=photo.get("thumbnail_url") or url,
            provider="foursquare",
            provider_place_id=str(place_id),
            source_url=f"https://foursquare.com/v/{place_id}",
            attribution="Foursquare",
            author=None,
            license=None,
            license_url=None,
        )

    @staticmethod
    def _best_match(context: PlaceImageContext, results: list[dict]) -> dict | None:
        best: tuple[float, dict] | None = None
        for item in results:
            name = str(item.get("name", ""))
            name_score = SequenceMatcher(None, _fold(context.name), _fold(name)).ratio()
            if name_score < 0.78:
                continue
            lat = item.get("latitude")
            lon = item.get("longitude")
            if lat is None or lon is None:
                continue
            distance = haversine_distance_meters(
                context.latitude, context.longitude, float(lat), float(lon)
            )
            if distance > 300:
                continue
            category_names = " ".join(
                str(category.get("name", "")) for category in item.get("categories", [])
            )
            category_names = _fold(category_names)
            expected = _CATEGORY_TERMS.get(context.normalized_category, ())
            category_match = not expected or any(term in category_names for term in expected)
            if expected and not category_match:
                continue
            locality = _fold((item.get("location") or {}).get("locality", ""))
            city = _fold(context.city)
            if locality and city not in locality and locality not in city:
                continue
            score = name_score + max(0.0, 1.0 - distance / 300.0) * 0.35
            if best is None or score > best[0]:
                best = (score, item)
        return best[1] if best else None

    @staticmethod
    def _select_photo(payload: object) -> dict | None:
        photos = payload.get("results", []) if isinstance(payload, dict) else payload
        if not isinstance(photos, list):
            return None
        excluded = {"logo", "logos", "menu", "product"}
        preferred = (
            "outdoor",
            "outdoor_building",
            "monuments_and_landmark_buildings",
            "indoor",
            "indoor_room",
            "food_or_drink",
            "facilities",
        )
        acceptable: list[tuple[int, dict]] = []
        for photo in photos:
            if not isinstance(photo, dict):
                continue
            classification = str(
                photo.get("classification") or photo.get("classifications") or ""
            ).casefold()
            if any(value in classification for value in excluded):
                continue
            rank = next((i for i, value in enumerate(preferred) if value in classification), len(preferred))
            acceptable.append((rank, photo))
        return min(acceptable, key=lambda item: item[0])[1] if acceptable else None

    @staticmethod
    def _photo_url(photo: dict) -> str | None:
        for key in ("original_url", "url"):
            value = photo.get(key)
            if isinstance(value, str) and value.startswith("http"):
                return value
        prefix, suffix = photo.get("prefix"), photo.get("suffix")
        if isinstance(prefix, str) and isinstance(suffix, str):
            return f"{prefix}original{suffix}"
        return None
