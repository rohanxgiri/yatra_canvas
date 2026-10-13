"""Durable role, ownership, overlay, audit and migration contracts (AC-1..9)."""

import hashlib
import json
import sqlite3
import zipfile
from pathlib import Path
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.config import Settings, get_settings
from app.core.security import create_access_token
from app.database import get_session
from app.main import app
from app.models import AdminAuditEvent, AdminReview, City, Trip, User
from app.services.admin_city_lab import CityLabService


def test_city_selection_prefers_bundled_source_and_discloses_ties(
    monkeypatch, tmp_path
):
    from app.routers import admin_operations

    monkeypatch.setattr(admin_operations, "BACKEND_DIR", tmp_path / "backend")
    manifest = tmp_path / "assets" / "citypacks" / "sample" / "manifest.json"
    manifest.parent.mkdir(parents=True)
    manifest.write_text(
        json.dumps(
            {
                "city_id": "sample",
                "state": "State",
                "country": "Country",
                "source_release": "reviewed",
            }
        )
    )
    identity = {"id": "sample", "state": "State", "country": "Country"}
    rows = [
        (name, Path(name), {"generated_at": "2026-10-01"}, identity)
        for name in ("base", "reviewed")
    ]
    service = SimpleNamespace(releases=lambda: rows)
    chosen, selection = admin_operations.selected_releases(service)[0]
    assert chosen[0] == "reviewed" and selection["source"] == "BUNDLED_APP"
    manifest.unlink()
    chosen, selection = admin_operations.selected_releases(service)[0]
    assert chosen[0] == "base" and selection["ambiguous"] is True
    assert selection["available_versions"] == ["base", "reviewed"]


@pytest.fixture
def setup(monkeypatch, tmp_path):
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        admin = User(
            name="Admin", email="ops@example.org", password_hash="unused", role="ADMIN"
        )
        user = User(
            name="Traveller", email="person@example.org", password_hash="unused"
        )
        city = City(
            name="Jaipur",
            state="Rajasthan",
            country="India",
            latitude=26.9,
            longitude=75.8,
        )
        session.add_all([admin, user, city])
        session.commit()
        for row in (admin, user, city):
            session.refresh(row)

        def request_session():
            yield session

        app.dependency_overrides[get_session] = request_session
        monkeypatch.setenv("ALLOW_DEV_GUEST", "false")
        monkeypatch.setenv("ENABLE_DEV_ADMIN", "false")
        monkeypatch.setenv("ADMIN_ARTIFACT_ROOT", str(tmp_path / "artifacts"))
        get_settings.cache_clear()
        with TestClient(app) as client:
            yield client, session, admin, user, city
        app.dependency_overrides.clear()
    engine.dispose()


def headers(user):
    return {
        "Authorization": "Bearer "
        + create_access_token({"sub": str(user.id), "role": "ADMIN"})
    }


def test_operational_reports_search_detail_revision_and_audit(setup):
    from app.models import Place, PlaceReport

    client, session, admin, user, city = setup
    place = Place(city_id=city.id, name="Evidence Fort", category="heritage", latitude=26.9, longitude=75.8)
    session.add(place)
    session.commit()
    session.refresh(place)
    report = PlaceReport(place_id=place.id, reason="wrong_category", details="Visitor access uncertain")
    session.add(report)
    session.commit()
    session.refresh(report)
    url = f"/api/admin/reports/{report.id}"
    assert client.get(url).status_code == 401
    assert client.get(url, headers=headers(user)).status_code == 403
    row = client.get(url, headers=headers(admin)).json()
    assert row["place_id"] == str(place.id) and row["place_name"] == place.name
    for query in ({"q": "evidence fort"}, {"q": "access uncertain"}, {"city_id": str(city.id)}, {"place_id": str(place.id)}):
        result = client.get("/api/admin/reports", params=query, headers=headers(admin))
        assert result.status_code == 200 and result.json()[0]["id"] == str(report.id)
    assert client.get("/api/admin/reports", params={"q": "no match"}, headers=headers(admin)).json() == []
    payload = {"status": "REVIEWING", "admin_notes": "Source verification required", "expected_updated_at": row["updated_at"]}
    saved = client.patch(url, json=payload, headers=headers(admin))
    assert saved.status_code == 200, saved.text
    assert saved.json()["status"] == "REVIEWING"
    assert client.patch(url, json={**payload, "status": "RESOLVED"}, headers=headers(admin)).status_code == 409
    assert client.get(url, headers=headers(admin)).json()["status"] == "REVIEWING"
    events = session.exec(select(AdminAuditEvent).where(AdminAuditEvent.entity_id == str(report.id))).all()
    assert len(events) == 1 and events[0].admin_user_id == admin.id
    assert events[0].before["status"] == "OPEN" and events[0].after["status"] == "REVIEWING"


