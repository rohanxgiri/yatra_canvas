import pytest

from app.services.place_category_normalizer import (
    NormalizedPlaceCategory,
    normalize_place_category,
)


@pytest.mark.parametrize(
    ("category", "name", "expected"),
    [
        ("religious", "Mahakaleshwar Temple", NormalizedPlaceCategory.PLACE_OF_WORSHIP),
        ("tourism", "Amer Fort", NormalizedPlaceCategory.FORT_PALACE),
        ("nature", "Nahargarh Viewpoint", NormalizedPlaceCategory.HILL_VIEWPOINT),
        ("food", "Lassiwala Restaurant", NormalizedPlaceCategory.RESTAURANT),
        ("commercial", "Johari Bazaar", NormalizedPlaceCategory.MARKET_SHOPPING),
        ("unknown", "Unclassified Venue", NormalizedPlaceCategory.OTHER),
    ],
)
def test_normalizes_provider_and_name_signals(category, name, expected) -> None:
    assert normalize_place_category(category, name=name) == expected


def test_specific_name_signal_beats_broad_tourism_label() -> None:
    assert normalize_place_category("tourism", name="City Palace") == NormalizedPlaceCategory.FORT_PALACE
