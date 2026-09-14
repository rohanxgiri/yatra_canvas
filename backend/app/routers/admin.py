"""Administrative API endpoints for dashboard analytics, moderation, and inspections."""

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, or_
from sqlmodel import Session, col, select

from app.core.auth import require_admin
from app.core.config import Settings, get_settings
from app.database import get_session
from app.models import (
    City,
    Place,
    PlaceOpeningHours,
    PlaceReport,
    PlaceSource,
    PlaceTag,
    Trip,
    TripDay,
    TripItinerary,
    TripPreference,
    User,
    UserRole,
    UserSavedPlace,
)
from app.schemas.admin import (
    AdminDashboardMetrics,
    AdminDestinationCreate,
    AdminDestinationRead,
    AdminDestinationUpdate,
    AdminPlaceDetailRead,
    AdminPlaceRead,
    AdminPlaceUpdate,
    AdminProviderStatus,
    AdminReportRead,
    AdminReportUpdate,
    AdminTripDetailRead,
    AdminTripRead,
    AdminUserRead,
    AdminUserUpdate,
)
from app.services.provider_circuit_breaker import ProviderCircuitBreaker

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/admin",
    tags=["admin"],
    dependencies=[Depends(require_admin)],
)

SessionDependency = Annotated[Session, Depends(get_session)]
SettingsDependency = Annotated[Settings, Depends(get_settings)]
AdminUserDependency = Annotated[User, Depends(require_admin)]


# ---------------------------------------------------------------------------
# 1. Dashboard Overview
# ---------------------------------------------------------------------------


@router.get("/dashboard", response_model=AdminDashboardMetrics)
def get_dashboard_metrics(
    session: SessionDependency,
    settings: SettingsDependency,
) -> AdminDashboardMetrics:
    """Aggregate real database metrics and provider status for dashboard home."""

    total_users = session.exec(select(func.count(User.id))).one()
    total_trips = session.exec(select(func.count(Trip.id))).one()
    total_places = session.exec(select(func.count(Place.id))).one()
    total_destinations = session.exec(select(func.count(City.id))).one()
    active_destinations = session.exec(
        select(func.count(City.id)).where(City.is_enabled == True)  # noqa: E712
    ).one()

    # Moderation breakdown
    status_counts_raw = session.exec(
        select(Place.moderation_status, func.count(Place.id)).group_by(
            Place.moderation_status
        )
    ).all()
    places_by_status = {
        status_name: count for status_name, count in status_counts_raw
    }
    for default_status in ["ACTIVE", "HIDDEN", "RESTRICTED", "DUPLICATE", "INVALID"]:
        places_by_status.setdefault(default_status, 0)

    # Open reports count
    open_reports_count = session.exec(
        select(func.count(PlaceReport.id)).where(
            PlaceReport.status.in_(["OPEN", "REVIEWING"])
        )
    ).one()

    # Recent trips
    recent_trips_rows = session.exec(
        select(Trip, City.name.label("city_name"))
        .join(City, City.id == Trip.city_id, isouter=True)
        .order_by(col(Trip.created_at).desc())
        .limit(8)
    ).all()
    recent_trips = [
        {
            "id": str(trip.id),
            "trip_name": trip.trip_name,
            "city_name": city_name or "Unknown City",
            "days": trip.days,
            "start_date": trip.start_date.isoformat() if trip.start_date else None,
            "created_at": trip.created_at.isoformat() if trip.created_at else None,
        }
        for trip, city_name in recent_trips_rows
    ]

    # Recent reports
    recent_reports_rows = session.exec(
        select(PlaceReport, Place.name.label("place_name"), City.name.label("city_name"))
        .join(Place, Place.id == PlaceReport.place_id, isouter=True)
        .join(City, City.id == Place.city_id, isouter=True)
        .order_by(col(PlaceReport.created_at).desc())
        .limit(8)
    ).all()
    recent_reports = [
        {
            "id": str(report.id),
            "place_name": place_name or "Unknown Place",
            "city_name": city_name or "Unknown City",
            "reason": report.reason,
            "status": report.status,
            "created_at": report.created_at.isoformat() if report.created_at else None,
        }
        for report, place_name, city_name in recent_reports_rows
    ]

    # External provider overview (safe summary)
    audiala_path = Path(settings.audiala_dataset_path) if settings.audiala_dataset_path else None
    provider_health = {
        "overpass": {
            "name": "OpenStreetMap / Overpass",
            "status": "online",
            "circuit_breaker": "closed",
        },
        "geoapify": {
            "name": "Geoapify Geocoding",
            "configured": bool(settings.geoapify_api_key_value),
        },
        "audiala": {
            "name": "Audiala Seed Dataset",
            "available": audiala_path.exists() if audiala_path else False,
        },
        "routing": {
            "name": "OSRM / Route Geometry",
            "provider": settings.routing_provider,
        },
        "weather": {
            "name": "Open-Meteo Weather",
            "provider": settings.weather_provider,
        },
    }

    return AdminDashboardMetrics(
        total_users=total_users,
        total_trips=total_trips,
        total_places=total_places,
        total_destinations=total_destinations,
        active_destinations=active_destinations,
        places_by_status=places_by_status,
        open_reports_count=open_reports_count,
        recent_trips=recent_trips,
        recent_reports=recent_reports,
        provider_health=provider_health,
    )


