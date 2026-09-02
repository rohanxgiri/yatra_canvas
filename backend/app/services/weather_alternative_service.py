"""Weather alternative recommendations and itinerary rearrangement service.

Generates indoor/sheltered place alternatives matching user preferences,
creates proposed non-persisted rearranged day schedules protecting constraints (must_visit, is_locked),
and transactionally applies user-confirmed adjustments.
"""

from __future__ import annotations

import logging
from uuid import UUID

from sqlmodel import Session, delete, select

from app.core.weather_constants import (
    WeatherCondition,
)
from app.models.entities import Place, PlaceTag, Trip, TripItinerary, TripPreference, UserSavedPlace
from app.schemas.weather_advisory import (
    DayRearrangePreviewRead,
    PlaceAlternativeRead,
    ProposedStopRead,
)
from app.services.place_environment_classifier import (
    classify_place,
    is_indoor_sheltered,
    is_outdoor_exposed,
)

logger = logging.getLogger(__name__)


class WeatherAlternativeService:
    """Provides weather-friendly place recommendations and non-persisted rearrangement previews."""

    def suggest_alternatives(
        self,
        session: Session,
        trip_id: UUID,
        day_number: int,
        condition: str,
    ) -> list[PlaceAlternativeRead]:
        trip = session.get(Trip, trip_id)
        if trip is None:
            return []

        # Get existing itinerary place IDs for this trip to avoid duplicates
        existing_place_ids = set(
            session.exec(
                select(TripItinerary.place_id).where(TripItinerary.trip_id == trip_id)
            ).all()
        )

        # Get user preferences / purposes
        user_prefs = {
            row.preference.lower()
            for row in session.exec(
                select(TripPreference).where(TripPreference.trip_id == trip_id)
            ).all()
        }

        # Query candidate places in the city
        candidates = list(
            session.exec(
                select(Place)
                .where(Place.city_id == trip.city_id)
                .where(Place.id.not_in(existing_place_ids))  # type: ignore[attr-defined]
            ).all()
        )
        if not candidates:
            return []

        # Fetch tags for candidates
        candidate_ids = [c.id for c in candidates]
        tags_by_id: dict[UUID, list[str]] = {}
        for t in session.exec(select(PlaceTag).where(PlaceTag.place_id.in_(candidate_ids))).all():  # type: ignore[attr-defined]
            tags_by_id.setdefault(t.place_id, []).append(t.tag)

        # Filter and score candidates based on condition
        scored_alternatives: list[tuple[float, PlaceAlternativeRead]] = []

        is_heat_or_rain = condition in (
            WeatherCondition.VERY_HOT,
            WeatherCondition.HOT,
            WeatherCondition.HEAVY_RAIN,
            WeatherCondition.STORM,
        )

        for place in candidates:
            tags = tags_by_id.get(place.id, [])
            env = classify_place(place.category, tags, place.name)

            if is_heat_or_rain and not is_indoor_sheltered(place.category, tags, place.name):
                # Only offer reliable indoor sheltered environments during extreme heat or rain
                continue

            # Calculate preference relevance score
            score = 1.0
            place_text = f"{place.name} {place.category} {' '.join(tags)}".lower()
            matched_prefs: list[str] = []
            for pref in user_prefs:
                if pref in place_text:
                    score += 2.0
                    matched_prefs.append(pref)

            if place.is_popular:
                score += 0.5
            if place.is_heritage and "history" in user_prefs:
                score += 1.0

            # Reason formulation
            if matched_prefs:
                reason = f"Sheltered indoor venue matching your interest in {', '.join(matched_prefs)}."
            elif is_heat_or_rain:
                reason = "Comfortable sheltered indoor environment protected from adverse weather."
            else:
                reason = "Weather-friendly attraction in your destination city."

            scored_alternatives.append(
                (
                    score,
                    PlaceAlternativeRead(
                        place_id=place.id,
                        name=place.name,
                        category=place.category,
                        reason=reason,
                        environment=env.value,
                    ),
                )
            )

        scored_alternatives.sort(key=lambda item: item[0], reverse=True)
        return [item[1] for item in scored_alternatives[:5]]

    def rearrange_day(
        self,
        session: Session,
        trip_id: UUID,
        day_number: int,
        condition: str,
        alternative_place_ids: list[UUID] | None = None,
    ) -> DayRearrangePreviewRead:
        """Create a proposed rearrangement preview without persisting changes to the database."""
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise ValueError(f"Trip {trip_id} not found")

        # Load day's current itinerary
        itinerary_rows = list(
            session.exec(
                select(TripItinerary)
                .where(
                    TripItinerary.trip_id == trip_id,
                    TripItinerary.day_number == day_number,
                )
                .order_by(TripItinerary.visit_order)  # type: ignore[arg-type]
            ).all()
        )
        if not itinerary_rows:
            return DayRearrangePreviewRead(
                trip_id=trip_id,
                day_number=day_number,
                original_places=[],
                proposed_places=[],
                explanation="No itinerary stops planned on this day to rearrange.",
            )

        # Load saved place constraints (locked, must_visit)
        saved_places_by_id = {
            sp.place_id: sp
            for sp in session.exec(
                select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)
            ).all()
        }

        # Load places and tags
        current_place_ids = [r.place_id for r in itinerary_rows]
        all_ids = set(current_place_ids) | set(alternative_place_ids or [])
        places_by_id = {
            p.id: p for p in session.exec(select(Place).where(Place.id.in_(all_ids))).all()  # type: ignore[attr-defined]
        }
        tags_by_id: dict[UUID, list[str]] = {}
        for t in session.exec(select(PlaceTag).where(PlaceTag.place_id.in_(all_ids))).all():  # type: ignore[attr-defined]
            tags_by_id.setdefault(t.place_id, []).append(t.tag)

        # Build original list with time windows
        original_stops: list[ProposedStopRead] = []
        for idx, row in enumerate(itinerary_rows):
            p = places_by_id.get(row.place_id)
            if p is None:
                continue
            tags = tags_by_id.get(p.id, [])
            env = classify_place(p.category, tags, p.name)
            time_str = self._approximate_time_window(idx, len(itinerary_rows))
            original_stops.append(
                ProposedStopRead(
                    place_id=p.id,
                    name=p.name,
                    visit_order=idx + 1,
                    time_window=time_str,
                    is_alternative=False,
                    environment=env.value,
                )
            )

        # Strategy for proposing rearrangement:
        # Separate flexible outdoor vs indoor stops.
        # Preserve locked places at their specific index if possible.
        locked_places = [
            (idx, row.place_id)
            for idx, row in enumerate(itinerary_rows)
            if saved_places_by_id.get(row.place_id) and saved_places_by_id[row.place_id].is_locked
        ]
        locked_set = {pid for _, pid in locked_places}

        flexible_stops = [
            row.place_id for row in itinerary_rows if row.place_id not in locked_set
        ]

        # Categorize flexible stops into outdoor vs indoor
        flexible_outdoor: list[UUID] = []
        flexible_indoor: list[UUID] = []
        for pid in flexible_stops:
            p = places_by_id.get(pid)
            if p is None:
                continue
            tags = tags_by_id.get(pid, [])
            if is_outdoor_exposed(p.category, tags, p.name):
                flexible_outdoor.append(pid)
            else:
                flexible_indoor.append(pid)

        # Incorporate selected alternatives into the indoor pool if provided
        for alt_id in alternative_place_ids or []:
            if alt_id in places_by_id and alt_id not in current_place_ids:
                flexible_indoor.append(alt_id)

        # Proposed ordering:
        # Morning (early hours): flexible outdoor
        # Midday / Afternoon (peak heat / rain): flexible indoor / alternatives
        # Late Afternoon / Evening: remaining outdoor
        split_point = len(flexible_outdoor) // 2
        morning_outdoor = flexible_outdoor[:split_point]
        evening_outdoor = flexible_outdoor[split_point:]

        proposed_order_pids = morning_outdoor + flexible_indoor + evening_outdoor

        # Reinsert locked places at their original relative positions
        for orig_idx, locked_pid in sorted(locked_places, key=lambda x: x[0]):
            insert_idx = min(orig_idx, len(proposed_order_pids))
            proposed_order_pids.insert(insert_idx, locked_pid)

        # Build proposed stops list
        proposed_stops: list[ProposedStopRead] = []
        for idx, pid in enumerate(proposed_order_pids):
            p = places_by_id.get(pid)
            if p is None:
                continue
            tags = tags_by_id.get(pid, [])
            env = classify_place(p.category, tags, p.name)
            time_str = self._approximate_time_window(idx, len(proposed_order_pids))
            proposed_stops.append(
                ProposedStopRead(
                    place_id=p.id,
                    name=p.name,
                    visit_order=idx + 1,
                    time_window=time_str,
                    is_alternative=pid not in current_place_ids,
                    environment=env.value,
                )
            )

        explanation = (
            "Proposed adjustment: Outdoor visits scheduled for cooler morning and late afternoon hours; "
            "indoor or sheltered attractions placed during the peak adverse period."
        )

        return DayRearrangePreviewRead(
            trip_id=trip_id,
            day_number=day_number,
            original_places=original_stops,
            proposed_places=proposed_stops,
            explanation=explanation,
        )

    def apply_rearrangement(
        self,
        session: Session,
        trip_id: UUID,
        day_number: int,
        place_ids: list[UUID],
    ) -> None:
        """Transactionally applies the proposed arrangement to the database."""
        trip = session.get(Trip, trip_id)
        if trip is None:
            raise ValueError(f"Trip {trip_id} not found")

        # Load existing day itinerary to check must-visit places
        current_rows = list(
            session.exec(
                select(TripItinerary)
                .where(
                    TripItinerary.trip_id == trip_id,
                    TripItinerary.day_number == day_number,
                )
            ).all()
        )
        saved_places = {
            sp.place_id: sp
            for sp in session.exec(
                select(UserSavedPlace).where(UserSavedPlace.trip_id == trip_id)
            ).all()
        }

        # Must-visit check: ensure no must-visit place from current day is omitted
        for row in current_rows:
            sp = saved_places.get(row.place_id)
            if sp and sp.must_visit and row.place_id not in place_ids:
                raise ValueError(
                    "Cannot remove a must-visit place from the day schedule."
                )

        try:
            # Delete old day itinerary and flush before inserting new visit orders
            session.exec(
                delete(TripItinerary).where(
                    TripItinerary.trip_id == trip_id,
                    TripItinerary.day_number == day_number,
                )
            )
            session.flush()

            # Insert new order
            for idx, pid in enumerate(place_ids, start=1):
                # Ensure the place is in UserSavedPlace for the trip
                if pid not in saved_places:
                    new_sp = UserSavedPlace(
                        trip_id=trip_id,
                        place_id=pid,
                        custom_order=idx,
                    )
                    session.add(new_sp)

                new_itinerary_row = TripItinerary(
                    trip_id=trip_id,
                    place_id=pid,
                    day_number=day_number,
                    visit_order=idx,
                )
                session.add(new_itinerary_row)

            session.commit()
            logger.info(
                "Successfully applied weather itinerary rearrangement for trip %s, day %d",
                trip_id,
                day_number,
            )
        except Exception as exc:
            session.rollback()
            logger.error(
                "Failed to apply rearrangement for trip %s, day %d: %s",
                trip_id,
                day_number,
                exc,
            )
            raise

    @staticmethod
    def _approximate_time_window(index: int, total_stops: int) -> str:
        """Generate human-readable approximate time label for display in preview."""
        times = [
            "9:30 AM",
            "11:30 AM",
            "1:30 PM",
            "3:30 PM",
            "5:30 PM",
            "7:00 PM",
        ]
        if index < len(times):
            return times[index]
        return f"Stop {index + 1}"