def test_moderation_conflict_does_not_overwrite_decision(setup):
    from app.models import Place

    client, session, admin, _, city = setup
    place = Place(city_id=city.id, name="Fort", category="heritage", latitude=26.9, longitude=75.8)
    session.add(place)
    session.commit()
    session.refresh(place)
    url = f"/api/admin/places/{place.id}"
    payload = {"moderation_status": "HIDDEN", "expected_moderation_status": "ACTIVE", "reason": "Review access evidence"}
    assert client.patch(url, json=payload, headers=headers(admin)).status_code == 200
    assert client.patch(url, json={**payload, "moderation_status": "ACTIVE"}, headers=headers(admin)).status_code == 409
    assert client.get(url, headers=headers(admin)).json()["moderation_status"] == "HIDDEN"


def test_dashboard_has_real_zero_counts_and_refresh_time(setup):
    from datetime import datetime

    client, _, admin, *_ = setup
    row = client.get("/api/admin/dashboard", headers=headers(admin)).json()
    assert row["total_users"] == 2 and row["total_trips"] == 0 and row["total_places"] == 0
    assert row["recent_trips"] == [] and row["recent_reports"] == []
    assert datetime.fromisoformat(row["refreshed_at"]).tzinfo is not None


def test_corrupt_release_is_disclosed_without_hiding_other_cities(setup, monkeypatch, tmp_path):
    client, _, admin, *_ = setup
    key, pack = connect_release(monkeypatch, tmp_path)
    broken = pack.parent / "broken-version"
    broken.mkdir()
    (broken / "manifest.json").write_text("{broken")
    (broken / "places.json").write_text("[]")
    result = client.get("/api/admin/city-lab/cities", headers=headers(admin)).json()
    assert result["items"][0]["id"] == key
    assert result["inventory_complete"] is False and len(result["inventory_problems"]) == 1
    assert "release_key" in result["inventory_problems"][0]
    summary = client.get("/api/admin/city-lab/summary", headers=headers(admin)).json()
    assert summary["published_places"] == 1 and summary["inventory_complete"] is False