# ---------------------------------------------------------------------------
# 2. User Management
# ---------------------------------------------------------------------------


@router.get("/users", response_model=list[AdminUserRead])
def list_admin_users(
    session: SessionDependency,
    q: Annotated[str | None, Query(description="Search by name or email")] = None,
    role: Annotated[str | None, Query(description="Filter by role")] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[AdminUserRead]:
    """List users with trip count, role, and pagination."""

    statement = select(User)
    if q:
        search_filter = f"%{q.strip().lower()}%"
        statement = statement.where(
            or_(
                func.lower(User.name).like(search_filter),
                func.lower(User.email).like(search_filter),
            )
        )
    if role:
        statement = statement.where(User.role == role.upper())

    users = list(
        session.exec(
            statement.order_by(col(User.created_at).desc()).offset(offset).limit(limit)
        ).all()
    )

    if not users:
        return []

    user_ids = [u.id for u in users]
    trip_counts = dict(
        session.exec(
            select(Trip.user_id, func.count(Trip.id))
            .where(Trip.user_id.in_(user_ids))
            .group_by(Trip.user_id)
        ).all()
    )

    return [
        AdminUserRead(
            id=user.id,
            name=user.name,
            email=user.email,
            role=user.role,
            is_active=user.is_active,
            created_at=user.created_at,
            trip_count=trip_counts.get(user.id, 0),
        )
        for user in users
    ]


@router.get("/users/{user_id}", response_model=AdminUserRead)
def get_admin_user(
    user_id: UUID,
    session: SessionDependency,
) -> AdminUserRead:
    """Get single user profile with trip count."""

    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    trip_count = session.exec(
        select(func.count(Trip.id)).where(Trip.user_id == user_id)
    ).one()

    return AdminUserRead(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
        trip_count=trip_count,
    )


@router.patch("/users/{user_id}", response_model=AdminUserRead)
def update_admin_user(
    user_id: UUID,
    update_data: AdminUserUpdate,
    session: SessionDependency,
    current_admin: AdminUserDependency,
) -> AdminUserRead:
    """Update user active status or role with self-deactivation guard."""

    user = session.get(User, user_id)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found.",
        )

    # Protect against self-deactivation or self-demotion
    if user.id == current_admin.id:
        if update_data.is_active is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Administrators cannot deactivate their own account.",
            )
        if update_data.role is not None and update_data.role != UserRole.ADMIN.value:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Administrators cannot demote their own account role.",
            )

    if update_data.name is not None:
        user.name = update_data.name.strip()
    if update_data.is_active is not None:
        user.is_active = update_data.is_active
    if update_data.role is not None:
        normalized_role = update_data.role.upper()
        if normalized_role not in (UserRole.USER.value, UserRole.ADMIN.value):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid role. Must be 'USER' or 'ADMIN'.",
            )
        user.role = normalized_role

    user.updated_at = datetime.now(timezone.utc)
    session.add(user)
    session.commit()
    session.refresh(user)

    logger.info(
        "Admin %s updated user %s (is_active=%s, role=%s)",
        current_admin.email,
        user.id,
        user.is_active,
        user.role,
    )

    trip_count = session.exec(
        select(func.count(Trip.id)).where(Trip.user_id == user_id)
    ).one()

    return AdminUserRead(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
        trip_count=trip_count,
    )


