"""Schema and migration parity checks for cache and city persistence repairs."""

from pathlib import Path

from app.models import City, CitySource, PlaceOpeningHours

BACKEND_ROOT = Path(__file__).resolve().parents[1]


def test_opening_hours_model_and_migration_include_updated_at() -> None:
    assert "updated_at" in PlaceOpeningHours.__table__.columns

    forward_path = BACKEND_ROOT / "sql" / "add_place_opening_hours_updated_at.sql"
    forward = forward_path.read_text(encoding="utf-8")
    rollback = (
        BACKEND_ROOT / "sql" / "rollback_place_opening_hours_updated_at.sql"
    ).read_text(encoding="utf-8")

    assert "ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ" in forward
    assert "DROP COLUMN IF EXISTS updated_at" in rollback


def test_city_identity_model_and_migration_have_matching_constraints() -> None:
    city_indexes = {index.name: index for index in City.__table__.indexes}
    assert city_indexes["uq_cities_normalized_identity"].unique is True

    source_uniques = {
        constraint.name
        for constraint in CitySource.__table__.constraints
        if constraint.name
    }
    assert "uq_city_sources_source_external_city" in source_uniques
    city_id_foreign_key = next(iter(CitySource.__table__.c.city_id.foreign_keys))
    assert city_id_foreign_key.ondelete == "CASCADE"

    forward = (BACKEND_ROOT / "sql" / "add_city_identity_and_sources.sql").read_text(
        encoding="utf-8"
    )
    rollback = (
        BACKEND_ROOT / "sql" / "rollback_city_identity_and_sources.sql"
    ).read_text(encoding="utf-8")

    assert "CREATE TABLE IF NOT EXISTS public.city_sources" in forward
    assert "CREATE UNIQUE INDEX IF NOT EXISTS uq_cities_normalized_identity" in forward
    assert "UPDATE public.places" in forward
    assert "UPDATE public.trips" in forward
    assert "DELETE FROM public.cities" in forward
    assert "DROP INDEX IF EXISTS public.uq_cities_normalized_identity" in rollback
    assert "DROP TABLE IF EXISTS public.city_sources" in rollback