@pytest.mark.parametrize("invalid", [None, "mismatch", "nan", "zero_reviews", "critical_blocker", "malformed", "timestamp", "schema"])
def test_lab_evidence_is_validated_and_never_certifies_unbound_bytes(setup, monkeypatch, tmp_path, invalid):
    client, _, admin, *_ = setup
    key, pack = connect_release(monkeypatch, tmp_path)
    report = {
        "schema_version": 1, "release_source": "citypack_lab", "city_id": "jaipur", "pack_version": "v1",
        "data_quality_score": 81.5, "travel_readiness_score": 70.5,
        "manual_qa_reviewed_count": 50, "manual_qa_minimum_required": 50, "manual_qa_passed": True,
        "release_gate_status": "READY", "status": "certified", "criticalIssues": 0,
        "validation_summary": {"manual_qa_sufficient": True, "database_integrity": True},
        "generated_at": "2026-10-12T00:00:00Z", "certified_at": "2026-10-12T00:00:00Z",
    }
    if invalid == "mismatch": report["pack_version"] = "another-version"
    if invalid == "nan": report["data_quality_score"] = float("nan")
    if invalid == "zero_reviews": report["manual_qa_reviewed_count"] = 0
    if invalid == "critical_blocker": report["criticalIssues"] = 1
    if invalid == "timestamp": report["generated_at"] = False
    if invalid == "schema": report["schema_version"] = True
    path = CityLabService().artifact_root() / "lab_reports" / key / "release.json"
    path.parent.mkdir(parents=True)
    path.write_text("{broken" if invalid == "malformed" else json.dumps(report))
    before = CityLabService().fingerprint(pack)
    response = client.get(f"/api/admin/city-lab/cities/{key}", headers=headers(admin))
    assert response.status_code == 200
    row = response.json()
    assert row["status"] == "NOT_CERTIFIED"
    if invalid:
        assert row["readiness"] is None and row["readiness_problem"]
    else:
        assert row["readiness"]["data_quality_score"] == 81.5
        assert row["reported_gate_status"] == "READY"
        assert "no canonical content fingerprint" in row["readiness_scope"]
    assert before == CityLabService().fingerprint(pack)


def test_signup_and_honest_reset(setup):
    client, session, *_ = setup
    payload = {
        "name": " New Traveller ",
        "email": " NEW@EXAMPLE.ORG ",
        "password": "safePassword123",
    }
    response = client.post("/api/auth/signup", json=payload)
    assert response.status_code == 201
    account = response.json()
    assert account["user"]["role"] == "USER" and "password_hash" not in account["user"]
    row = session.exec(select(User).where(User.email == "new@example.org")).one()
    assert row.password_hash != payload["password"] and row.password_hash.startswith(
        "$2"
    )
    assert client.post("/api/auth/signup", json=payload).status_code == 409
    assert (
        client.post("/api/auth/signup", json={**payload, "role": "ADMIN"}).status_code
        == 422
    )
    assert (
        client.post(
            "/api/auth/signup", json={**payload, "password": "short"}
        ).status_code
        == 422
    )
    assert (
        client.post(
            "/api/auth/login",
            json={"email": row.email, "password": payload["password"]},
        ).status_code
        == 200
    )
    result = client.post("/api/auth/forgot-password", json={"email": row.email}).json()
    assert result["available"] is False and "No email was sent" in result["message"]
    assert (
        client.post("/api/auth/forgot-password", json={"email": "bad"}).status_code
        == 422
    )


def test_demo_is_explicit_and_revoked_when_flag_removed(setup, monkeypatch):
    client, session, *_ = setup
    credentials = {"email": "admin@yatracanvas.com", "password": "admin"}
    assert client.post("/api/auth/login", json=credentials).status_code == 401
    monkeypatch.setenv("ENABLE_DEV_ADMIN", "true")
    get_settings.cache_clear()
    response = client.post("/api/auth/login", json=credentials)
    assert response.status_code == 200 and response.json()["user"]["role"] == "ADMIN"
    token = {"Authorization": "Bearer " + response.json()["access_token"]}
    assert client.get("/api/admin/system-health", headers=token).status_code == 200
    assert (
        session.exec(select(User).where(User.email == credentials["email"])).first()
        is None
    )
    monkeypatch.setenv("ENABLE_DEV_ADMIN", "false")
    get_settings.cache_clear()
    assert client.get("/api/admin/system-health", headers=token).status_code == 401