# ---------------------------------------------------------------------------
# 3. Destination Management
# ---------------------------------------------------------------------------


@router.get("/destinations", response_model=list[AdminDestinationRead])
def list_admin_destinations(
    session: SessionDependency,
    q: Annotated[str | None, Query(description="Search by city name")] = None,
    is_enabled: Annotated[bool | None, Query()] = None,
    is_featured: Annotated[bool | None, Query()] = None,
    is_popular: Annotated[bool | None, Query()] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=300)] = 100,
) -> list[AdminDestinationRead]:
    """List destinations with status flags, place counts, and trip counts."""

    statement = select(City)
    if q:
        statement = statement.where(func.lower(City.name).like(f"%{q.strip().lower()}%"))
    if is_enabled is not None:
        statement = statement.where(City.is_enabled == is_enabled)
    if is_featured is not None:
        statement = statement.where(City.is_featured == is_featured)
    if is_popular is not None:
        statement = statement.where(City.is_popular == is_popular)

    destinations = list(
        session.exec(
            statement.order_by(City.display_order.desc(), City.name)
            .offset(offset)
            .limit(limit)
        ).all()
    )

    if not destinations:
        return []

    city_ids = [d.id for d in destinations]
    place_counts = dict(
        session.exec(
            select(Place.city_id, func.count(Place.id))
            .where(Place.city_id.in_(city_ids))
            .group_by(Place.city_id)
        ).all()
    )
    trip_counts = dict(
        session.exec(
            select(Trip.city_id, func.count(Trip.id))
            .where(Trip.city_id.in_(city_ids))
            .group_by(Trip.city_id)
        ).all()
    )

    return [
        AdminDestinationRead(
            id=dest.id,
            name=dest.name,
            state=dest.state,
            country=dest.country,
            latitude=dest.latitude,
            longitude=dest.longitude,
            google_place_id=dest.google_place_id,
            is_enabled=dest.is_enabled,
            is_featured=dest.is_featured,
            is_popular=dest.is_popular,
            image_url=dest.image_url,
            description=dest.description,
            display_order=dest.display_order,
            places_count=place_counts.get(dest.id, 0),
            trips_count=trip_counts.get(dest.id, 0),
        )
        for dest in destinations
    ]


@router.post("/destinations", response_model=AdminDestinationRead, status_code=status.HTTP_201_CREATED)
def create_admin_destination(
    payload: AdminDestinationCreate,
    session: SessionDependency,
    current_admin: AdminUserDependency,
) -> AdminDestinationRead:
    """Create a new destination/city."""

    city = City(
        name=payload.name.strip(),
        state=payload.state.strip() if payload.state else None,
        country=payload.country.strip(),
        latitude=payload.latitude,
        longitude=payload.longitude,
        is_enabled=payload.is_enabled,
        is_featured=payload.is_featured,
        is_popular=payload.is_popular,
        image_url=payload.image_url.strip() if payload.image_url else None,
        description=payload.description.strip() if payload.description else None,
        display_order=payload.display_order,
        created_at=datetime.now(timezone.utc),
    )
    session.add(city)
    session.commit()
    session.refresh(city)

    logger.info("Admin %s created destination %s (%s)", current_admin.email, city.name, city.id)

    return AdminDestinationRead(
        id=city.id,
        name=city.name,
        state=city.state,
        country=city.country,
        latitude=city.latitude,
        longitude=city.longitude,
        google_place_id=city.google_place_id,
        is_enabled=city.is_enabled,
        is_featured=city.is_featured,
        is_popular=city.is_popular,
        image_url=city.image_url,
        description=city.description,
        display_order=city.display_order,
        places_count=0,
        trips_count=0,
    )


