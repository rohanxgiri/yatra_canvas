"""Public, provider-neutral place image contract."""

from typing import Literal

from sqlmodel import SQLModel


class PlaceImageRead(SQLModel):
    url: str | None = None
    thumbnail_url: str | None = None
    provider: Literal["geoapify", "wikimedia", "foursquare"] | None = None
    source_url: str | None = None
    attribution: str | None = None
    author: str | None = None
    license: str | None = None
    license_url: str | None = None
    status: Literal["resolved", "not_found", "failed"] = "not_found"
