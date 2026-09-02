"""Weather Advisory Service for itinerary-aware weather assistance.

Evaluates normalized weather forecast data against actual trip itinerary stops,
detecting meaningful adverse weather conditions (extreme heat, cold, rain, storm, wind)
that overlap with outdoor activities.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
import logging
from uuid import UUID

from sqlmodel import Session, select

from app.core.weather_constants import (
    COLD_APPARENT_TEMP_C,
    DEFAULT_PLANNING_WINDOW_END_HOUR,
    DEFAULT_PLANNING_WINDOW_START_HOUR,
    HEAVY_PRECIPITATION_WMO_CODES,
    HEAVY_RAIN_MM_PER_HOUR,
    HIGH_PRECIPITATION_PROBABILITY_PCT,
    HIGH_WIND_GUST_KMH,
    HIGH_WIND_SPEED_KMH,
    HOT_APPARENT_TEMP_C,
    MIN_ADVERSE_DURATION_HOURS,
    MODERATE_RAIN_MM_PER_HOUR,
    STORM_WEATHER_CODES,
    STORM_WIND_GUST_KMH,
    VERY_COLD_APPARENT_TEMP_C,
    VERY_HOT_APPARENT_TEMP_C,
    AdvisorySeverity,
    WeatherCondition,
)
from app.models.entities import City, Place, PlaceTag, Trip, TripItinerary, TripPreference
from app.schemas.weather_advisory import TripWeatherAdvisoriesRead, WeatherAdvisoryRead
from app.services.place_environment_classifier import is_outdoor_exposed
from app.services.weather_service import (
    CachedWeatherService,
    NormalizedDailyForecast,
    NormalizedHourlyForecast,
    WeatherProvider,
)

logger = logging.getLogger(__name__)


class WeatherAdvisoryService:
    """Detects weather conditions impacting itinerary stops and produces structured advisories."""

    def __init__(self, weather_provider: WeatherProvider) -> None:
        self._weather_provider = weather_provider
        self._cached_service = CachedWeatherService(weather_provider)

    async def get_trip_advisories(
        self, session: Session, trip_id: UUID
    ) -> TripWeatherAdvisoriesRead:
        trip = session.get(Trip, trip_id)
        if trip is None:
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="trip_not_found", advisories=[]
            )

        # Check if user opted to ignore weather suggestions for this trip
        ignored = session.exec(
            select(TripPreference).where(
                TripPreference.trip_id == trip_id,
                TripPreference.preference == "ignore_weather_advisories",
            )
        ).first()
        if ignored is not None:
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="ignored", advisories=[]
            )

        # Determine coordinates
        lat = trip.start_latitude or trip.arrival_latitude
        lon = trip.start_longitude or trip.arrival_longitude
        if lat is None or lon is None:
            city = session.get(City, trip.city_id)
            if city:
                lat, lon = city.latitude, city.longitude

        if lat is None or lon is None:
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="no_coordinates", advisories=[]
            )

        if trip.start_date is None:
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="no_dates_set", advisories=[]
            )

        end_date = trip.start_date + timedelta(days=max(trip.days - 1, 0))

        # Fetch forecasts
        forecasts = await self._cached_service.get_forecast(
            lat, lon, trip.start_date, end_date
        )
        if forecasts is None:
            # Trip is outside the provider's forecast horizon or provider is unreachable
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="no_forecast_available", advisories=[]
            )

        # Fetch itinerary places for the trip
        itinerary_rows = list(
            session.exec(
                select(TripItinerary)
                .where(TripItinerary.trip_id == trip_id)
                .order_by(TripItinerary.day_number, TripItinerary.visit_order)  # type: ignore[arg-type]
            ).all()
        )
        if not itinerary_rows:
            return TripWeatherAdvisoriesRead(
                trip_id=trip_id, status="ok", advisories=[]
            )

        # Preload places and tags
        place_ids = {r.place_id for r in itinerary_rows}
        places_by_id = {p.id: p for p in session.exec(select(Place).where(Place.id.in_(place_ids))).all()}  # type: ignore[attr-defined]
        tags_by_place_id: dict[UUID, list[str]] = {}
        for tag_row in session.exec(select(PlaceTag).where(PlaceTag.place_id.in_(place_ids))).all():  # type: ignore[attr-defined]
            tags_by_place_id.setdefault(tag_row.place_id, []).append(tag_row.tag)

        # Group itinerary by day
        itinerary_by_day: dict[int, list[TripItinerary]] = {}
        for row in itinerary_rows:
            itinerary_by_day.setdefault(row.day_number, []).append(row)

        advisories: list[WeatherAdvisoryRead] = []

        # Analyze each day
        forecast_by_date = {f.date: f for f in forecasts}

        for day_num in range(1, trip.days + 1):
            day_date = trip.start_date + timedelta(days=day_num - 1)
            daily_forecast = forecast_by_date.get(day_date)
            if daily_forecast is None:
                continue

            day_stops = itinerary_by_day.get(day_num, [])
            if not day_stops:
                continue

            advisory = self._evaluate_day_advisory(
                trip_id=trip_id,
                day_number=day_num,
                day_date=day_date,
                daily_forecast=daily_forecast,
                day_stops=day_stops,
                places_by_id=places_by_id,
                tags_by_place_id=tags_by_place_id,
            )
            if advisory is not None:
                advisories.append(advisory)

        return TripWeatherAdvisoriesRead(
            trip_id=trip_id, status="ok", advisories=advisories
        )

    def _evaluate_day_advisory(
        self,
        trip_id: UUID,
        day_number: int,
        day_date: date,
        daily_forecast: NormalizedDailyForecast,
        day_stops: list[TripItinerary],
        places_by_id: dict[UUID, Place],
        tags_by_place_id: dict[UUID, list[str]],
    ) -> WeatherAdvisoryRead | None:
        """Evaluate whether adverse weather overlaps with outdoor stops on a day."""
        hourly = daily_forecast.hourly
        if not hourly:
            return None

        # Detect adverse condition windows during touring hours (09:00 - 18:00)
        touring_hours = [
            h
            for h in hourly
            if DEFAULT_PLANNING_WINDOW_START_HOUR <= h.timestamp.hour < DEFAULT_PLANNING_WINDOW_END_HOUR
        ]
        if not touring_hours:
            touring_hours = list(hourly)

        condition, severity, affected_hours = self._detect_condition(touring_hours)
        if condition == WeatherCondition.NORMAL or not affected_hours:
            return None

        affected_start = affected_hours[0].timestamp
        affected_end = affected_hours[-1].timestamp + timedelta(hours=1)

        # Identify places scheduled during the affected hours
        num_stops = len(day_stops)
        affected_places: list[Place] = []

        for idx, stop in enumerate(day_stops):
            place = places_by_id.get(stop.place_id)
            if place is None:
                continue

            tags = tags_by_place_id.get(place.id, [])
            if not is_outdoor_exposed(place.category, tags, place.name):
                # Sheltered indoor venue is not adversely affected by heat/rain
                continue

            # Check if this stop overlaps with the affected window
            is_overlapping = False
            tz = affected_start.tzinfo
            if stop.planned_arrival_time is not None and stop.planned_departure_time is not None:
                stop_start = datetime.combine(day_date, stop.planned_arrival_time, tzinfo=tz) if tz else datetime.combine(day_date, stop.planned_arrival_time)
                stop_end = datetime.combine(day_date, stop.planned_departure_time, tzinfo=tz) if tz else datetime.combine(day_date, stop.planned_departure_time)
                if stop_start < affected_end and stop_end > affected_start:
                    is_overlapping = True
            else:
                # Documented fallback planning window:
                # Distribute stops across the daily window (09:00 to 18:00, 9 hours)
                slot_duration_hours = max(9.0 / max(num_stops, 1), 1.5)
                estimated_start_hour = DEFAULT_PLANNING_WINDOW_START_HOUR + (idx * slot_duration_hours)
                estimated_start = datetime.combine(day_date, time(int(min(estimated_start_hour, 23))), tzinfo=tz) if tz else datetime.combine(day_date, time(int(min(estimated_start_hour, 23))))
                estimated_end = estimated_start + timedelta(hours=slot_duration_hours)
                if estimated_start < affected_end and estimated_end > affected_start:
                    is_overlapping = True

            if is_overlapping:
                affected_places.append(place)

        if not affected_places:
            # Condition occurred, but no outdoor places are affected (e.g. already all indoor)
            return None

        # Build summary
        summary = self._build_summary(
            day_number=day_number,
            condition=condition,
            affected_hours=affected_hours,
            affected_places=affected_places,
        )

        return WeatherAdvisoryRead(
            id=f"advisory-{trip_id}-d{day_number}-{condition}",
            day_number=day_number,
            condition=condition,
            severity=severity,
            affected_start=affected_start,
            affected_end=affected_end,
            summary=summary,
            affected_place_ids=[p.id for p in affected_places],
            affected_place_names=[p.name for p in affected_places],
            actions=["continue", "suggest_alternatives", "rearrange_day"],
        )

    def _detect_condition(
        self, hourly: list[NormalizedHourlyForecast]
    ) -> tuple[WeatherCondition, AdvisorySeverity, list[NormalizedHourlyForecast]]:
        """Identify adverse condition spanning at least MIN_ADVERSE_DURATION_HOURS."""
        # 1. Extreme Heat (VERY_HOT)
        very_hot_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            if h.apparent_temperature >= VERY_HOT_APPARENT_TEMP_C:
                very_hot_consecutive.append(h)
                if len(very_hot_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.VERY_HOT, AdvisorySeverity.WARNING, very_hot_consecutive
            else:
                if len(very_hot_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    very_hot_consecutive.clear()

        # 2. Storms / Thunderstorms
        storm_hours = [
            h for h in hourly
            if h.weather_code in STORM_WEATHER_CODES or h.wind_gusts_kmh >= STORM_WIND_GUST_KMH
        ]
        if storm_hours:
            return WeatherCondition.STORM, AdvisorySeverity.WARNING, storm_hours

        # 3. Heavy Rain
        heavy_rain_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            is_heavy = (
                h.precipitation_mm >= HEAVY_RAIN_MM_PER_HOUR
                or (h.precipitation_probability >= HIGH_PRECIPITATION_PROBABILITY_PCT and h.precipitation_mm >= MODERATE_RAIN_MM_PER_HOUR)
                or h.weather_code in HEAVY_PRECIPITATION_WMO_CODES
            )
            if is_heavy:
                heavy_rain_consecutive.append(h)
                if len(heavy_rain_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.HEAVY_RAIN, AdvisorySeverity.WARNING, heavy_rain_consecutive
            else:
                if len(heavy_rain_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    heavy_rain_consecutive.clear()

        # 4. Moderate Heat (HOT)
        hot_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            if h.apparent_temperature >= HOT_APPARENT_TEMP_C:
                hot_consecutive.append(h)
                if len(hot_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.HOT, AdvisorySeverity.ADVISORY, hot_consecutive
            else:
                if len(hot_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    hot_consecutive.clear()

        # 5. Extreme Cold (VERY_COLD)
        very_cold_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            if h.apparent_temperature <= VERY_COLD_APPARENT_TEMP_C:
                very_cold_consecutive.append(h)
                if len(very_cold_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.VERY_COLD, AdvisorySeverity.WARNING, very_cold_consecutive
            else:
                if len(very_cold_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    very_cold_consecutive.clear()

        # 6. Cold
        cold_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            if h.apparent_temperature <= COLD_APPARENT_TEMP_C:
                cold_consecutive.append(h)
                if len(cold_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.COLD, AdvisorySeverity.ADVISORY, cold_consecutive
            else:
                if len(cold_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    cold_consecutive.clear()

        # 7. High Wind
        wind_consecutive: list[NormalizedHourlyForecast] = []
        for h in hourly:
            if h.wind_speed_kmh >= HIGH_WIND_SPEED_KMH or h.wind_gusts_kmh >= HIGH_WIND_GUST_KMH:
                wind_consecutive.append(h)
                if len(wind_consecutive) >= MIN_ADVERSE_DURATION_HOURS:
                    return WeatherCondition.HIGH_WIND, AdvisorySeverity.ADVISORY, wind_consecutive
            else:
                if len(wind_consecutive) < MIN_ADVERSE_DURATION_HOURS:
                    wind_consecutive.clear()

        return WeatherCondition.NORMAL, AdvisorySeverity.INFO, []

    def _build_summary(
        self,
        day_number: int,
        condition: WeatherCondition,
        affected_hours: list[NormalizedHourlyForecast],
        affected_places: list[Place],
    ) -> str:
        start_hour = affected_hours[0].timestamp.strftime("%I:%M %p").lstrip("0")
        end_hour = (affected_hours[-1].timestamp + timedelta(hours=1)).strftime("%I:%M %p").lstrip("0")
        time_span = f"{start_hour}–{end_hour}"
        place_count = len(affected_places)
        places_str = f"{place_count} outdoor {'place' if place_count == 1 else 'places'}"

        if condition in (WeatherCondition.VERY_HOT, WeatherCondition.HOT):
            peak_temp = max(h.apparent_temperature for h in affected_hours)
            intensity = "very hot" if condition == WeatherCondition.VERY_HOT else "hot"
            return (
                f"Day {day_number} between {time_span} may be {intensity} "
                f"(apparent temperature reaching {peak_temp:.0f}°C). "
                f"You have {places_str} planned during this window."
            )
        elif condition == WeatherCondition.HEAVY_RAIN:
            return (
                f"Heavy rain is forecast on Day {day_number} around {time_span}. "
                f"You have {places_str} planned during this wet period."
            )
        elif condition == WeatherCondition.STORM:
            return (
                f"Thunderstorms and strong gusts are forecast on Day {day_number} around {time_span}. "
                f"You have {places_str} scheduled during this period."
            )
        elif condition in (WeatherCondition.VERY_COLD, WeatherCondition.COLD):
            min_temp = min(h.apparent_temperature for h in affected_hours)
            intensity = "freezing" if condition == WeatherCondition.VERY_COLD else "cold"
            return (
                f"Day {day_number} between {time_span} will be {intensity} "
                f"(apparent temperature down to {min_temp:.0f}°C). "
                f"You have {places_str} planned during this period."
            )
        elif condition == WeatherCondition.HIGH_WIND:
            max_wind = max(h.wind_gusts_kmh for h in affected_hours)
            return (
                f"High wind gusts up to {max_wind:.0f} km/h are expected on Day {day_number} around {time_span}. "
                f"You have {places_str} scheduled during this window."
            )

        return f"Adverse weather is forecast on Day {day_number} affecting {places_str}."