@router.get("/destinations/{destination_id}", response_model=AdminDestinationRead)
def get_admin_destination(
    destination_id: UUID,
    session: SessionDependency,
) -> AdminDestinationRead:
    """Get single destination details."""

    city = session.get(City, destination_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Destination not found.",
        )

    places_count = session.exec(
        select(func.count(Place.id)).where(Place.city_id == destination_id)
    ).one()
    trips_count = session.exec(
        select(func.count(Trip.id)).where(Trip.city_id == destination_id)
    ).one()

    return AdminDestinationRead(
        id=city.id,
        name=city.name,
        state=city.state,
        country=city.country,
        latitude=city.latitude,
        longitude=city.longitude,
        google_place_id=city.google_place_id,
        is_enabled=city.is_enabled,
        is_featured=city.is_featured,
        is_popular=city.is_popular,
        image_url=city.image_url,
        description=city.description,
        display_order=city.display_order,
        places_count=places_count,
        trips_count=trips_count,
    )


@router.patch("/destinations/{destination_id}", response_model=AdminDestinationRead)
def update_admin_destination(
    destination_id: UUID,
    update_data: AdminDestinationUpdate,
    session: SessionDependency,
    current_admin: AdminUserDependency,
) -> AdminDestinationRead:
    """Update destination flags, description, image, or order."""

    city = session.get(City, destination_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Destination not found.",
        )

    if update_data.name is not None:
        city.name = update_data.name.strip()
    if update_data.state is not None:
        city.state = update_data.state.strip()
    if update_data.country is not None:
        city.country = update_data.country.strip()
    if update_data.latitude is not None:
        city.latitude = update_data.latitude
    if update_data.longitude is not None:
        city.longitude = update_data.longitude
    if update_data.is_enabled is not None:
        city.is_enabled = update_data.is_enabled
    if update_data.is_featured is not None:
        city.is_featured = update_data.is_featured
    if update_data.is_popular is not None:
        city.is_popular = update_data.is_popular
    if update_data.image_url is not None:
        city.image_url = update_data.image_url.strip() if update_data.image_url else None
    if update_data.description is not None:
        city.description = update_data.description.strip() if update_data.description else None
    if update_data.display_order is not None:
        city.display_order = update_data.display_order

    session.add(city)
    session.commit()
    session.refresh(city)

    logger.info("Admin %s updated destination %s (%s)", current_admin.email, city.name, city.id)

    places_count = session.exec(
        select(func.count(Place.id)).where(Place.city_id == destination_id)
    ).one()
    trips_count = session.exec(
        select(func.count(Trip.id)).where(Trip.city_id == destination_id)
    ).one()

    return AdminDestinationRead(
        id=city.id,
        name=city.name,
        state=city.state,
        country=city.country,
        latitude=city.latitude,
        longitude=city.longitude,
        google_place_id=city.google_place_id,
        is_enabled=city.is_enabled,
        is_featured=city.is_featured,
        is_popular=city.is_popular,
        image_url=city.image_url,
        description=city.description,
        display_order=city.display_order,
        places_count=places_count,
        trips_count=trips_count,
    )


# ---------------------------------------------------------------------------
# 4. Places & POI Moderation Management
# ---------------------------------------------------------------------------


