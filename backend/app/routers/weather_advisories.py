"""API routes for Weather-Aware Trip Assistance."""

import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlmodel import Session, select

from app.database import get_session
from app.models.entities import Trip, TripPreference
from app.schemas.weather_advisory import (
    ApplyRearrangementRequest,
    DayRearrangePreviewRead,
    PlaceAlternativeRead,
    RearrangePreviewRequest,
    TripWeatherAdvisoriesRead,
)
from app.services.weather_advisory_service import WeatherAdvisoryService
from app.services.weather_alternative_service import WeatherAlternativeService
from app.services.weather_service import OpenMeteoWeatherProvider, WeatherProvider

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/trips/{trip_id}", tags=["weather-advisories"])


def get_weather_provider() -> WeatherProvider:
    """Dependency injector for WeatherProvider."""
    return OpenMeteoWeatherProvider()


@router.get(
    "/weather-advisories",
    response_model=TripWeatherAdvisoriesRead,
    summary="Get weather advisories affecting the trip itinerary",
)
async def get_weather_advisories(
    trip_id: UUID,
    session: Session = Depends(get_session),
    provider: WeatherProvider = Depends(get_weather_provider),
) -> TripWeatherAdvisoriesRead:
    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip {trip_id} not found.",
        )

    try:
        service = WeatherAdvisoryService(weather_provider=provider)
        return await service.get_trip_advisories(session, trip_id)
    except Exception as exc:
        logger.error("Weather advisory evaluation failed for trip %s: %s", trip_id, exc)
        # Safe degradation: return weather_unavailable without crashing the trip workflow
        return TripWeatherAdvisoriesRead(
            trip_id=trip_id,
            status="weather_unavailable",
            advisories=[],
        )


@router.get(
    "/weather-alternatives",
    response_model=list[PlaceAlternativeRead],
    summary="Suggest sheltered weather-friendly alternatives matching user interests",
)
def get_weather_alternatives(
    trip_id: UUID,
    day_number: int = Query(ge=1, default=1),
    condition: str = Query(default="hot"),
    session: Session = Depends(get_session),
) -> list[PlaceAlternativeRead]:
    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip {trip_id} not found.",
        )

    service = WeatherAlternativeService()
    return service.suggest_alternatives(
        session=session,
        trip_id=trip_id,
        day_number=day_number,
        condition=condition,
    )


@router.post(
    "/rearrange-preview",
    response_model=DayRearrangePreviewRead,
    summary="Generate a non-persisted preview of a weather-adjusted day itinerary",
)
def preview_day_rearrangement(
    trip_id: UUID,
    payload: RearrangePreviewRequest,
    condition: str = Query(default="hot"),
    session: Session = Depends(get_session),
) -> DayRearrangePreviewRead:
    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip {trip_id} not found.",
        )

    service = WeatherAlternativeService()
    try:
        return service.rearrange_day(
            session=session,
            trip_id=trip_id,
            day_number=payload.day_number,
            condition=condition,
            alternative_place_ids=payload.alternative_place_ids,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc


@router.post(
    "/apply-itinerary-adjustment",
    status_code=status.HTTP_200_OK,
    summary="Transactionally apply a confirmed rearrangement to the trip itinerary",
)
def apply_itinerary_adjustment(
    trip_id: UUID,
    payload: ApplyRearrangementRequest,
    session: Session = Depends(get_session),
) -> dict[str, object]:
    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip {trip_id} not found.",
        )

    service = WeatherAlternativeService()
    try:
        service.apply_rearrangement(
            session=session,
            trip_id=trip_id,
            day_number=payload.day_number,
            place_ids=payload.place_ids,
        )
        return {
            "status": "applied",
            "trip_id": str(trip_id),
            "day_number": payload.day_number,
            "place_count": len(payload.place_ids),
        }
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    except Exception as exc:
        logger.error("Failed applying rearrangement for trip %s: %s", trip_id, exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update itinerary schedule.",
        ) from exc


@router.post(
    "/ignore-weather",
    status_code=status.HTTP_200_OK,
    summary="Ignore weather suggestions for this trip",
)
def ignore_weather_suggestions(
    trip_id: UUID,
    session: Session = Depends(get_session),
) -> dict[str, object]:
    trip = session.get(Trip, trip_id)
    if trip is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Trip {trip_id} not found.",
        )

    existing = session.exec(
        select(TripPreference).where(
            TripPreference.trip_id == trip_id,
            TripPreference.preference == "ignore_weather_advisories",
        )
    ).first()

    if existing is None:
        pref = TripPreference(
            trip_id=trip_id,
            preference="ignore_weather_advisories",
            weight=1.0,
        )
        session.add(pref)
        session.commit()

    return {
        "status": "ignored",
        "trip_id": str(trip_id),
    }
