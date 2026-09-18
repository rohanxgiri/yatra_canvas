#!/usr/bin/env python3
"""Safely inspect and optionally write-test the place image cache schema."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from sqlalchemy import Connection, Engine, create_engine, inspect, text
from sqlalchemy.sql.sqltypes import DateTime, String, Uuid
from sqlmodel import Session

from app.core.config import Settings
from app.core.database_safety import (
    UnsafeDatabaseOperationError,
    require_write_test_environment,
)
from app.models import City, Place, PlaceImageCache

DATABASE_URL_PATTERN = re.compile(
    r"postgres(?:ql)?(?:\+[a-z0-9_]+)?://[^\s'\"]+",
    flags=re.IGNORECASE,
)


@dataclass(frozen=True)
class ColumnExpectation:
    kind: str
    nullable: bool
    length: int | None = None


EXPECTED_COLUMNS = {
    "id": ColumnExpectation("uuid", False),
    "place_id": ColumnExpectation("uuid", False),
    "provider_place_id": ColumnExpectation("string", True, 255),
    "normalized_category": ColumnExpectation("string", False, 40),
    "url": ColumnExpectation("string", True, 2000),
    "thumbnail_url": ColumnExpectation("string", True, 2000),
    "provider": ColumnExpectation("string", True, 40),
    "source_url": ColumnExpectation("string", True, 2000),
    "attribution": ColumnExpectation("string", True, 1000),
    "author": ColumnExpectation("string", True, 500),
    "license": ColumnExpectation("string", True, 160),
    "license_url": ColumnExpectation("string", True, 1000),
    "status": ColumnExpectation("string", False, 20),
    "fetched_at": ColumnExpectation("timestamp_tz", False),
    "expires_at": ColumnExpectation("timestamp_tz", False),
    "failure_reason": ColumnExpectation("string", True, 500),
}

EXPECTED_INDEXES = {
    "ix_place_image_cache_place_id",
    "ix_place_image_cache_provider_place_id",
    "ix_place_image_cache_normalized_category",
    "ix_place_image_cache_provider",
    "ix_place_image_cache_status",
    "ix_place_image_cache_expires_at",
}

EXPECTED_CHECK_TOKENS = {
    "ck_place_image_cache_status": {"resolved", "not_found", "failed"},
    "ck_place_image_cache_provider": {
        "geoapify",
        "wikimedia",
        "foursquare",
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Verify place_image_cache without writes by default. Use --write-test "
            "only against an explicitly classified development/test database."
        )
    )
    parser.add_argument(
        "--write-test",
        action="store_true",
        help="Run a temporary commit/reconnect/read/cleanup persistence test.",
    )
    return parser.parse_args()


def redact_message(message: object, settings: Settings | None = None) -> str:
    """Remove complete database URLs and known URL variants from diagnostic text."""

    rendered = str(message)
    if settings is not None:
        raw_url = settings.database_url.get_secret_value()
        rendered = rendered.replace(raw_url, "[REDACTED_DATABASE_URL]")
        rendered = rendered.replace(
            settings.sqlalchemy_database_url,
            "[REDACTED_DATABASE_URL]",
        )
    return DATABASE_URL_PATTERN.sub("[REDACTED_DATABASE_URL]", rendered)


def _column_type_matches(actual_type: object, expected: ColumnExpectation) -> bool:
    if expected.kind == "uuid":
        return isinstance(actual_type, Uuid)
    if expected.kind == "string":
        return (
            isinstance(actual_type, String)
            and getattr(actual_type, "length", None) == expected.length
        )
    if expected.kind == "timestamp_tz":
        return isinstance(actual_type, DateTime) and bool(
            getattr(actual_type, "timezone", False)
        )
    return False


def inspect_schema(connection: Connection) -> list[str]:
    """Return schema discrepancies without modifying the database."""

    inspector = inspect(connection)
    table_name = "place_image_cache"
    schema = "public"
    if not inspector.has_table(table_name, schema=schema):
        return ["Missing table public.place_image_cache"]

    errors: list[str] = []
    columns = {
        column["name"]: column
        for column in inspector.get_columns(table_name, schema=schema)
    }
    expected_names = set(EXPECTED_COLUMNS)
    actual_names = set(columns)
    if missing := sorted(expected_names - actual_names):
        errors.append(f"Missing columns: {', '.join(missing)}")
    if unexpected := sorted(actual_names - expected_names):
        errors.append(f"Unexpected columns: {', '.join(unexpected)}")

    for name, expected in EXPECTED_COLUMNS.items():
        column = columns.get(name)
        if column is None:
            continue
        if bool(column["nullable"]) != expected.nullable:
            errors.append(f"Column {name} has incorrect nullability")
        if not _column_type_matches(column["type"], expected):
            errors.append(f"Column {name} has incorrect type or length")

    fetched_at = columns.get("fetched_at")
    if fetched_at is not None and fetched_at.get("default") not in (None, ""):
        errors.append("Column fetched_at must not have a server-side default")

    primary_key = inspector.get_pk_constraint(table_name, schema=schema)
    if primary_key.get("constrained_columns") != ["id"]:
        errors.append("Primary key must contain only id")

    unique_constraints = {
        constraint.get("name"): constraint
        for constraint in inspector.get_unique_constraints(table_name, schema=schema)
    }
    place_unique = unique_constraints.get("uq_place_image_cache_place_id")
    if place_unique is None or place_unique.get("column_names") != ["place_id"]:
        errors.append("Missing or incorrect uq_place_image_cache_place_id")

    indexes = inspector.get_indexes(table_name, schema=schema)
    index_names = {
        index["name"]
        for index in indexes
        if index.get("name") and not index.get("duplicates_constraint")
    }
    if missing_indexes := sorted(EXPECTED_INDEXES - index_names):
        errors.append(f"Missing indexes: {', '.join(missing_indexes)}")
    if unexpected_indexes := sorted(index_names - EXPECTED_INDEXES):
        errors.append(f"Unexpected indexes: {', '.join(unexpected_indexes)}")

    checks = {
        constraint.get("name"): (constraint.get("sqltext") or "").lower()
        for constraint in inspector.get_check_constraints(table_name, schema=schema)
    }
    for name, tokens in EXPECTED_CHECK_TOKENS.items():
        expression = checks.get(name)
        if expression is None or any(token not in expression for token in tokens):
            errors.append(f"Missing or incorrect check constraint {name}")

    foreign_keys = inspector.get_foreign_keys(table_name, schema=schema)
    place_foreign_key = next(
        (
            foreign_key
            for foreign_key in foreign_keys
            if foreign_key.get("constrained_columns") == ["place_id"]
        ),
        None,
    )
    if (
        place_foreign_key is None
        or place_foreign_key.get("referred_table") != "places"
        or place_foreign_key.get("referred_columns") != ["id"]
        or (place_foreign_key.get("options") or {}).get("ondelete") != "CASCADE"
    ):
        errors.append("Missing or incorrect place_id foreign key with ON DELETE CASCADE")

    return errors


def verify_schema_read_only(engine: Engine) -> list[str]:
    """Inspect the catalog inside a transaction that PostgreSQL enforces as read-only."""

    with engine.connect() as connection:
        connection.execute(text("SET TRANSACTION READ ONLY"))
        try:
            return inspect_schema(connection)
        finally:
            connection.rollback()


def _delete_test_rows(
    engine: Engine,
    *,
    cache_id: UUID,
    place_id: UUID,
    city_id: UUID,
) -> None:
    """Delete only rows whose UUIDs were generated by this invocation."""

    with Session(engine) as session:
        for model, record_id in (
            (PlaceImageCache, cache_id),
            (Place, place_id),
            (City, city_id),
        ):
            record = session.get(model, record_id)
            if record is not None:
                session.delete(record)
        session.commit()


def run_write_test(engine: Engine) -> None:
    """Commit unique temporary rows, reconnect, verify them, and always clean up."""

    invocation_id = uuid4()
    identifier = f"yatracanvas-place-image-cache-verification-{invocation_id}"
    city_id = uuid4()
    place_id = uuid4()
    cache_id = uuid4()
    now = datetime.now(timezone.utc)
    expected_url = f"https://example.invalid/{invocation_id}.jpg"
    print(f"TEST_IDENTIFIER={identifier}")

    try:
        with Session(engine) as session:
            session.add(
                City(
                    id=city_id,
                    name=identifier,
                    state="Database verification",
                    country="Test",
                    latitude=0,
                    longitude=0,
                )
            )
            session.add(
                Place(
                    id=place_id,
                    city_id=city_id,
                    name=identifier,
                    category="cafe",
                    latitude=0,
                    longitude=0,
                )
            )
            session.add(
                PlaceImageCache(
                    id=cache_id,
                    place_id=place_id,
                    provider_place_id=identifier,
                    normalized_category="cafe",
                    url=expected_url,
                    thumbnail_url=expected_url,
                    provider="wikimedia",
                    source_url="https://example.invalid/source",
                    attribution="YatraCanvas temporary database verification",
                    author="YatraCanvas test utility",
                    license="test-only",
                    license_url="https://example.invalid/license",
                    status="resolved",
                    fetched_at=now,
                    expires_at=now + timedelta(minutes=5),
                )
            )
            session.commit()

        with Session(engine) as fresh_session:
            persisted = fresh_session.get(PlaceImageCache, cache_id)
            if persisted is None:
                raise RuntimeError("Temporary cache row did not persist across sessions")
            expected = {
                "place_id": place_id,
                "provider_place_id": identifier,
                "normalized_category": "cafe",
                "url": expected_url,
                "provider": "wikimedia",
                "status": "resolved",
            }
            for field, expected_value in expected.items():
                if getattr(persisted, field) != expected_value:
                    raise RuntimeError(
                        f"Temporary cache field did not persist correctly: {field}"
                    )
    finally:
        _delete_test_rows(
            engine,
            cache_id=cache_id,
            place_id=place_id,
            city_id=city_id,
        )

def main() -> int:
    args = parse_args()
    settings: Settings | None = None
    try:
        settings = Settings()
        if args.write_test:
            require_write_test_environment(settings)
    except UnsafeDatabaseOperationError as exc:
        print("SAFETY_GUARD=REFUSED")
        print(f"ERROR={redact_message(exc, settings)}")
        return 2
    except Exception as exc:  # noqa: BLE001 - never allow config errors to leak URLs.
        print("CONFIGURATION=FAIL")
        print(f"ERROR_TYPE={type(exc).__name__}")
        return 2

    environment = settings.app_env.value if settings.app_env is not None else "unset"
    print("DATABASE_URL=[REDACTED_DATABASE_URL]")
    print(f"APP_ENV={environment}")
    print(f"MODE={'WRITE_TEST' if args.write_test else 'READ_ONLY_SCHEMA_CHECK'}")

    engine = create_engine(settings.sqlalchemy_database_url, pool_pre_ping=True)
    try:
        schema_errors = verify_schema_read_only(engine)
        if schema_errors:
            print("SCHEMA_CHECK=FAIL")
            for error in schema_errors:
                print(f"SCHEMA_ERROR={redact_message(error, settings)}")
            return 1
        print("SCHEMA_CHECK=PASS")

        if not args.write_test:
            print("WRITE_TEST=SKIPPED")
            return 0

        run_write_test(engine)
        print("WRITE_TEST=PASS")
        print("WRITE_TEST_CLEANUP=PASS")
        return 0
    except Exception as exc:  # noqa: BLE001 - final redaction boundary for DB errors.
        print("VERIFICATION=FAIL")
        print(f"ERROR={redact_message(exc, settings)}")
        return 1
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
