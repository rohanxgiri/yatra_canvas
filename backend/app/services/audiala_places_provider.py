"""Fetch and serve Audiala places dataset."""

import json
import logging
import math
from pathlib import Path
from typing import ClassVar

from app.schemas.recommendation import DiscoveryCategory
from app.services.place_deduplication_service import haversine_distance_meters
from app.services.openstreetmap_places_service import OpenStreetMapNearbyPlace

logger = logging.getLogger(__name__)

AUDIALA_CATEGORY_MAPPING = {
    "temple": DiscoveryCategory.RELIGIOUS,
    "religious-site": DiscoveryCategory.RELIGIOUS,
    "mosque": DiscoveryCategory.RELIGIOUS,
    "church": DiscoveryCategory.RELIGIOUS,
    "cathedral": DiscoveryCategory.RELIGIOUS,
    "monastery": DiscoveryCategory.RELIGIOUS,
    "synagogue": DiscoveryCategory.RELIGIOUS,
    "restaurant": DiscoveryCategory.FOOD,
    "attraction": DiscoveryCategory.TOURISM,
    "museum": DiscoveryCategory.TOURISM,
    "park": DiscoveryCategory.NATURE,
    "botanical-garden": DiscoveryCategory.NATURE,
    "zoo": DiscoveryCategory.TOURISM,
    "amusement-park": DiscoveryCategory.TOURISM,
    "square": DiscoveryCategory.TOURISM,
    "memorial": DiscoveryCategory.TOURISM,
    "bridge": DiscoveryCategory.TOURISM,
    "beach": DiscoveryCategory.NATURE,
    "waterfall": DiscoveryCategory.NATURE,
    "mountain": DiscoveryCategory.NATURE,
    "lake": DiscoveryCategory.NATURE,
    "cave": DiscoveryCategory.NATURE,
    "island": DiscoveryCategory.NATURE,
    "stadium": DiscoveryCategory.TOURISM,
    "theatre": DiscoveryCategory.TOURISM,
    "opera-house": DiscoveryCategory.TOURISM,
    "library": DiscoveryCategory.TOURISM,
    "university": DiscoveryCategory.TOURISM,
    "cemetery": DiscoveryCategory.TOURISM,
    "garden": DiscoveryCategory.NATURE,
    "monument": DiscoveryCategory.HERITAGE,
    "fortification": DiscoveryCategory.HERITAGE,
    "archaeological-site": DiscoveryCategory.HERITAGE,
    "palace": DiscoveryCategory.HERITAGE,
    "statue": DiscoveryCategory.HERITAGE,
    "lighthouse": DiscoveryCategory.HERITAGE,
    "tower": DiscoveryCategory.HERITAGE,
    "building": DiscoveryCategory.HERITAGE,
    "market": DiscoveryCategory.MARKETS,
    "marketplace": DiscoveryCategory.MARKETS,
    "bazaar": DiscoveryCategory.MARKETS,
}