@router.get("/places", response_model=list[AdminPlaceRead])
def list_admin_places(
    session: SessionDependency,
    city_id: Annotated[UUID | None, Query(description="Filter by city")] = None,
    category: Annotated[str | None, Query(description="Filter by category")] = None,
    moderation_status: Annotated[str | None, Query(description="Filter by status")] = None,
    q: Annotated[str | None, Query(description="Search by place name")] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[AdminPlaceRead]:
    """List places with moderation status, source count, and report count."""

    statement = select(Place, City.name.label("city_name")).join(
        City, City.id == Place.city_id, isouter=True
    )

    if city_id:
        statement = statement.where(Place.city_id == city_id)
    if category:
        statement = statement.where(Place.category == category.lower())
    if moderation_status:
        statement = statement.where(Place.moderation_status == moderation_status.upper())
    if q:
        statement = statement.where(func.lower(Place.name).like(f"%{q.strip().lower()}%"))

    rows = list(
        session.exec(
            statement.order_by(col(Place.created_at).desc(), Place.name)
            .offset(offset)
            .limit(limit)
        ).all()
    )

    if not rows:
        return []

    place_ids = [place.id for place, _ in rows]
    sources_counts = dict(
        session.exec(
            select(PlaceSource.place_id, func.count(PlaceSource.id))
            .where(PlaceSource.place_id.in_(place_ids))
            .group_by(PlaceSource.place_id)
        ).all()
    )
    reports_counts = dict(
        session.exec(
            select(PlaceReport.place_id, func.count(PlaceReport.id))
            .where(PlaceReport.place_id.in_(place_ids))
            .group_by(PlaceReport.place_id)
        ).all()
    )

    return [
        AdminPlaceRead(
            id=place.id,
            city_id=place.city_id,
            city_name=city_name,
            name=place.name,
            category=place.category,
            latitude=place.latitude,
            longitude=place.longitude,
            rating=place.rating,
            review_count=place.review_count,
            is_popular=place.is_popular,
            is_heritage=place.is_heritage,
            is_local_speciality=place.is_local_speciality,
            wikidata_id=place.wikidata_id,
            importance_score=place.importance_score,
            opening_hours_status=place.opening_hours_status,
            raw_opening_hours=place.raw_opening_hours,
            moderation_status=place.moderation_status,
            sources_count=sources_counts.get(place.id, 0),
            reports_count=reports_counts.get(place.id, 0),
        )
        for place, city_name in rows
    ]


@router.get("/places/{place_id}", response_model=AdminPlaceDetailRead)
def get_admin_place_details(
    place_id: UUID,
    session: SessionDependency,
) -> AdminPlaceDetailRead:
    """Get full details of a place including sources, opening hours, tags, and reports."""

    place = session.get(Place, place_id)
    if place is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Place not found.",
        )

    city = session.get(City, place.city_id)
    sources = session.exec(select(PlaceSource).where(PlaceSource.place_id == place_id)).all()
    hours = session.exec(
        select(PlaceOpeningHours)
        .where(PlaceOpeningHours.place_id == place_id)
        .order_by(PlaceOpeningHours.day_of_week)
    ).all()
    tags = session.exec(select(PlaceTag.tag).where(PlaceTag.place_id == place_id)).all()
    reports = session.exec(
        select(PlaceReport)
        .where(PlaceReport.place_id == place_id)
        .order_by(col(PlaceReport.created_at).desc())
    ).all()

    return AdminPlaceDetailRead(
        id=place.id,
        city_id=place.city_id,
        city_name=city.name if city else None,
        name=place.name,
        category=place.category,
        latitude=place.latitude,
        longitude=place.longitude,
        rating=place.rating,
        review_count=place.review_count,
        is_popular=place.is_popular,
        is_heritage=place.is_heritage,
        is_local_speciality=place.is_local_speciality,
        wikidata_id=place.wikidata_id,
        importance_score=place.importance_score,
        opening_hours_status=place.opening_hours_status,
        raw_opening_hours=place.raw_opening_hours,
        moderation_status=place.moderation_status,
        sources_count=len(sources),
        reports_count=len(reports),
        sources=[
            {
                "id": str(s.id),
                "source": s.source,
                "external_place_id": s.external_place_id,
                "wikidata_id": s.wikidata_id,
                "source_url": s.source_url,
                "licence_identifier": s.licence_identifier,
                "address": s.address,
                "website": s.website,
                "telephone": s.telephone,
                "raw_opening_hours": s.raw_opening_hours,
                "imported_at": s.imported_at.isoformat() if s.imported_at else None,
            }
            for s in sources
        ],
        opening_hours=[
            {
                "day_of_week": h.day_of_week,
                "status": h.status,
                "intervals": h.intervals,
            }
            for h in hours
        ],
        tags=list(tags),
        reports=[
            {
                "id": str(r.id),
                "reason": r.reason,
                "details": r.details,
                "status": r.status,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in reports
        ],
    )


@router.patch("/places/{place_id}", response_model=AdminPlaceRead)
def update_admin_place_moderation(
    place_id: UUID,
    update_data: AdminPlaceUpdate,
    session: SessionDependency,
    current_admin: AdminUserDependency,
) -> AdminPlaceRead:
    """Update place moderation status or quality flags."""

    place = session.get(Place, place_id)
    if place is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Place not found.",
        )

    if update_data.moderation_status is not None:
        old_status = place.moderation_status
        place.moderation_status = update_data.moderation_status
        logger.info(
            "Admin %s updated place '%s' (%s) moderation_status from %s to %s",
            current_admin.email,
            place.name,
            place.id,
            old_status,
            place.moderation_status,
        )

    if update_data.is_popular is not None:
        place.is_popular = update_data.is_popular
    if update_data.is_heritage is not None:
        place.is_heritage = update_data.is_heritage
    if update_data.is_local_speciality is not None:
        place.is_local_speciality = update_data.is_local_speciality

    session.add(place)
    session.commit()
    session.refresh(place)

    city = session.get(City, place.city_id)
    sources_count = session.exec(
        select(func.count(PlaceSource.id)).where(PlaceSource.place_id == place_id)
    ).one()
    reports_count = session.exec(
        select(func.count(PlaceReport.id)).where(PlaceReport.place_id == place_id)
    ).one()

    return AdminPlaceRead(
        id=place.id,
        city_id=place.city_id,
        city_name=city.name if city else None,
        name=place.name,
        category=place.category,
        latitude=place.latitude,
        longitude=place.longitude,
        rating=place.rating,
        review_count=place.review_count,
        is_popular=place.is_popular,
        is_heritage=place.is_heritage,
        is_local_speciality=place.is_local_speciality,
        wikidata_id=place.wikidata_id,
        importance_score=place.importance_score,
        opening_hours_status=place.opening_hours_status,
        raw_opening_hours=place.raw_opening_hours,
        moderation_status=place.moderation_status,
        sources_count=sources_count,
        reports_count=reports_count,
    )


