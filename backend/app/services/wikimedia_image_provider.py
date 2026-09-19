"""Conservative Wikimedia/Wikipedia image resolver with license metadata."""

from __future__ import annotations

import html
import logging
import re
from difflib import SequenceMatcher
from urllib.parse import quote, unquote, urlparse

import httpx

from app.services.place_deduplication_service import haversine_distance_meters
from app.services.place_image_provider import (
    PlaceImageCandidate,
    PlaceImageContext,
    first_identifier,
    place_image_search_query,
)

logger = logging.getLogger(__name__)


def _plain(value: object) -> str | None:
    if value is None:
        return None
    text = re.sub(r"<[^>]+>", "", html.unescape(str(value))).strip()
    return text or None


class WikimediaImageProvider:
    name = "wikimedia"

    def __init__(self, *, client: httpx.AsyncClient) -> None:
        self._client = client

    async def resolve(self, context: PlaceImageContext) -> PlaceImageCandidate | None:
        commons = first_identifier(context, "wikimedia_commons")
        if commons:
            title = self._commons_title(commons)
            candidate = await self._commons_image(title)
            if candidate:
                return candidate

        wikidata_id = context.wikidata_id or first_identifier(context, "wikidata")
        if wikidata_id:
            response = await self._client.get(
                "https://www.wikidata.org/w/api.php",
                params={
                    "action": "wbgetentities",
                    "ids": wikidata_id,
                    "props": "claims",
                    "format": "json",
                },
            )
            response.raise_for_status()
            claims = (
                response.json()
                .get("entities", {})
                .get(wikidata_id, {})
                .get("claims", {})
            )
            p18 = claims.get("P18", [])
            if p18:
                filename = p18[0].get("mainsnak", {}).get("datavalue", {}).get("value")
                if filename:
                    candidate = await self._commons_image(f"File:{filename}")
                    if candidate:
                        return candidate

        wikipedia = first_identifier(context, "wikipedia")
        if wikipedia:
            title = self._wikipedia_title(wikipedia)
            candidate = await self._wikipedia_page_image(title, context, direct=True)
            if candidate:
                return candidate

        return await self._fuzzy_wikipedia(context)

    async def _fuzzy_wikipedia(
        self, context: PlaceImageContext
    ) -> PlaceImageCandidate | None:
        query = place_image_search_query(context)
        response = await self._client.get(
            "https://en.wikipedia.org/w/api.php",
            params={
                "action": "query",
                "generator": "search",
                "gsrsearch": query,
                "gsrnamespace": 0,
                "gsrlimit": 4,
                "prop": "coordinates|pageimages|info",
                "piprop": "name|thumbnail|original",
                "pithumbsize": 800,
                "inprop": "url",
                "format": "json",
            },
        )
        logger.debug(
            "PLACE_IMAGE_HTTP provider=wikimedia operation=search status=%s "
            "query=%r response=%s",
            response.status_code,
            query,
            response.text[:2000],
        )
        response.raise_for_status()
        pages = response.json().get("query", {}).get("pages", {})
        expected = context.name.casefold()
        for page in sorted(pages.values(), key=lambda item: item.get("index", 999)):
            title = str(page.get("title", ""))
            similarity = SequenceMatcher(None, expected, title.casefold()).ratio()
            if similarity < 0.76 and expected not in title.casefold():
                continue
            coords = page.get("coordinates") or []
            if coords:
                distance = haversine_distance_meters(
                    context.latitude,
                    context.longitude,
                    float(coords[0]["lat"]),
                    float(coords[0]["lon"]),
                )
                if distance > 5000:
                    continue
            page_image = page.get("pageimage")
            if page_image:
                candidate = await self._commons_image(f"File:{page_image}")
                if candidate:
                    return candidate
        return None

    async def _wikipedia_page_image(
        self, title: str, context: PlaceImageContext, *, direct: bool
    ) -> PlaceImageCandidate | None:
        response = await self._client.get(
            "https://en.wikipedia.org/w/api.php",
            params={
                "action": "query",
                "titles": title,
                "prop": "pageimages",
                "piprop": "name",
                "format": "json",
            },
        )
        response.raise_for_status()
        pages = response.json().get("query", {}).get("pages", {})
        page = next(iter(pages.values()), {})
        page_image = page.get("pageimage")
        return await self._commons_image(f"File:{page_image}") if page_image else None

    async def _commons_image(self, title: str) -> PlaceImageCandidate | None:
        lowered_title = title.casefold()
        if any(
            excluded in lowered_title
            for excluded in (" logo", "flag of", " map", "seal of", "coat of arms")
        ):
            return None
        response = await self._client.get(
            "https://commons.wikimedia.org/w/api.php",
            params={
                "action": "query",
                "titles": title,
                "prop": "imageinfo",
                "iiprop": "url|user|extmetadata",
                "iiurlwidth": 800,
                "format": "json",
            },
        )
        response.raise_for_status()
        pages = response.json().get("query", {}).get("pages", {})
        page = next(iter(pages.values()), {})
        infos = page.get("imageinfo") or []
        if not infos:
            return None
        info = infos[0]
        url = info.get("url")
        if not isinstance(url, str) or not url.startswith("http"):
            return None
        meta = info.get("extmetadata") or {}
        value = lambda key: _plain((meta.get(key) or {}).get("value"))
        page_title = str(page.get("title", title))
        source_url = info.get("descriptionurl") or (
            f"https://commons.wikimedia.org/wiki/{quote(page_title.replace(' ', '_'))}"
        )
        return PlaceImageCandidate(
            url=url,
            thumbnail_url=info.get("thumburl") or url,
            provider="wikimedia",
            provider_place_id=page_title,
            source_url=source_url,
            attribution=value("Credit") or value("Attribution") or "Wikimedia Commons",
            author=value("Artist") or _plain(info.get("user")),
            license=value("LicenseShortName") or value("UsageTerms"),
            license_url=value("LicenseUrl"),
        )

    @staticmethod
    def _commons_title(value: str) -> str:
        if value.startswith("http"):
            path = unquote(urlparse(value).path)
            title = path.rsplit("/", 1)[-1].replace("_", " ")
        else:
            title = value.replace("_", " ")
        if not title.casefold().startswith("file:"):
            title = f"File:{title}"
        return title

    @staticmethod
    def _wikipedia_title(value: str) -> str:
        if value.startswith("http"):
            return unquote(urlparse(value).path.rsplit("/", 1)[-1]).replace("_", " ")
        if ":" in value and len(value.split(":", 1)[0]) <= 3:
            value = value.split(":", 1)[1]
        return value.replace("_", " ")