def test_demo_never_shadows_a_registered_account(setup, monkeypatch):
    from app.core.security import hash_password

    client, session, *_ = setup
    monkeypatch.setenv("ENABLE_DEV_ADMIN", "true")
    get_settings.cache_clear()
    credentials = {"email": "admin@yatracanvas.com", "password": "admin"}
    demo = client.post("/api/auth/login", json=credentials).json()
    user = User(name="Registered traveler", email=credentials["email"], password_hash=hash_password("RegisteredOnly123"))
    session.add(user)
    session.commit()
    assert client.post("/api/auth/login", json=credentials).status_code == 401
    token = {"Authorization": "Bearer " + demo["access_token"]}
    assert client.get("/api/admin/dashboard", headers=token).status_code == 401
    registered = client.post("/api/auth/login", json={**credentials, "password": "RegisteredOnly123"})
    assert registered.status_code == 200 and registered.json()["user"]["role"] == "USER"


@pytest.mark.parametrize("field", ["enable_dev_admin", "allow_dev_guest"])
def test_deployment_rejects_development_flags(field):
    with pytest.raises(ValueError, match="Development authentication"):
        Settings(
            _env_file=None,
            DATABASE_URL="postgresql://localhost/isolated_test",
            APP_ENV="production",
            JWT_SECRET_KEY="a-deployment-key",
            **{field: True},
        )


def test_admin_routes_check_live_role_and_deactivation(setup):
    client, session, admin, user, _ = setup
    for path in (
        "system-health",
        "jobs",
        "audit-log",
        "city-lab/cities",
        "city-packs",
        "research/tasks?city=missing",
        "artifacts/" + str(uuid4()),
    ):
        assert client.get("/api/admin/" + path).status_code == 401
        assert (
            client.get("/api/admin/" + path, headers=headers(user)).status_code == 403
        )
    token = headers(admin)
    admin.role = "USER"
    session.add(admin)
    session.commit()
    assert client.get("/api/admin/system-health", headers=token).status_code == 403
    user.is_active = False
    session.add(user)
    session.commit()
    assert client.get("/api/auth/me", headers=headers(user)).status_code == 403


def test_trip_creation_binds_actor_and_all_resource_guards(setup):
    client, session, admin, user, city = setup
    payload = {
        "city_id": str(city.id),
        "days": 2,
        "start_date": "2026-11-01",
        "end_date": "2026-11-02",
        "arrival_place": "Jaipur",
        "purposes": ["leisure"],
        "preferences": ["heritage"],
        "request_id": str(uuid4()),
    }
    guest = client.post("/trips", json=payload)
    assert guest.status_code == 201, guest.text
    guest_id = guest.json()["trip_id"]
    from app.services.trip_service import DEVELOPMENT_USER_ID

    assert session.get(Trip, UUID(guest_id)).user_id == DEVELOPMENT_USER_ID
    assert len(session.exec(select(User)).all()) == 2
    assert client.get("/trips/" + guest_id).status_code == 200
    assert client.get("/trips/" + guest_id, headers=headers(user)).status_code == 404
    assert client.post("/trips", json=payload, headers={"Authorization": "Bearer invalid"}).status_code == 401
    payload["request_id"] = str(uuid4())
    response = client.post("/trips", json=payload, headers=headers(user))
    assert response.status_code == 201, response.text
    trip_id = response.json()["trip_id"]
    assert session.get(Trip, UUID(trip_id)).user_id == user.id
    assert client.get("/trips/" + trip_id).status_code == 404
    other = User(name="Other", email="other@example.org", password_hash="unused")
    session.add(other)
    session.commit()
    for suffix in (
        "",
        "/days",
        "/saved-places",
        "/itinerary",
        "/route-geometry",
        "/weather-advisories",
        "/replan-impact",
    ):
        result = client.get("/trips/" + trip_id + suffix, headers=headers(other))
        assert result.status_code == 404, (suffix, result.text)
    assert client.get("/trips/" + trip_id, headers=headers(admin)).status_code == 403
    assert (
        client.post("/trips", json=payload, headers=headers(other)).status_code == 404
    )
    assert (
        client.get("/api/admin/trips/" + trip_id, headers=headers(admin)).status_code
        == 200
    )
    assert (
        client.get(
            "/api/admin/trips",
            params={"date_state": "UPCOMING", "q": trip_id},
            headers=headers(admin),
        ).json()[0]["id"]
        == trip_id
    )