# ---------------------------------------------------------------------------
# 5. Trip Inspector (Read-only for debugging)
# ---------------------------------------------------------------------------


@router.get("/trips", response_model=list[AdminTripRead])
def list_admin_trips(
    session: SessionDependency,
    city_id: Annotated[UUID | None, Query(description="Filter by destination city")] = None,
    q: Annotated[str | None, Query(description="Search by trip name")] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[AdminTripRead]:
    """List traveller trips with destination, stop counts, and date ranges."""

    statement = select(Trip, City.name.label("city_name"), User.name.label("user_name")).join(
        City, City.id == Trip.city_id, isouter=True
    ).join(
        User, User.id == Trip.user_id, isouter=True
    )

    if city_id:
        statement = statement.where(Trip.city_id == city_id)
    if q:
        statement = statement.where(func.lower(Trip.trip_name).like(f"%{q.strip().lower()}%"))

    rows = list(
        session.exec(
            statement.order_by(col(Trip.created_at).desc()).offset(offset).limit(limit)
        ).all()
    )

    if not rows:
        return []

    trip_ids = [trip.id for trip, _, _ in rows]
    saved_counts = dict(
        session.exec(
            select(UserSavedPlace.trip_id, func.count(UserSavedPlace.id))
            .where(UserSavedPlace.trip_id.in_(trip_ids))
            .group_by(UserSavedPlace.trip_id)
        ).all()
    )
    itinerary_counts = dict(
        session.exec(
            select(TripItinerary.trip_id, func.count(TripItinerary.id))
            .where(TripItinerary.trip_id.in_(trip_ids))
            .group_by(TripItinerary.trip_id)
        ).all()
    )

    return [
        AdminTripRead(
            id=trip.id,
            user_id=trip.user_id,
            user_name=user_name,
            city_id=trip.city_id,
            city_name=city_name,
            trip_name=trip.trip_name,
            days=trip.days,
            start_date=trip.start_date,
            arrival_place=trip.arrival_place,
            start_location_type=trip.start_location_type,
            start_location_name=trip.start_location_name,
            saved_places_count=saved_counts.get(trip.id, 0),
            itinerary_stops_count=itinerary_counts.get(trip.id, 0),
            created_at=trip.created_at,
        )
        for trip, city_name, user_name in rows
    ]


@router.get("/trips/{trip_id}", response_model=AdminTripDetailRead)
def get_admin_trip_details(
    trip_id: UUID,
    session: SessionDependency,
) -> AdminTripDetailRead:
    """Read-only inspection of a trip, its days, preferences, places, and itinerary."""

    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Trip not found.",
        )

    city = session.get(City, trip.city_id)
    user = session.get(User, trip.user_id)

    days = session.exec(
        select(TripDay).where(TripDay.trip_id == trip_id).order_by(TripDay.day_number)
    ).all()
    preferences = session.exec(
        select(TripPreference).where(TripPreference.trip_id == trip_id)
    ).all()

    # User saved places with place details
    saved_rows = session.exec(
        select(UserSavedPlace, Place.name.label("place_name"), Place.category.label("category"))
        .join(Place, Place.id == UserSavedPlace.place_id, isouter=True)
        .where(UserSavedPlace.trip_id == trip_id)
        .order_by(UserSavedPlace.custom_order)
    ).all()

    # Itinerary stops with place details
    itinerary_rows = session.exec(
        select(TripItinerary, Place.name.label("place_name"), Place.category.label("category"))
        .join(Place, Place.id == TripItinerary.place_id, isouter=True)
        .where(TripItinerary.trip_id == trip_id)
        .order_by(TripItinerary.day_number, TripItinerary.visit_order)
    ).all()

    return AdminTripDetailRead(
        id=trip.id,
        user_id=trip.user_id,
        user_name=user.name if user else None,
        city_id=trip.city_id,
        city_name=city.name if city else None,
        trip_name=trip.trip_name,
        days=trip.days,
        start_date=trip.start_date,
        arrival_place=trip.arrival_place,
        start_location_type=trip.start_location_type,
        start_location_name=trip.start_location_name,
        saved_places_count=len(saved_rows),
        itinerary_stops_count=len(itinerary_rows),
        created_at=trip.created_at,
        trip_days=[
            {
                "day_number": d.day_number,
                "date": d.date.isoformat(),
                "day_type": d.day_type,
                "start_time": d.start_time.isoformat() if d.start_time else None,
                "end_time": d.end_time.isoformat() if d.end_time else None,
            }
            for d in days
        ],
        preferences=[
            {
                "preference": p.preference,
                "weight": p.weight,
            }
            for p in preferences
        ],
        saved_places=[
            {
                "place_id": str(sp.place_id),
                "place_name": place_name,
                "category": category,
                "priority": sp.priority,
                "is_locked": sp.is_locked,
                "must_visit": sp.must_visit,
                "assignment_mode": sp.assignment_mode,
                "notes": sp.notes,
            }
            for sp, place_name, category in saved_rows
        ],
        itinerary=[
            {
                "day_number": it.day_number,
                "visit_order": it.visit_order,
                "place_id": str(it.place_id),
                "place_name": place_name,
                "category": category,
                "planned_arrival_time": it.planned_arrival_time.isoformat() if it.planned_arrival_time else None,
                "planned_departure_time": it.planned_departure_time.isoformat() if it.planned_departure_time else None,
                "status": it.status,
            }
            for it, place_name, category in itinerary_rows
        ],
    )


