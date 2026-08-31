"""Small provider boundary for runtime location autocomplete."""

from typing import Protocol

from app.schemas.location import LocationAutocompleteResult


class LocationAutocompleteProvider(Protocol):
    async def autocomplete(
        self,
        query: str,
        *,
        location_type: str | None,
        country_code: str,
        latitude: float | None,
        longitude: float | None,
        limit: int,
    ) -> list[LocationAutocompleteResult]: ...