class AudialaPlacesProvider:
    """Provides local tourist places from the Audiala dataset (CC BY 4.0)."""

    _cache: ClassVar[dict[str, list[dict]]] = {}

    def __init__(self, dataset_path: str | None) -> None:
        self._places: list[dict] = []
        self._dataset_path = dataset_path
        self._loaded = False

    def _resolve_path(self) -> Path | None:
        if not self._dataset_path:
            return None

        path = Path(self._dataset_path)
        if path.is_absolute() and path.exists():
            return path

        if path.exists():
            return path.resolve()

        # Try relative to repo root (parents[3])
        repo_root = Path(__file__).resolve().parents[3]
        candidate = repo_root / path
        if candidate.exists():
            return candidate

        # Try relative to backend dir (parents[2])
        backend_dir = Path(__file__).resolve().parents[2]
        candidate = backend_dir / path
        if candidate.exists():
            return candidate

        # If path is named audiala_places.json, check default app data directory
        if path.name == "audiala_places.json":
            app_data = Path(__file__).resolve().parents[1] / "data" / "audiala_places.json"
            if app_data.exists():
                return app_data

        return None

    def _load_if_needed(self) -> None:
        if self._loaded:
            return

        self._loaded = True
        if not self._dataset_path:
            logger.info("Audiala dataset path is not configured. Provider will be inactive.")
            return

        resolved_path = self._resolve_path()
        if not resolved_path or not resolved_path.exists():
            logger.warning(
                "Audiala dataset not found at %s. Audiala discovery will be empty.",
                self._dataset_path,
            )
            return

        cache_key = str(resolved_path.resolve())
        if cache_key in self._cache:
            self._places = self._cache[cache_key]
            return

        try:
            with open(resolved_path, "r", encoding="utf-8") as f:
                self._places = json.load(f)
            self._cache[cache_key] = self._places
            logger.info("Loaded %d Audiala places from %s", len(self._places), resolved_path)
        except Exception as exc:
            logger.error("Failed to load Audiala dataset from %s: %s", resolved_path, exc)

    async def search_nearby_places_for_categories(
        self,
        latitude: float,
        longitude: float,
        categories: list[DiscoveryCategory],
        category_radii: dict[DiscoveryCategory, int],
        category_limits: dict[DiscoveryCategory, int],
    ) -> dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]]:
        """Search Audiala in-memory dataset for nearby places."""
        self._load_if_needed()

        if not self._places:
            return {}

        results: dict[DiscoveryCategory, list[OpenStreetMapNearbyPlace]] = {
            category: [] for category in categories
        }

        # Index pending categories for fast lookup
        requested_categories = set(categories)

        candidates_by_category: dict[DiscoveryCategory, list[tuple[float, dict]]] = {
            category: [] for category in categories
        }

        max_radius_m = max((category_radii.get(cat, 10000) for cat in requested_categories), default=10000)
        # 1 degree of latitude is ~111,000 meters
        max_lat_diff = (max_radius_m + 500) / 111000.0
        lat_rad = math.radians(latitude)
        cos_lat = max(0.2, math.cos(lat_rad))
        max_lon_diff = (max_radius_m + 500) / (111000.0 * cos_lat)

        for record in self._places:
            cat_str = record.get("category")
            mapped_cat = AUDIALA_CATEGORY_MAPPING.get(cat_str)
            if not mapped_cat or mapped_cat not in requested_categories:
                continue

            plat = record.get("latitude")
            plon = record.get("longitude")
            if plat is None or plon is None:
                continue

            if abs(plat - latitude) > max_lat_diff or abs(plon - longitude) > max_lon_diff:
                continue

            radius_m = category_radii.get(mapped_cat, 10000)
            dist_m = haversine_distance_meters(latitude, longitude, plat, plon)

            if dist_m <= radius_m:
                candidates_by_category[mapped_cat].append((dist_m, record))

        for category in categories:
            candidates = candidates_by_category[category]
            if not candidates:
                continue

            # Sort by sitelinks (popularity) descending, then by distance ascending
            candidates.sort(
                key=lambda x: (-(x[1].get("sitelinks") or 0), x[0])
            )
            
            limit = category_limits.get(category, 50)
            top_candidates = candidates[:limit]

            for dist, record in top_candidates:
                tags = {}
                if record.get("category"):
                    tags["audiala:category"] = record["category"]
                if record.get("article_tier"):
                    tags["audiala:article_tier"] = str(record["article_tier"])
                if record.get("wikidata_pagerank"):
                    tags["audiala:pagerank"] = str(record["wikidata_pagerank"])
                if record.get("sitelinks"):
                    tags["audiala:sitelinks"] = str(record["sitelinks"])
                
                name = record.get("name_en")
                if not name:
                    continue

                external_id = record.get("wikidata_id")
                if not external_id:
                    continue

                place = OpenStreetMapNearbyPlace(
                    external_place_id=external_id,
                    name=name,
                    latitude=record["latitude"],
                    longitude=record["longitude"],
                    source_url=record.get("url_en"),
                    tags=tags,
                )
                results[category].append(place)

        return {k: v for k, v in results.items() if v}