# ---------------------------------------------------------------------------
# 6. Place Reports Management
# ---------------------------------------------------------------------------


@router.get("/reports", response_model=list[AdminReportRead])
def list_admin_reports(
    session: SessionDependency,
    status_filter: Annotated[str | None, Query(alias="status")] = None,
    reason: Annotated[str | None, Query()] = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> list[AdminReportRead]:
    """List place reports submitted by users or reviewers."""

    statement = select(
        PlaceReport, Place.name.label("place_name"), City.name.label("city_name")
    ).join(Place, Place.id == PlaceReport.place_id, isouter=True).join(
        City, City.id == Place.city_id, isouter=True
    )

    if status_filter:
        statement = statement.where(PlaceReport.status == status_filter.upper())
    if reason:
        statement = statement.where(PlaceReport.reason == reason)

    rows = list(
        session.exec(
            statement.order_by(col(PlaceReport.created_at).desc()).offset(offset).limit(limit)
        ).all()
    )

    return [
        AdminReportRead(
            id=report.id,
            place_id=report.place_id,
            place_name=place_name,
            city_name=city_name,
            user_id=report.user_id,
            reason=report.reason,
            details=report.details,
            status=report.status,
            admin_notes=report.admin_notes,
            created_at=report.created_at,
            updated_at=report.updated_at,
        )
        for report, place_name, city_name in rows
    ]


@router.patch("/reports/{report_id}", response_model=AdminReportRead)
def update_admin_report(
    report_id: UUID,
    update_data: AdminReportUpdate,
    session: SessionDependency,
    current_admin: AdminUserDependency,
) -> AdminReportRead:
    """Update report review status (OPEN, REVIEWING, RESOLVED, REJECTED) and admin notes."""

    report = session.get(PlaceReport, report_id)
    if report is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Report not found.",
        )

    if update_data.status is not None:
        report.status = update_data.status
    if update_data.admin_notes is not None:
        report.admin_notes = update_data.admin_notes.strip()

    report.updated_at = datetime.now(timezone.utc)
    session.add(report)
    session.commit()
    session.refresh(report)

    logger.info(
        "Admin %s updated report %s status to %s",
        current_admin.email,
        report.id,
        report.status,
    )

    place = session.get(Place, report.place_id)
    city = session.get(City, place.city_id) if place else None

    return AdminReportRead(
        id=report.id,
        place_id=report.place_id,
        place_name=place.name if place else None,
        city_name=city.name if city else None,
        user_id=report.user_id,
        reason=report.reason,
        details=report.details,
        status=report.status,
        admin_notes=report.admin_notes,
        created_at=report.created_at,
        updated_at=report.updated_at,
    )


