"""Comprehensive tests for admin authentication, authorization, and operations."""

from collections.abc import Generator
from datetime import datetime, timezone
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.engine import Engine
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.core.security import create_access_token, hash_password
from app.database import get_session
from app.main import app
from app.models import City, Place, PlaceReport, Trip, User, UserRole
from app.scripts.create_admin import create_or_update_admin


@pytest.fixture
def test_setup() -> Generator[tuple[TestClient, Session, User, User], None, None]:
    """Provide isolated in-memory test database, test client, and seeded users."""

    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    # Seed Admin User
    admin_user = User(
        id=uuid4(),
        name="Admin User",
        email="admin@yatracanvas.com",
        password_hash=hash_password("AdminSecurePassword123!"),
        role=UserRole.ADMIN.value,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )

    # Seed Normal User
    normal_user = User(
        id=uuid4(),
        name="Normal Traveler",
        email="traveler@example.com",
        password_hash=hash_password("TravelerPassword123!"),
        role=UserRole.USER.value,
        is_active=True,
        created_at=datetime.now(timezone.utc),
    )

    # Seed Deactivated User
    inactive_user = User(
        id=uuid4(),
        name="Disabled User",
        email="disabled@example.com",
        password_hash=hash_password("DisabledPassword123!"),
        role=UserRole.USER.value,
        is_active=False,
        created_at=datetime.now(timezone.utc),
    )

    # Seed City and Places
    city = City(
        id=uuid4(),
        name="Jaipur",
        state="Rajasthan",
        country="India",
        latitude=26.9124,
        longitude=75.7873,
        is_enabled=True,
        is_featured=True,
    )

    place1 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Hawa Mahal",
        category="heritage",
        latitude=26.9239,
        longitude=75.8267,
        moderation_status="ACTIVE",
    )
    place2 = Place(
        id=uuid4(),
        city_id=city.id,
        name="Private Canteen Facility",
        category="food",
        latitude=26.9200,
        longitude=75.8200,
        moderation_status="HIDDEN",
    )

    # Seed Report
    report = PlaceReport(
        id=uuid4(),
        place_id=place2.id,
        user_id=normal_user.id,
        reason="restricted_facility",
        details="Student canteen with campus ID requirement.",
        status="OPEN",
        created_at=datetime.now(timezone.utc),
    )

    with Session(engine, expire_on_commit=False) as seed_session:
        seed_session.add(admin_user)
        seed_session.add(normal_user)
        seed_session.add(inactive_user)
        seed_session.add(city)
        seed_session.add(place1)
        seed_session.add(place2)
        seed_session.add(report)
        seed_session.commit()

    def override_session() -> Generator[Session, None, None]:
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    client = TestClient(app)

    with Session(engine, expire_on_commit=False) as session:
        yield client, session, admin_user, normal_user

    client.close()
    app.dependency_overrides.clear()
    SQLModel.metadata.drop_all(engine)


def test_admin_login_success(test_setup):
    client, _, admin_user, _ = test_setup

    response = client.post(
        "/api/auth/login",
        json={"email": "admin@yatracanvas.com", "password": "AdminSecurePassword123!"},
    )
    assert response.status_code == 200
    data = response.json()
    assert "access_token" in data
    assert data["token_type"] == "bearer"
    assert data["user"]["email"] == "admin@yatracanvas.com"
    assert data["user"]["role"] == "ADMIN"


def test_admin_login_invalid_password(test_setup):
    client, _, _, _ = test_setup

    response = client.post(
        "/api/auth/login",
        json={"email": "admin@yatracanvas.com", "password": "WrongPassword!"},
    )
    assert response.status_code == 401
    assert "Invalid email or password" in response.json()["detail"]


def test_normal_user_login(test_setup):
    client, _, _, normal_user = test_setup

    response = client.post(
        "/api/auth/login",
        json={"email": "traveler@example.com", "password": "TravelerPassword123!"},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["user"]["role"] == "USER"


def test_inactive_user_login(test_setup):
    client, _, _, _ = test_setup

    response = client.post(
        "/api/auth/login",
        json={"email": "disabled@example.com", "password": "DisabledPassword123!"},
    )
    assert response.status_code == 403
    assert "deactivated" in response.json()["detail"]


def test_get_current_user_me(test_setup):
    client, _, admin_user, _ = test_setup

    # Unauthenticated
    resp_anon = client.get("/api/auth/me")
    assert resp_anon.status_code == 401

    # Authenticated
    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})
    resp_auth = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert resp_auth.status_code == 200
    assert resp_auth.json()["email"] == admin_user.email


def test_admin_route_unauthenticated_returns_401(test_setup):
    client, _, _, _ = test_setup

    response = client.get("/api/admin/dashboard")
    assert response.status_code == 401


