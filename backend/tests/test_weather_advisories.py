"""Unit and integration tests for Weather-Aware Trip Assistance."""

from datetime import date, datetime, time, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine, select

from app.database import get_session
from app.main import app
from app.models.entities import City, Place, PlaceTag, Trip, TripItinerary, TripPreference, UserSavedPlace
from app.routers.weather_advisories import get_weather_provider
from app.services.place_environment_classifier import PlaceEnvironment, classify_place, is_outdoor_exposed
from app.services.weather_service import (
    CachedWeatherService,
    NormalizedDailyForecast,
    NormalizedHourlyForecast,
    WeatherProvider,
)


class MockWeatherProvider(WeatherProvider):
    """Controllable mock weather provider for deterministic testing."""

    def __init__(
        self,
        forecasts: list[NormalizedDailyForecast] | None = None,
        should_fail: bool = False,
    ) -> None:
        self.forecasts = forecasts
        self.should_fail = should_fail
        self.call_count = 0

    async def get_forecast(
        self,
        latitude: float,
        longitude: float,
        start_date: date,
        end_date: date,
    ) -> list[NormalizedDailyForecast] | None:
        self.call_count += 1
        if self.should_fail:
            raise RuntimeError("Upstream weather provider timed out")
        return self.forecasts


def _make_hourly_series(
    day_date: date,
    temperatures: list[float],
    apparent_temperatures: list[float],
    precipitation: list[float] | None = None,
    weather_codes: list[int] | None = None,
    wind_gusts: list[float] | None = None,
) -> list[NormalizedHourlyForecast]:
    hours: list[NormalizedHourlyForecast] = []
    for h in range(24):
        dt = datetime.combine(day_date, time(h, 0), tzinfo=timezone.utc)
        temp = temperatures[h] if h < len(temperatures) else 25.0
        app_temp = apparent_temperatures[h] if h < len(apparent_temperatures) else 25.0
        precip = precipitation[h] if precipitation and h < len(precipitation) else 0.0
        code = weather_codes[h] if weather_codes and h < len(weather_codes) else 0
        gust = wind_gusts[h] if wind_gusts and h < len(wind_gusts) else 10.0

        hours.append(
            NormalizedHourlyForecast(
                timestamp=dt,
                temperature=temp,
                apparent_temperature=app_temp,
                precipitation_probability=85.0 if precip > 0 else 10.0,
                precipitation_mm=precip,
                weather_code=code,
                wind_speed_kmh=15.0,
                wind_gusts_kmh=gust,
            )
        )
    return hours


@pytest.fixture
def session_and_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    with Session(engine) as session:
        def override_get_session():
            yield session

        app.dependency_overrides[get_session] = override_get_session
        with TestClient(app) as client:
            yield session, client

    app.dependency_overrides.clear()


def test_place_environment_classifier():
    assert classify_place("Park") == PlaceEnvironment.OUTDOOR
    assert classify_place("Monument") == PlaceEnvironment.OUTDOOR
    assert classify_place("Fort") == PlaceEnvironment.OUTDOOR
    assert classify_place("Museum") == PlaceEnvironment.INDOOR
    assert classify_place("Art Gallery") == PlaceEnvironment.INDOOR
    assert classify_place("Shopping Mall") == PlaceEnvironment.INDOOR
    assert classify_place("Palace") == PlaceEnvironment.DUAL

    # Outdoor exposed check
    assert is_outdoor_exposed("Fort") is True
    assert is_outdoor_exposed("Garden") is True
    assert is_outdoor_exposed("Museum") is False


def test_normal_weather_generates_no_advisory(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=2)
    trip = Trip(
        user_id=uuid4(),
        city_id=city.id,
        trip_name="Pleasant Jaipur",
        days=1,
        start_date=trip_date,
    )
    session.add(trip)
    session.commit()

    place = Place(city_id=city.id, name="Amer Fort", category="fort", latitude=26.9855, longitude=75.8513)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # Pleasant temperatures (26C apparent temp)
    hourly = _make_hourly_series(
        trip_date,
        temperatures=[25.0] * 24,
        apparent_temperatures=[26.0] * 24,
    )
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=27.0,
        temperature_min=20.0,
        apparent_temperature_max=27.0,
        apparent_temperature_min=20.0,
        precipitation_sum_mm=0.0,
        precipitation_probability_max=10.0,
        wind_speed_max_kmh=15.0,
        wind_gusts_max_kmh=20.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["advisories"] == []


