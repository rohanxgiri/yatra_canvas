"""City API endpoints."""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from app.database import get_session
from app.models import City
from app.schemas import CityCreate, CityRead


router = APIRouter(prefix="/cities", tags=["cities"])
SessionDependency = Annotated[Session, Depends(get_session)]


@router.post("", response_model=CityRead, status_code=status.HTTP_201_CREATED)
def create_city(city_data: CityCreate, session: SessionDependency) -> City:
    """Create and persist a city."""

    city = City.model_validate(city_data)
    session.add(city)
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="The city could not be created because it conflicts with existing data.",
        ) from exc

    session.refresh(city)
    return city


@router.get("", response_model=list[CityRead])
def list_cities(
    session: SessionDependency,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=500)] = 100,
) -> list[City]:
    """Return cities in name order with simple pagination."""

    statement = select(City).order_by(City.name).offset(offset).limit(limit)
    return list(session.exec(statement).all())


@router.get("/{city_id}", response_model=CityRead)
def get_city(city_id: UUID, session: SessionDependency) -> City:
    """Return one city or a clear 404 response."""

    city = session.get(City, city_id)
    if city is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="City not found.",
        )
    return city
