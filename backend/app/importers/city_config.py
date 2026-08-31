"""Single source of truth for cities allowed in offline POI imports."""

from dataclasses import dataclass
import re
import unicodedata


@dataclass(frozen=True)
class ImportCity:
    slug: str
    name: str
    state: str
    country: str
    latitude: float
    longitude: float
    locality_aliases: frozenset[str]

    def matches_locality(self, locality: str) -> bool:
        return normalize_text(locality) in self.locality_aliases


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold().strip()
    return re.sub(r"[^\w]+", " ", normalized).strip()


# Add future cities only here. Importers must not duplicate city filters.
IMPORT_CITIES: dict[str, ImportCity] = {
    "ujjain": ImportCity(
        slug="ujjain",
        name="Ujjain",
        state="Madhya Pradesh",
        country="India",
        latitude=23.1765,
        longitude=75.7885,
        locality_aliases=frozenset(
            normalize_text(value) for value in ("Ujjain", "Ujjayin", "उज्जैन")
        ),
    ),
}


def get_import_city(slug: str) -> ImportCity:
    try:
        return IMPORT_CITIES[normalize_text(slug).replace(" ", "-")]
    except KeyError as exc:
        supported = ", ".join(sorted(IMPORT_CITIES))
        raise ValueError(
            f"Unsupported import city. Choose one of: {supported}."
        ) from exc