def test_isolated_one_hour_spike_does_not_trigger_advisory(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=2)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Spike Test", days=1, start_date=trip_date)
    session.add(trip)
    session.commit()

    place = Place(city_id=city.id, name="City Palace", category="fort", latitude=26.9258, longitude=75.8236)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # Only 1 hour (hour 14) has 43C; hours 13 and 15 are 32C
    app_temps = [32.0] * 24
    app_temps[14] = 43.0

    hourly = _make_hourly_series(trip_date, temperatures=[30.0] * 24, apparent_temperatures=app_temps)
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=35.0,
        temperature_min=25.0,
        apparent_temperature_max=43.0,
        apparent_temperature_min=25.0,
        precipitation_sum_mm=0.0,
        precipitation_probability_max=0.0,
        wind_speed_max_kmh=10.0,
        wind_gusts_max_kmh=15.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert data["advisories"] == []


def test_very_hot_weather_triggers_advisory_on_outdoor_place(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=2)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Hot Jaipur", days=1, start_date=trip_date)
    session.add(trip)
    session.commit()

    place = Place(city_id=city.id, name="Amer Fort", category="fort", latitude=26.9855, longitude=75.8513)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # 4 consecutive hours of 43C apparent temp during afternoon (13, 14, 15, 16)
    app_temps = [32.0] * 24
    for h in (13, 14, 15, 16):
        app_temps[h] = 43.5

    hourly = _make_hourly_series(trip_date, temperatures=[38.0] * 24, apparent_temperatures=app_temps)
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=40.0,
        temperature_min=28.0,
        apparent_temperature_max=43.5,
        apparent_temperature_min=28.0,
        precipitation_sum_mm=0.0,
        precipitation_probability_max=0.0,
        wind_speed_max_kmh=12.0,
        wind_gusts_max_kmh=18.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["advisories"]) == 1
    advisory = data["advisories"][0]
    assert advisory["condition"] == "very_hot"
    assert advisory["severity"] == "warning"
    assert "very hot" in advisory["summary"].lower()
    assert str(place.id) in [str(pid) for pid in advisory["affected_place_ids"]]
    assert "continue" in advisory["actions"]
    assert "suggest_alternatives" in advisory["actions"]
    assert "rearrange_day" in advisory["actions"]


def test_indoor_only_day_does_not_trigger_heat_advisory(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=2)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Museum Day", days=1, start_date=trip_date)
    session.add(trip)
    session.commit()

    # Pure indoor museum
    place = Place(city_id=city.id, name="Albert Hall Museum", category="museum", latitude=26.9118, longitude=75.8195)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # 43C heat
    app_temps = [43.0] * 24
    hourly = _make_hourly_series(trip_date, temperatures=[38.0] * 24, apparent_temperatures=app_temps)
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=40.0,
        temperature_min=28.0,
        apparent_temperature_max=43.0,
        apparent_temperature_min=28.0,
        precipitation_sum_mm=0.0,
        precipitation_probability_max=0.0,
        wind_speed_max_kmh=10.0,
        wind_gusts_max_kmh=15.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    # No advisory because the venue is sheltered indoor!
    assert data["advisories"] == []


def test_heavy_rain_and_storm_advisories(session_and_client):
    session, client = session_and_client

    city = City(name="Goa", country="India", latitude=15.2993, longitude=74.1240)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=3)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Beach Trip", days=1, start_date=trip_date)
    session.add(trip)
    session.commit()

    place = Place(city_id=city.id, name="Calangute Beach", category="beach", latitude=15.5439, longitude=73.7553)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # Rain of 10 mm/hr for 3 hours
    rain = [0.0] * 24
    rain[10] = 10.5
    rain[11] = 12.0
    rain[12] = 8.5

    hourly = _make_hourly_series(
        trip_date,
        temperatures=[26.0] * 24,
        apparent_temperatures=[28.0] * 24,
        precipitation=rain,
        weather_codes=[65 if 10 <= h <= 12 else 0 for h in range(24)],
    )
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=28.0,
        temperature_min=24.0,
        apparent_temperature_max=30.0,
        apparent_temperature_min=24.0,
        precipitation_sum_mm=31.0,
        precipitation_probability_max=95.0,
        wind_speed_max_kmh=25.0,
        wind_gusts_max_kmh=40.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["advisories"]) == 1
    assert data["advisories"][0]["condition"] == "heavy_rain"


