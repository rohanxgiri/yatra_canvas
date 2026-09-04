"""Tests for AudialaPlacesProvider (CC BY 4.0 offline dataset provider)."""

import asyncio
from pathlib import Path
import pytest

from app.schemas.recommendation import DiscoveryCategory
from app.services.audiala_places_provider import AudialaPlacesProvider


def test_audiala_provider_unconfigured_path_returns_empty() -> None:
    provider = AudialaPlacesProvider(None)
    results = asyncio.run(
        provider.search_nearby_places_for_categories(
            latitude=23.1765,
            longitude=75.7885,
            categories=[DiscoveryCategory.RELIGIOUS],
            category_radii={DiscoveryCategory.RELIGIOUS: 15000},
            category_limits={DiscoveryCategory.RELIGIOUS: 10},
        )
    )
    assert results == {}


def test_audiala_provider_nonexistent_path_fails_gracefully() -> None:
    provider = AudialaPlacesProvider("nonexistent/path/to/dataset.json")
    results = asyncio.run(
        provider.search_nearby_places_for_categories(
            latitude=23.1765,
            longitude=75.7885,
            categories=[DiscoveryCategory.RELIGIOUS],
            category_radii={DiscoveryCategory.RELIGIOUS: 15000},
            category_limits={DiscoveryCategory.RELIGIOUS: 10},
        )
    )
    assert results == {}


def test_audiala_provider_loads_production_dataset() -> None:
    provider = AudialaPlacesProvider("backend/app/data/audiala_places.json")
    results = asyncio.run(
        provider.search_nearby_places_for_categories(
            latitude=23.1765,
            longitude=75.7885,
            categories=[DiscoveryCategory.RELIGIOUS, DiscoveryCategory.TOURISM],
            category_radii={
                DiscoveryCategory.RELIGIOUS: 15000,
                DiscoveryCategory.TOURISM: 15000,
            },
            category_limits={
                DiscoveryCategory.RELIGIOUS: 10,
                DiscoveryCategory.TOURISM: 10,
            },
        )
    )

    assert DiscoveryCategory.RELIGIOUS in results
    places = results[DiscoveryCategory.RELIGIOUS]
    assert len(places) > 0

    # Verify place schema and CC BY 4.0 metadata tags
    first_place = places[0]
    assert first_place.external_place_id.startswith("Q")
    assert first_place.name
    assert first_place.latitude
    assert first_place.longitude
    assert "audiala:category" in first_place.tags


def test_audiala_provider_caches_in_memory_across_instances() -> None:
    provider1 = AudialaPlacesProvider("backend/app/data/audiala_places.json")
    provider2 = AudialaPlacesProvider("backend/app/data/audiala_places.json")

    # Load provider1
    asyncio.run(
        provider1.search_nearby_places_for_categories(
            latitude=23.1765,
            longitude=75.7885,
            categories=[DiscoveryCategory.RELIGIOUS],
            category_radii={DiscoveryCategory.RELIGIOUS: 5000},
            category_limits={DiscoveryCategory.RELIGIOUS: 5},
        )
    )

    # Provider2 should reuse cache
    asyncio.run(
        provider2.search_nearby_places_for_categories(
            latitude=23.1765,
            longitude=75.7885,
            categories=[DiscoveryCategory.RELIGIOUS],
            category_radii={DiscoveryCategory.RELIGIOUS: 5000},
            category_limits={DiscoveryCategory.RELIGIOUS: 5},
        )
    )

    assert provider1._places is provider2._places
