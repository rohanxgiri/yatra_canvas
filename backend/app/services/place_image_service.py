"""Persistent cache, provider orchestration, and non-blocking image enrichment."""

from __future__ import annotations

import asyncio
import logging
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse
from uuid import UUID

import httpx
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError
from sqlmodel import Session, select

from app.core.config import Settings, get_settings
from app.models import City, Place, PlaceImageCache, PlaceSource
from app.schemas.place import PlaceRead
from app.schemas.place_image import PlaceImageRead
from app.services.foursquare_image_provider import FoursquareImageProvider
from app.services.geoapify_image_provider import GeoapifyImageProvider
from app.services.place_category_normalizer import (
    NormalizedPlaceCategory,
    is_business_category,
    is_nature_category,
    normalize_place_category,
)
from app.services.place_image_provider import (
    PlaceImageCandidate,
    PlaceImageContext,
    PlaceImageSourceContext,
    place_image_identity_key,
    place_image_search_query,
)
from app.services.provider_rate_control import (
    WikimediaRateController,
    WikimediaRateLimitedError,
)
from app.services.wikimedia_image_provider import WikimediaImageProvider

logger = logging.getLogger(__name__)

IMAGE_ENRICHMENT_BATCH_SIZE = 10
IMAGE_ENRICHMENT_MAX_PER_SCHEDULE = 20


def _aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=timezone.utc)


def image_read_from_cache(row: PlaceImageCache) -> PlaceImageRead:
    return PlaceImageRead(
        url=row.url,
        thumbnail_url=row.thumbnail_url,
        provider=row.provider,  # type: ignore[arg-type]
        source_url=row.source_url,
        attribution=row.attribution,
        author=row.author,
        license=row.license,
        license_url=row.license_url,
        status=row.status,  # type: ignore[arg-type]
    )


def get_cached_place_images(
    session: Session,
    place_ids: list[UUID] | set[UUID],
    *,
    include_expired_resolved: bool = True,
) -> tuple[dict[UUID, PlaceImageRead], set[UUID]]:
    """Return cached images in one query plus ids that should refresh."""

    ids = list(dict.fromkeys(place_ids))
    if not ids:
        return {}, set()
    try:
        rows = session.exec(
            select(PlaceImageCache).where(PlaceImageCache.place_id.in_(ids))
        ).all()
    except SQLAlchemyError as exc:
        logger.warning(
            "PLACE_IMAGE_CACHE_UNAVAILABLE error=%s",
            type(exc).__name__,
        )
        session.rollback()
        return {}, set(ids)
    now = datetime.now(timezone.utc)
    images: dict[UUID, PlaceImageRead] = {}
    refresh = set(ids)
    for row in rows:
        expired = _aware(row.expires_at) <= now
        if not expired:
            refresh.discard(row.place_id)
        if not expired or (include_expired_resolved and row.status == "resolved"):
            images[row.place_id] = image_read_from_cache(row)
    return images, refresh


def build_place_reads(
    session: Session,
    places: list[Place],
) -> tuple[list[PlaceRead], set[UUID]]:
    """Serialize places with one image-cache lookup and no remote I/O."""

    images, refresh = get_cached_place_images(session, [place.id for place in places])
    result: list[PlaceRead] = []
    for place in places:
        item = PlaceRead.model_validate(place)
        item.image = images.get(place.id)
        result.append(item)
    return result, refresh


def enrich_image_reads(
    session: Session,
    items: list,
    *,
    id_attribute: str = "id",
) -> set[UUID]:
    """Attach normalized category/image fields to API read models in two queries."""

    ids = [
        getattr(item, id_attribute)
        for item in items
        if getattr(item, id_attribute, None)
    ]
    if not ids:
        return set()
    places = {
        place.id: place
        for place in session.exec(select(Place).where(Place.id.in_(ids))).all()
    }
    images, refresh = get_cached_place_images(session, ids)
    for item in items:
        place_id = getattr(item, id_attribute, None)
        place = places.get(place_id)
        if place is None:
            continue
        if hasattr(item, "category"):
            item.category = place.category
        if hasattr(item, "normalized_category"):
            item.normalized_category = normalize_place_category(
                place.category, name=place.name
            ).value
        if hasattr(item, "image"):
            item.image = images.get(place_id)
    return refresh