def test_forecast_outside_horizon_returns_no_forecast_available(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    # 40 days in the future (outside 16-day horizon)
    future_date = date.today() + timedelta(days=40)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Future Journey", days=2, start_date=future_date)
    session.add(trip)
    session.commit()

    mock_provider = MockWeatherProvider(None)  # Provider returns None outside horizon
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "no_forecast_available"
    assert data["advisories"] == []


def test_weather_provider_timeout_degrades_gracefully(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Timeout Trip", days=1, start_date=date.today())
    session.add(trip)
    session.commit()

    mock_provider = MockWeatherProvider(should_fail=True)
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "weather_unavailable"
    assert data["advisories"] == []


def test_suggest_weather_alternatives(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Cultural Tour", days=1, start_date=date.today())
    session.add(trip)
    session.commit()

    pref = TripPreference(trip_id=trip.id, preference="history", weight=1.0)
    session.add(pref)
    session.commit()

    museum = Place(city_id=city.id, name="Albert Hall Museum", category="museum", latitude=26.9118, longitude=75.8195, is_heritage=True)
    mall = Place(city_id=city.id, name="World Trade Park", category="mall", latitude=26.8530, longitude=75.8050)
    outdoor_park = Place(city_id=city.id, name="Central Park", category="park", latitude=26.9032, longitude=75.8085)
    session.add_all([museum, mall, outdoor_park])
    session.commit()

    resp = client.get(f"/trips/{trip.id}/weather-alternatives?day_number=1&condition=very_hot")
    assert resp.status_code == 200
    alternatives = resp.json()

    alt_names = [a["name"] for a in alternatives]
    assert "Albert Hall Museum" in alt_names
    assert "World Trade Park" in alt_names
    # Outdoor park should NOT be recommended as an alternative for extreme heat!
    assert "Central Park" not in alt_names


def test_rearrange_preview_and_transactional_apply(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Rearrange Test", days=1, start_date=date.today())
    session.add(trip)
    session.commit()

    fort = Place(city_id=city.id, name="Amer Fort", category="fort", latitude=26.9855, longitude=75.8513)
    palace = Place(city_id=city.id, name="City Palace", category="palace", latitude=26.9258, longitude=75.8236)
    museum = Place(city_id=city.id, name="Albert Hall Museum", category="museum", latitude=26.9118, longitude=75.8195)
    session.add_all([fort, palace, museum])
    session.commit()

    it1 = TripItinerary(trip_id=trip.id, place_id=fort.id, day_number=1, visit_order=1)
    it2 = TripItinerary(trip_id=trip.id, place_id=palace.id, day_number=1, visit_order=2)
    session.add_all([it1, it2])
    session.commit()

    saved_fort = UserSavedPlace(trip_id=trip.id, place_id=fort.id, must_visit=True)
    saved_palace = UserSavedPlace(trip_id=trip.id, place_id=palace.id, must_visit=False)
    session.add_all([saved_fort, saved_palace])
    session.commit()

    # 1. Request Preview
    preview_resp = client.post(
        f"/trips/{trip.id}/rearrange-preview",
        json={"day_number": 1, "alternative_place_ids": [str(museum.id)]},
    )
    assert preview_resp.status_code == 200
    preview = preview_resp.json()
    assert preview["day_number"] == 1
    assert len(preview["proposed_places"]) == 3
    # Database MUST NOT be modified by preview!
    current_count = len(session.exec(select(TripItinerary).where(TripItinerary.trip_id == trip.id)).all())
    assert current_count == 2

    # 2. Cannot omit must-visit place when applying
    bad_apply = client.post(
        f"/trips/{trip.id}/apply-itinerary-adjustment",
        json={"day_number": 1, "place_ids": [str(palace.id), str(museum.id)]},
    )
    assert bad_apply.status_code == 400
    assert "must-visit" in bad_apply.json()["detail"].lower()

    # 3. Apply with must-visit fort included
    good_apply = client.post(
        f"/trips/{trip.id}/apply-itinerary-adjustment",
        json={"day_number": 1, "place_ids": [str(fort.id), str(museum.id), str(palace.id)]},
    )
    assert good_apply.status_code == 200
    assert good_apply.json()["status"] == "applied"

    # Verify DB state is updated
    updated_itinerary = list(
        session.exec(
            select(TripItinerary)
            .where(TripItinerary.trip_id == trip.id)
            .order_by(TripItinerary.visit_order)  # type: ignore[arg-type]
        ).all()
    )
    assert len(updated_itinerary) == 3
    assert updated_itinerary[0].place_id == fort.id
    assert updated_itinerary[1].place_id == museum.id
    assert updated_itinerary[2].place_id == palace.id


def test_ignore_weather_suggestions(session_and_client):
    session, client = session_and_client

    city = City(name="Jaipur", country="India", latitude=26.9124, longitude=75.7873)
    session.add(city)
    session.commit()

    trip_date = date.today() + timedelta(days=2)
    trip = Trip(user_id=uuid4(), city_id=city.id, trip_name="Ignore Test", days=1, start_date=trip_date)
    session.add(trip)
    session.commit()

    place = Place(city_id=city.id, name="Amer Fort", category="fort", latitude=26.9855, longitude=75.8513)
    session.add(place)
    session.commit()

    itinerary = TripItinerary(trip_id=trip.id, place_id=place.id, day_number=1, visit_order=1)
    session.add(itinerary)
    session.commit()

    # Extreme heat
    app_temps = [44.0] * 24
    hourly = _make_hourly_series(trip_date, temperatures=[38.0] * 24, apparent_temperatures=app_temps)
    daily = NormalizedDailyForecast(
        date=trip_date,
        temperature_max=42.0,
        temperature_min=28.0,
        apparent_temperature_max=44.0,
        apparent_temperature_min=28.0,
        precipitation_sum_mm=0.0,
        precipitation_probability_max=0.0,
        wind_speed_max_kmh=10.0,
        wind_gusts_max_kmh=15.0,
        hourly=tuple(hourly),
    )

    mock_provider = MockWeatherProvider([daily])
    app.dependency_overrides[get_weather_provider] = lambda: mock_provider

    # Before ignoring: advisory is returned
    resp = client.get(f"/trips/{trip.id}/weather-advisories")
    assert len(resp.json()["advisories"]) == 1

    # User ignores weather for this trip
    ignore_resp = client.post(f"/trips/{trip.id}/ignore-weather")
    assert ignore_resp.status_code == 200
    assert ignore_resp.json()["status"] == "ignored"

    # After ignoring: status is ignored, no advisories returned
    resp_after = client.get(f"/trips/{trip.id}/weather-advisories")
    assert resp_after.status_code == 200
    data_after = resp_after.json()
    assert data_after["status"] == "ignored"
    assert data_after["advisories"] == []


@pytest.mark.anyio
async def test_cached_weather_service_ttl():
    mock_provider = MockWeatherProvider(
        [
            NormalizedDailyForecast(
                date=date(2026, 8, 25),
                temperature_max=30.0,
                temperature_min=20.0,
                apparent_temperature_max=30.0,
                apparent_temperature_min=20.0,
                precipitation_sum_mm=0.0,
                precipitation_probability_max=0.0,
                wind_speed_max_kmh=10.0,
                wind_gusts_max_kmh=15.0,
                hourly=(),
            )
        ]
    )
    cached = CachedWeatherService(mock_provider, ttl_minutes=60)

    res1 = await cached.get_forecast(26.91, 75.78, date(2026, 8, 25), date(2026, 8, 25))
    assert res1 is not None
    assert mock_provider.call_count == 1

    # Second call uses in-memory cache
    res2 = await cached.get_forecast(26.91, 75.78, date(2026, 8, 25), date(2026, 8, 25))
    assert res2 == res1
    assert mock_provider.call_count == 1
