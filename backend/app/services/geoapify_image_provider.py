"""Geoapify image adapter that reuses imported metadata before paid details lookup."""

from __future__ import annotations

import logging

import httpx

from app.services.place_image_provider import (
    PlaceImageCandidate,
    PlaceImageContext,
    first_identifier,
    source_for,
)

logger = logging.getLogger(__name__)


class GeoapifyImageProvider:
    name = "geoapify"

    def __init__(
        self,
        api_key: str | None,
        *,
        base_url: str,
        client: httpx.AsyncClient,
    ) -> None:
        self._api_key = api_key.strip() if api_key else None
        self._base_url = base_url.rstrip("/")
        self._client = client

    async def resolve(self, context: PlaceImageContext) -> PlaceImageCandidate | None:
        imported_url = first_identifier(context, "geoapify_image")
        geo_source = source_for(context, "geoapify")
        if imported_url:
            return self._candidate(imported_url, geo_source, context)

        if not self._api_key or geo_source is None:
            return None
        raw_id = geo_source.external_place_id
        place_id = raw_id.removeprefix("geoapify-")
        if not place_id:
            return None

        response = await self._client.get(
            f"{self._base_url}/v2/place-details",
            params={"id": place_id, "apiKey": self._api_key},
        )
        logger.debug(
            "PLACE_IMAGE_HTTP provider=geoapify operation=place_details "
            "status=%s provider_place_id=%s response=%s",
            response.status_code,
            place_id,
            response.text[:2000],
        )
        response.raise_for_status()
        payload = response.json()
        features = payload.get("features") if isinstance(payload, dict) else None
        props = features[0].get("properties", {}) if features else {}
        media = props.get("wiki_and_media", {}) if isinstance(props, dict) else {}
        image_url = media.get("image") if isinstance(media, dict) else None
        if not isinstance(image_url, str) or not image_url.startswith("http"):
            return None
        return self._candidate(image_url, geo_source, context)

    @staticmethod
    def _candidate(url: str, source, context: PlaceImageContext) -> PlaceImageCandidate:
        return PlaceImageCandidate(
            url=url,
            thumbnail_url=url,
            provider="geoapify",
            provider_place_id=source.external_place_id if source else None,
            source_url=source.source_url if source else None,
            attribution="Image metadata supplied by Geoapify",
            author=None,
            license=None,
            license_url=None,
        )
