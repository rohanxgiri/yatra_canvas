"""Provider-neutral runtime location autocomplete schemas."""

from sqlmodel import Field, SQLModel


class LocationAutocompleteResult(SQLModel):
    provider: str
    provider_place_id: str
    name: str
    formatted_address: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    city: str | None = None
    state: str | None = None
    country_code: str
    result_type: str


class LocationAutocompleteResponse(SQLModel):
    results: list[LocationAutocompleteResult]