class PlaceImageResolver:
    """Resolve missing/stale place images with bounded concurrency and one HTTP client."""

    def __init__(self, settings: Settings | None = None) -> None:
        self._settings = settings or get_settings()
        self._validation_client: httpx.AsyncClient | None = None

    async def resolve_many(
        self,
        session: Session,
        place_ids: list[UUID] | set[UUID],
        *,
        force: bool = False,
    ) -> dict[UUID, PlaceImageRead]:
        ids = list(dict.fromkeys(place_ids))
        if not ids:
            return {}
        cached, refresh_ids = get_cached_place_images(session, ids)
        targets = set(ids) if force else refresh_ids
        if not targets:
            logger.info("PLACE_IMAGE_CACHE_HIT count=%d", len(ids))
            return cached
        logger.info(
            "PLACE_IMAGE_CACHE_MISS requested=%d refresh=%d", len(ids), len(targets)
        )

        contexts = self._load_contexts(session, targets)
        timeout = httpx.Timeout(
            self._settings.place_image_timeout_seconds,
            connect=min(3.0, self._settings.place_image_timeout_seconds),
        )
        headers = {
            "User-Agent": (
                "YatraCanvas/0.1 "
                "(https://github.com/rohanxgiri/yatra_canvas; image resolver)"
            )
        }
        semaphore = asyncio.Semaphore(self._settings.place_image_concurrency)
        started = time.perf_counter()
        async with httpx.AsyncClient(
            timeout=timeout,
            headers=headers,
            follow_redirects=True,
        ) as client:
            self._validation_client = client
            providers = {
                "geoapify": GeoapifyImageProvider(
                    self._settings.geoapify_api_key_value,
                    base_url=self._settings.geoapify_base_url,
                    client=client,
                ),
                "wikimedia": WikimediaImageProvider(
                    client=client,
                    rate_controller=WikimediaRateController(session.get_bind()),
                ),
                "foursquare": FoursquareImageProvider(
                    self._settings.foursquare_api_key_value,
                    base_url=self._settings.foursquare_base_url,
                    client=client,
                ),
            }

            async def resolve_one(context: PlaceImageContext):
                async with semaphore:
                    try:
                        candidate, had_error = await asyncio.wait_for(
                            self._resolve_context(context, providers),
                            timeout=self._settings.place_image_timeout_seconds * 2,
                        )
                    except TimeoutError:
                        logger.warning(
                            "PLACE_IMAGE_FAILED place_id=%s stage=total_budget",
                            context.place_id,
                        )
                        candidate, had_error = None, True
                    return context, candidate, had_error

            try:
                results = await asyncio.gather(
                    *(resolve_one(context) for context in contexts),
                    return_exceptions=True,
                )
            finally:
                self._validation_client = None

        now = datetime.now(timezone.utc)
        existing_rows = {
            row.place_id: row
            for row in session.exec(
                select(PlaceImageCache).where(
                    PlaceImageCache.place_id.in_(list(targets))
                )
            ).all()
        }
        for result in results:
            if isinstance(result, BaseException):
                logger.warning(
                    "PLACE_IMAGE_FAILED stage=resolve error=%s", type(result).__name__
                )
                continue
            context, candidate, had_error = result
            row = existing_rows.get(context.place_id)
            if row is None:
                row = PlaceImageCache(
                    place_id=context.place_id,
                    normalized_category=context.normalized_category.value,
                    status="failed",
                    expires_at=now,
                )
                session.add(row)
            row.normalized_category = context.normalized_category.value
            row.fetched_at = now
            if candidate is not None:
                self._apply_candidate(row, candidate)
                row.status = "resolved"
                row.failure_reason = None
                row.expires_at = now + timedelta(
                    hours=self._settings.place_image_cache_ttl_hours
                )
                cached[context.place_id] = image_read_from_cache(row)
            else:
                row.url = None
                row.thumbnail_url = None
                row.provider = None
                row.provider_place_id = None
                row.source_url = None
                row.attribution = None
                row.author = None
                row.license = None
                row.license_url = None
                row.status = "failed" if had_error else "not_found"
                row.failure_reason = "provider_error" if had_error else None
                ttl = (
                    timedelta(minutes=self._settings.place_image_failed_ttl_minutes)
                    if had_error
                    else timedelta(hours=self._settings.place_image_negative_ttl_hours)
                )
                row.expires_at = now + ttl
                cached[context.place_id] = image_read_from_cache(row)
        session.commit()
        logger.info(
            "PLACE_IMAGE_BATCH_COMPLETE requested=%d resolved=%d elapsed_ms=%d",
            len(targets),
            sum(1 for image in cached.values() if image.status == "resolved"),
            round((time.perf_counter() - started) * 1000),
        )
        return cached

    async def _resolve_context(self, context, providers):
        had_error = False
        logger.info(
            "PLACE_IMAGE_LOOKUP place_id=%s cache_key=%s name=%r category=%s "
            "city=%r latitude=%.5f longitude=%.5f provider_query=%r",
            context.place_id,
            place_image_identity_key(context),
            context.name,
            context.normalized_category.value,
            context.city,
            context.latitude,
            context.longitude,
            place_image_search_query(context),
        )
        for name in self._provider_order(context.normalized_category):
            provider_started = time.perf_counter()
            attempts = 1 if name == "wikimedia" else 2
            for attempt in range(attempts):
                try:
                    candidate = await providers[name].resolve(context)
                    logger.info(
                        "PLACE_IMAGE_PROVIDER place_id=%s provider=%s outcome=%s elapsed_ms=%d",
                        context.place_id,
                        name,
                        "resolved" if candidate else "miss",
                        round((time.perf_counter() - provider_started) * 1000),
                    )
                    if candidate is not None:
                        validation_client = self._validation_client
                        if (
                            validation_client is not None
                            and not await self._candidate_url_is_image(
                                validation_client,
                                context,
                                candidate,
                            )
                        ):
                            had_error = True
                            logger.warning(
                                "PLACE_IMAGE_PROVIDER_FAILED place_id=%s provider=%s "
                                "error=invalid_image_response",
                                context.place_id,
                                name,
                            )
                            break
                        return candidate, had_error
                    break
                except WikimediaRateLimitedError as exc:
                    had_error = True
                    logger.warning(
                        "PLACE_IMAGE_PROVIDER_COOLDOWN place_id=%s provider=%s "
                        "retry_after_seconds=%d",
                        context.place_id,
                        name,
                        exc.retry_after_seconds,
                    )
                    break
                except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
                    had_error = True
                    status_code = (
                        exc.response.status_code
                        if isinstance(exc, httpx.HTTPStatusError)
                        else None
                    )
                    retryable = isinstance(exc, httpx.TimeoutException) or (
                        isinstance(exc, httpx.HTTPStatusError)
                        and (
                            exc.response.status_code == 429
                            or exc.response.status_code >= 500
                        )
                    )
                    if attempt == 0 and retryable and attempts > 1:
                        logger.info(
                            "PLACE_IMAGE_PROVIDER_RETRY place_id=%s provider=%s",
                            context.place_id,
                            name,
                        )
                        await asyncio.sleep(0.1)
                        continue
                    logger.warning(
                        "PLACE_IMAGE_PROVIDER_FAILED place_id=%s provider=%s "
                        "http_status=%s error=%s",
                        context.place_id,
                        name,
                        status_code,
                        type(exc).__name__,
                    )
                    break
        return None, had_error

    @staticmethod
    async def _candidate_url_is_image(
        client: httpx.AsyncClient,
        context: PlaceImageContext,
        candidate: PlaceImageCandidate,
    ) -> bool:
        display_url = candidate.thumbnail_url or candidate.url
        parsed = urlparse(display_url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            return False
        async with client.stream(
            "GET",
            display_url,
            headers={"Range": "bytes=0-1023"},
        ) as response:
            content_type = response.headers.get("content-type", "")
            logger.debug(
                "PLACE_IMAGE_URL_CHECK place_id=%s provider=%s status=%s "
                "content_type=%r host=%s",
                context.place_id,
                candidate.provider,
                response.status_code,
                content_type,
                parsed.hostname,
            )
            return response.status_code in {
                200,
                206,
            } and content_type.casefold().startswith("image/")

    @staticmethod
    def _provider_order(category: NormalizedPlaceCategory) -> tuple[str, ...]:
        if is_business_category(category):
            return ("foursquare", "geoapify", "wikimedia")
        if is_nature_category(category):
            return ("geoapify", "wikimedia", "foursquare")
        return ("geoapify", "wikimedia", "foursquare")

    @staticmethod
    def _apply_candidate(row: PlaceImageCache, candidate: PlaceImageCandidate) -> None:
        row.url = candidate.url[:2000]
        row.thumbnail_url = (candidate.thumbnail_url or candidate.url)[:2000]
        row.provider = candidate.provider
        row.provider_place_id = candidate.provider_place_id
        row.source_url = candidate.source_url
        row.attribution = candidate.attribution
        row.author = candidate.author
        row.license = candidate.license
        row.license_url = candidate.license_url

    @staticmethod
    def _load_contexts(
        session: Session, place_ids: set[UUID]
    ) -> list[PlaceImageContext]:
        places = list(
            session.exec(select(Place).where(Place.id.in_(list(place_ids)))).all()
        )
        city_ids = {place.city_id for place in places}
        cities = {
            city.id: city
            for city in session.exec(
                select(City).where(City.id.in_(list(city_ids)))
            ).all()
        }
        sources_by_place: dict[UUID, list[PlaceSource]] = defaultdict(list)
        for source in session.exec(
            select(PlaceSource).where(PlaceSource.place_id.in_(list(place_ids)))
        ).all():
            sources_by_place[source.place_id].append(source)
        contexts: list[PlaceImageContext] = []
        for place in places:
            city = cities.get(place.city_id)
            if city is None:
                continue
            sources = tuple(
                PlaceImageSourceContext(
                    source=source.source,
                    external_place_id=source.external_place_id,
                    source_url=source.source_url,
                    locality=source.locality,
                    region=source.region,
                    country_code=source.country_code,
                    identifiers=dict(source.social_identifiers or {}),
                )
                for source in sources_by_place.get(place.id, [])
            )
            contexts.append(
                PlaceImageContext(
                    place_id=place.id,
                    name=place.name,
                    raw_category=place.category,
                    normalized_category=normalize_place_category(
                        place.category,
                        name=place.name,
                    ),
                    latitude=place.latitude,
                    longitude=place.longitude,
                    city=city.name,
                    state=city.state,
                    country=city.country,
                    wikidata_id=place.wikidata_id,
                    sources=sources,
                )
            )
        return contexts


_background_tasks: set[asyncio.Task[None]] = set()
_background_place_ids: set[UUID] = set()


def schedule_place_image_enrichment(
    place_ids: list[UUID] | set[UUID],
    *,
    engine: Engine | None = None,
) -> None:
    """Schedule best-effort enrichment on the current server loop and return now."""

    ids = [
        place_id
        for place_id in dict.fromkeys(place_ids)
        if place_id not in _background_place_ids
    ][:IMAGE_ENRICHMENT_MAX_PER_SCHEDULE]
    if not ids:
        return
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        return

    _background_place_ids.update(ids)

    async def run() -> None:
        try:
            if engine is None:
                from app.database import get_engine

                target_engine = get_engine()
            else:
                target_engine = engine
            with Session(target_engine) as session:
                for offset in range(0, len(ids), IMAGE_ENRICHMENT_BATCH_SIZE):
                    await PlaceImageResolver().resolve_many(
                        session,
                        ids[offset : offset + IMAGE_ENRICHMENT_BATCH_SIZE],
                    )
        except asyncio.CancelledError:
            raise
        except Exception as exc:  # noqa: BLE001 - background enrichment must never escape
            logger.warning("PLACE_IMAGE_BACKGROUND_FAILED error=%s", type(exc).__name__)
        finally:
            _background_place_ids.difference_update(ids)

    task = asyncio.create_task(run())
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