def test_admin_route_forbidden_for_user_returns_403(test_setup):
    client, _, _, normal_user = test_setup

    token = create_access_token({"sub": str(normal_user.id), "email": normal_user.email, "role": normal_user.role})
    response = client.get("/api/admin/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403
    assert "Administrator access required" in response.json()["detail"]


def test_admin_dashboard_metrics(test_setup):
    client, _, admin_user, _ = test_setup

    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})
    response = client.get("/api/admin/dashboard", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    data = response.json()
    assert data["total_users"] == 3
    assert data["total_places"] == 2
    assert data["total_destinations"] == 1
    assert data["open_reports_count"] == 1
    assert data["places_by_status"]["ACTIVE"] == 1
    assert data["places_by_status"]["HIDDEN"] == 1


def test_admin_user_management(test_setup):
    client, _, admin_user, normal_user = test_setup

    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    # List users
    resp = client.get("/api/admin/users", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    users = resp.json()
    assert len(users) == 3

    # Toggle traveler active status
    patch_resp = client.patch(
        f"/api/admin/users/{normal_user.id}",
        json={"is_active": False},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["is_active"] is False


def test_admin_self_deactivation_guarded(test_setup):
    client, _, admin_user, _ = test_setup

    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    # Admin cannot deactivate self
    resp = client.patch(
        f"/api/admin/users/{admin_user.id}",
        json={"is_active": False},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 400
    assert "cannot deactivate their own account" in resp.json()["detail"]

    # Admin cannot demote self
    resp_demote = client.patch(
        f"/api/admin/users/{admin_user.id}",
        json={"role": "USER"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp_demote.status_code == 400
    assert "cannot demote their own account" in resp_demote.json()["detail"]


def test_admin_destination_management(test_setup):
    client, _, admin_user, _ = test_setup
    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    # List destinations
    resp = client.get("/api/admin/destinations", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    destinations = resp.json()
    assert len(destinations) >= 1

    # Create new destination
    create_resp = client.post(
        "/api/admin/destinations",
        json={
            "name": "Udaipur",
            "state": "Rajasthan",
            "country": "India",
            "latitude": 24.5854,
            "longitude": 73.7125,
            "is_enabled": True,
            "is_featured": True,
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert create_resp.status_code == 201
    new_dest = create_resp.json()
    assert new_dest["name"] == "Udaipur"

    # Patch destination
    patch_resp = client.patch(
        f"/api/admin/destinations/{new_dest['id']}",
        json={"is_popular": True, "display_order": 10},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["is_popular"] is True
    assert patch_resp.json()["display_order"] == 10


def test_admin_place_moderation(test_setup):
    client, session, admin_user, _ = test_setup
    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    # Find active place
    place = session.exec(select(Place).where(Place.name == "Hawa Mahal")).one()
    assert place.moderation_status == "ACTIVE"

    # Moderate place to HIDDEN
    patch_resp = client.patch(
        f"/api/admin/places/{place.id}",
        json={"moderation_status": "HIDDEN"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["moderation_status"] == "HIDDEN"

    # Verify place search excludes HIDDEN place
    search_resp = client.get(f"/cities/{place.city_id}/places/search?query=Hawa")
    assert search_resp.status_code == 200
    results = search_resp.json()
    assert not any(r["name"] == "Hawa Mahal" for r in results)


def test_admin_reports_management(test_setup):
    client, session, admin_user, _ = test_setup
    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    # List reports
    resp = client.get("/api/admin/reports", headers={"Authorization": f"Bearer {token}"})
    assert resp.status_code == 200
    reports = resp.json()
    assert len(reports) == 1
    report_id = reports[0]["id"]

    # Triage report
    patch_resp = client.patch(
        f"/api/admin/reports/{report_id}",
        json={"status": "RESOLVED", "admin_notes": "Facility verified as private and hidden."},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert patch_resp.status_code == 200
    assert patch_resp.json()["status"] == "RESOLVED"
    assert "Facility verified" in patch_resp.json()["admin_notes"]


def test_admin_provider_status(test_setup):
    client, _, admin_user, _ = test_setup
    token = create_access_token({"sub": str(admin_user.id), "email": admin_user.email, "role": admin_user.role})

    response = client.get("/api/admin/provider-status", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    data = response.json()
    assert "providers" in data
    assert "overpass" in data["providers"]
    assert "geoapify" in data["providers"]
    # Ensure no secret keys are in output
    text_data = str(data)
    assert "GEOAPIFY_API_KEY" not in text_data
    assert "secret" not in text_data.lower()


def test_create_admin_script_idempotent(monkeypatch):
    test_engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(test_engine)
    monkeypatch.setattr("app.scripts.create_admin.get_engine", lambda: test_engine)
    monkeypatch.setattr("app.database.get_engine", lambda: test_engine)

    # Initial creation
    res1 = create_or_update_admin(
        email="admin@yatracanvas.com",
        password="SuperAdminSecretPassword123!",
    )
    assert res1 is True

    with Session(test_engine) as s:
        u = s.exec(select(User).where(User.email == "admin@yatracanvas.com")).one()
        assert u.role == "ADMIN"
        assert u.is_active is True

    # Idempotent re-run without update
    res2 = create_or_update_admin(
        email="admin@yatracanvas.com",
        password="SuperAdminSecretPassword123!",
    )
    assert res2 is True

    # Re-run with password update
    res3 = create_or_update_admin(
        email="admin@yatracanvas.com",
        password="NewAdminPassword456!",
        update_password_if_exists=True,
    )
    assert res3 is True

    test_engine.dispose()