# ---------------------------------------------------------------------------
# 7. Provider Status & System Diagnostics
# ---------------------------------------------------------------------------


@router.get("/provider-status", response_model=AdminProviderStatus)
def get_admin_provider_status(
    settings: SettingsDependency,
) -> AdminProviderStatus:
    """Inspect data source providers, circuit breakers, and configuration without leaking secrets."""

    audiala_path = Path(settings.audiala_dataset_path) if settings.audiala_dataset_path else None

    providers = {
        "overpass": {
            "name": "OpenStreetMap / Overpass",
            "endpoint": settings.overpass_api_url,
            "timeout_seconds": settings.overpass_timeout_seconds,
            "circuit_breaker_threshold": settings.overpass_circuit_breaker_threshold,
            "circuit_breaker_cooldown_seconds": settings.overpass_circuit_breaker_cooldown_seconds,
            "status": "active",
        },
        "geoapify": {
            "name": "Geoapify Geocoding & Autocomplete",
            "endpoint": settings.geoapify_base_url,
            "configured": bool(settings.geoapify_api_key_value),
            "timeout_seconds": settings.geoapify_timeout_seconds,
            "cache_ttl_seconds": settings.geoapify_autocomplete_cache_ttl_seconds,
        },
        "audiala": {
            "name": "Audiala Dataset Seed",
            "path_configured": settings.audiala_dataset_path,
            "file_exists": audiala_path.exists() if audiala_path else False,
        },
        "routing": {
            "name": "Road Geometry Routing",
            "provider": settings.routing_provider,
            "osrm_endpoint": settings.osrm_router_url,
            "ors_configured": bool(settings.openrouteservice_api_key_value),
        },
        "weather": {
            "name": "Weather Advisories",
            "provider": settings.weather_provider,
            "endpoint": settings.open_meteo_base_url,
            "cache_ttl_minutes": settings.weather_cache_ttl_minutes,
        },
    }

    return AdminProviderStatus(providers=providers)