@pytest.mark.parametrize("environment", [None, "development", "test", "staging", "production"])
def test_guest_trip_access_does_not_depend_on_auth_flags(setup, monkeypatch, environment):
    client, session, _, _, city = setup
    monkeypatch.setattr(Settings, "model_config", {**Settings.model_config, "env_file": None})
    monkeypatch.setenv("DATABASE_URL", "postgresql://localhost/isolated_test")
    if environment is None:
        monkeypatch.delenv("APP_ENV", raising=False)
    else:
        monkeypatch.setenv("APP_ENV", environment)
    monkeypatch.setenv("JWT_SECRET_KEY", "test-only-signing-key-with-at-least-32-characters")
    monkeypatch.setenv("ALLOW_DEV_GUEST", "false")
    get_settings.cache_clear()
    assert get_settings().app_env == environment
    response = client.post("/trips", json={
        "city_id": str(city.id), "days": 1, "start_date": "2026-11-01",
        "end_date": "2026-11-01", "arrival_place": "Jaipur",
        "purposes": ["leisure"], "preferences": ["heritage"],
    })
    assert response.status_code == 201, response.text
    trip_id = response.json()["trip_id"]
    assert client.get("/trips/" + trip_id).status_code == 200
    assert client.patch("/trips/" + trip_id, json={"trip_name": "Guest edit"}).status_code == 200
    assert client.get("/api/admin/trips/" + trip_id).status_code == 401


def connect_release(monkeypatch, tmp_path):
    pack = tmp_path / "releases" / "india" / "rajasthan" / "jaipur" / "v1"
    pack.mkdir(parents=True)
    place = {
        "id": "poi",
        "name": "Fort",
        "description": None,
        "tier": "core_destination",
        "classification": {"category": "heritage"},
        "location": {"latitude": 26.9, "longitude": 75.8},
        "contact": {},
        "images": {},
        "opening_hours": {},
        "sources": [{"source": "official", "url": "https://example.org"}],
    }
    for name, value in {
        "places.json": [place],
        "city.json": {
            "id": "jaipur",
            "name": "Jaipur",
            "state": "Rajasthan",
            "country": "India",
        },
        "manifest.json": {
            "schema_version": 3,
            "generated_at": "2026-10-07",
            "counts": {"accepted": 1},
        },
    }.items():
        (pack / name).write_text(json.dumps(value), encoding="utf-8")
    monkeypatch.setenv("ADMIN_RELEASE_ROOT", str(tmp_path / "releases"))
    get_settings.cache_clear()

    def validate(field, value):
        if field not in {"description", "website"} or not isinstance(value, str):
            raise ValueError("unsupported")

    patch = SimpleNamespace(
        validate_value=validate,
        get_value=lambda p, f: (
            p.get("contact", {}).get(f) if f == "website" else p.get(f)
        ),
    )
    task = {
        "task_id": "description-task",
        "place_id": "poi",
        "type": "DESCRIPTION",
        "priority": "P4",
        "place": {"name": "Fort"},
    }
    modules = {
        "citylab_patch": patch,
        "research.export": SimpleNamespace(make_tasks=lambda *a: [task]),
        "pipeline.identity_assurance": SimpleNamespace(conflict_groups=lambda *a: []),
    }
    monkeypatch.setattr(CityLabService, "module", lambda self, name: modules[name])
    return CityLabService().releases()[0][0], pack


def test_review_export_is_base_bound_audited_and_preserves_source(
    setup, monkeypatch, tmp_path
):
    client, session, admin, _, _ = setup
    key, pack = connect_release(monkeypatch, tmp_path)
    original = (pack / "places.json").read_bytes()
    city = client.get(
        "/api/admin/city-lab/cities/" + key, headers=headers(admin)
    ).json()
    assert city["readiness"] is None and city["status"] == "NOT_CERTIFIED"
    url = f"/api/admin/city-lab/cities/{key}/places/poi"
    payload = {
        "fingerprint": city["fingerprint"],
        "status": "KEEP",
        "changes": {"website": "https://example.org"},
        "evidence_url": "https://example.org",
        "notes": "Official source",
    }
    assert (
        client.patch(
            url, json={**payload, "fingerprint": "old"}, headers=headers(admin)
        ).status_code
        == 409
    )
    assert (
        client.patch(
            url, json={**payload, "evidence_url": None}, headers=headers(admin)
        ).status_code
        == 422
    )
    assert (
        client.patch(
            url, json={**payload, "changes": {"sources": []}}, headers=headers(admin)
        ).status_code
        == 422
    )
    assert client.patch(url, json=payload, headers=headers(admin)).status_code == 200
    assert client.patch(url, json=payload, headers=headers(admin)).status_code == 409
    tasks = client.get(
        "/api/admin/research/tasks",
        params={"city": key, "priority": "P4"},
        headers=headers(admin),
    ).json()
    assert tasks["total"] == 1 and tasks["items"][0]["status"] == "OPEN"
    research_url = "/api/admin/research/description-task/review?city=" + key
    accepted = {
        **payload,
        "status": "ACCEPTED",
        "changes": {"description": "Verified description"},
    }
    assert (
        client.post(research_url, json=accepted, headers=headers(admin)).status_code
        == 200
    )
    result = client.post(
        f"/api/admin/city-lab/cities/{key}/export-patch", headers=headers(admin)
    ).json()
    download = client.get(result["download"], headers=headers(admin))
    zip_path = tmp_path / "download.zip"
    zip_path.write_bytes(download.content)
    with zipfile.ZipFile(zip_path) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        raw = archive.read("changes.json")
        assert (
            manifest["media_count"] == 0
            and manifest["checksums"]["changes.json"] == hashlib.sha256(raw).hexdigest()
        )
        assert json.loads(raw)[0]["changes"] == {
            "website": "https://example.org",
            "description": "Verified description",
        }
    assert (pack / "places.json").read_bytes() == original
    assert len(session.exec(select(AdminReview)).all()) == 2
    events = client.get(
        "/api/admin/audit-log", params={"city": "jaipur"}, headers=headers(admin)
    ).json()["items"]
    assert len(events) == 3 and all(e["admin_user_id"] == str(admin.id) for e in events)
    assert "password_hash" not in json.dumps(events) and "Bearer" not in json.dumps(
        events
    )
    assert (
        client.get(
            f"/api/admin/city-lab/cities/{key}/media",
            params={"path": "../../city.json"},
            headers=headers(admin),
        ).status_code
        == 404
    )


def test_user_update_records_safe_atomic_audit(setup):
    client, session, admin, user, _ = setup
    result = client.patch(
        "/api/admin/users/" + str(user.id),
        json={"is_active": False, "reason": "Support review"},
        headers=headers(admin),
    )
    assert result.status_code == 200
    event = session.exec(select(AdminAuditEvent)).one()
    assert event.before["is_active"] is True and event.after["is_active"] is False
    assert "password_hash" not in event.after


def test_migration_and_archival_rollback_preserve_data():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE users (id TEXT, name TEXT)")
    db.execute("INSERT INTO users VALUES ('legacy', 'Keep me')")
    db.commit()
    root = Path(__file__).resolve().parents[1] / "sql"
    forward = (root / "add_admin_operations.sql").read_text()
    db.executescript(forward)
    db.executescript(forward)
    db.execute(
        "INSERT INTO admin_audit_events VALUES ('id','date','actor','action','place','poi',NULL,'{}','{}','reason')"
    )
    db.commit()
    db.executescript((root / "rollback_admin_operations.sql").read_text())
    assert db.execute("SELECT name FROM users").fetchone()[0] == "Keep me"
    assert (
        db.execute("SELECT reason FROM admin_audit_events_archive").fetchone()[0]
        == "reason"
    )
    db.close()
