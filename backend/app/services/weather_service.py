"""Provider-neutral weather forecasting service and Open-Meteo adapter.

Fetches only required variables (temperature, apparent temperature, precipitation,
precipitation probability, weather code, wind speed, and wind gusts) for
itinerary advisory generation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
import logging
from typing import Protocol

import httpx

from app.core.config import get_settings
from app.core.weather_constants import MAX_FORECAST_HORIZON_DAYS

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class NormalizedHourlyForecast:
    timestamp: datetime
    temperature: float
    apparent_temperature: float
    precipitation_probability: float
    precipitation_mm: float
    weather_code: int
    wind_speed_kmh: float
    wind_gusts_kmh: float


@dataclass(frozen=True, slots=True)
class NormalizedDailyForecast:
    date: date
    temperature_max: float
    temperature_min: float
    apparent_temperature_max: float
    apparent_temperature_min: float
    precipitation_sum_mm: float
    precipitation_probability_max: float
    wind_speed_max_kmh: float
    wind_gusts_max_kmh: float
    hourly: tuple[NormalizedHourlyForecast, ...] = field(default_factory=tuple)


class WeatherProvider(Protocol):
    """Provider-neutral interface for weather forecasting."""

    async def get_forecast(
        self,
        latitude: float,
        longitude: float,
        start_date: date,
        end_date: date,
    ) -> list[NormalizedDailyForecast] | None:
        """Fetch normalized daily and hourly forecasts for the coordinate and date range.

        Returns None if forecast is unavailable (e.g. outside horizon, provider offline).
        """
        ...


class OpenMeteoWeatherProvider:
    """Open-Meteo API implementation of WeatherProvider.

    Licensing & Usage note:
    The hosted free endpoint (https://api.open-meteo.com) has non-commercial restrictions
    and requires CC BY 4.0 attribution. For commercial production, a commercial plan
    customer endpoint or self-hosted Open-Meteo container must be configured.
    """

    def __init__(
        self,
        base_url: str | None = None,
        timeout_seconds: float | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        settings = get_settings()
        self._base_url = (base_url or settings.open_meteo_base_url).rstrip("/")
        self._timeout_seconds = timeout_seconds or settings.open_meteo_timeout_seconds
        self._client = client

    async def get_forecast(
        self,
        latitude: float,
        longitude: float,
        start_date: date,
        end_date: date,
    ) -> list[NormalizedDailyForecast] | None:
        today = datetime.now(timezone.utc).date()
        # Horizon check: standard public Open-Meteo provides up to 16 days forward
        if end_date < today or start_date > today + timedelta(days=MAX_FORECAST_HORIZON_DAYS):
            logger.info(
                "Requested dates %s to %s outside forecast horizon (today: %s)",
                start_date,
                end_date,
                today,
            )
            return None

        url = f"{self._base_url}/v1/forecast"
        params = {
            "latitude": f"{latitude:.4f}",
            "longitude": f"{longitude:.4f}",
            "hourly": (
                "temperature_2m,apparent_temperature,precipitation_probability,"
                "precipitation,weather_code,wind_speed_10m,wind_gusts_10m"
            ),
            "daily": (
                "weather_code,temperature_2m_max,temperature_2m_min,"
                "apparent_temperature_max,apparent_temperature_min,"
                "precipitation_sum,precipitation_probability_max,"
                "wind_speed_10m_max,wind_gusts_10m_max"
            ),
            "timezone": "auto",
        }

        try:
            if self._client is not None:
                response = await self._client.get(
                    url, params=params, timeout=self._timeout_seconds
                )
            else:
                async with httpx.AsyncClient() as client:
                    response = await client.get(
                        url, params=params, timeout=self._timeout_seconds
                    )

            if response.status_code != 200:
                logger.warning(
                    "Open-Meteo returned status %d: %s",
                    response.status_code,
                    response.text[:200],
                )
                return None

            data = response.json()
            return self._normalize_response(data, start_date, end_date)

        except (httpx.TimeoutException, httpx.RequestError) as exc:
            logger.warning("Open-Meteo request error: %s", exc)
            return None
        except Exception as exc:
            logger.error("Unexpected error parsing Open-Meteo response: %s", exc)
            return None

    def _normalize_response(
        self,
        data: dict,
        start_date: date,
        end_date: date,
    ) -> list[NormalizedDailyForecast] | None:
        daily_raw = data.get("daily")
        hourly_raw = data.get("hourly")
        if not daily_raw or not hourly_raw:
            return None

        daily_times = daily_raw.get("time", [])
        if not daily_times:
            return None

        # Parse hourly by date
        hourly_by_date: dict[date, list[NormalizedHourlyForecast]] = {}
        hourly_times = hourly_raw.get("time", [])
        temp_list = hourly_raw.get("temperature_2m", [])
        app_temp_list = hourly_raw.get("apparent_temperature", [])
        precip_prob_list = hourly_raw.get("precipitation_probability", [])
        precip_list = hourly_raw.get("precipitation", [])
        weather_code_list = hourly_raw.get("weather_code", [])
        wind_speed_list = hourly_raw.get("wind_speed_10m", [])
        wind_gust_list = hourly_raw.get("wind_gusts_10m", [])

        for idx, t_str in enumerate(hourly_times):
            try:
                # Open-Meteo format: "2026-08-25T14:00"
                dt = datetime.fromisoformat(t_str)
                d = dt.date()
                if start_date <= d <= end_date:
                    if d not in hourly_by_date:
                        hourly_by_date[d] = []
                    hourly_by_date[d].append(
                        NormalizedHourlyForecast(
                            timestamp=dt,
                            temperature=float(temp_list[idx]) if idx < len(temp_list) and temp_list[idx] is not None else 0.0,
                            apparent_temperature=float(app_temp_list[idx]) if idx < len(app_temp_list) and app_temp_list[idx] is not None else 0.0,
                            precipitation_probability=float(precip_prob_list[idx]) if idx < len(precip_prob_list) and precip_prob_list[idx] is not None else 0.0,
                            precipitation_mm=float(precip_list[idx]) if idx < len(precip_list) and precip_list[idx] is not None else 0.0,
                            weather_code=int(weather_code_list[idx]) if idx < len(weather_code_list) and weather_code_list[idx] is not None else 0,
                            wind_speed_kmh=float(wind_speed_list[idx]) if idx < len(wind_speed_list) and wind_speed_list[idx] is not None else 0.0,
                            wind_gusts_kmh=float(wind_gust_list[idx]) if idx < len(wind_gust_list) and wind_gust_list[idx] is not None else 0.0,
                        )
                    )
            except (ValueError, TypeError) as parse_err:
                logger.debug("Failed parsing hourly timestamp %s: %s", t_str, parse_err)

        daily_results: list[NormalizedDailyForecast] = []
        for idx, date_str in enumerate(daily_times):
            try:
                d = date.fromisoformat(date_str)
                if start_date <= d <= end_date:
                    day_hourly = tuple(hourly_by_date.get(d, []))
                    daily_results.append(
                        NormalizedDailyForecast(
                            date=d,
                            temperature_max=float(daily_raw["temperature_2m_max"][idx]),
                            temperature_min=float(daily_raw["temperature_2m_min"][idx]),
                            apparent_temperature_max=float(daily_raw["apparent_temperature_max"][idx]),
                            apparent_temperature_min=float(daily_raw["apparent_temperature_min"][idx]),
                            precipitation_sum_mm=float(daily_raw["precipitation_sum"][idx]),
                            precipitation_probability_max=float(daily_raw["precipitation_probability_max"][idx]),
                            wind_speed_max_kmh=float(daily_raw["wind_speed_10m_max"][idx]),
                            wind_gusts_max_kmh=float(daily_raw["wind_gusts_10m_max"][idx]),
                            hourly=day_hourly,
                        )
                    )
            except (ValueError, KeyError, IndexError) as err:
                logger.debug("Failed parsing daily forecast row %s: %s", date_str, err)

        return daily_results if daily_results else None


class CachedWeatherService:
    """Wrapper around WeatherProvider with in-memory TTL caching."""

    def __init__(
        self,
        provider: WeatherProvider,
        ttl_minutes: int | None = None,
    ) -> None:
        self._provider = provider
        settings = get_settings()
        self._ttl = timedelta(minutes=ttl_minutes or settings.weather_cache_ttl_minutes)
        self._cache: dict[str, tuple[datetime, list[NormalizedDailyForecast] | None]] = {}

    def _cache_key(
        self, latitude: float, longitude: float, start_date: date, end_date: date
    ) -> str:
        return f"{latitude:.2f}:{longitude:.2f}:{start_date.isoformat()}:{end_date.isoformat()}"

    async def get_forecast(
        self,
        latitude: float,
        longitude: float,
        start_date: date,
        end_date: date,
    ) -> list[NormalizedDailyForecast] | None:
        now = datetime.now(timezone.utc)
        key = self._cache_key(latitude, longitude, start_date, end_date)

        cached = self._cache.get(key)
        if cached is not None:
            expires_at, result = cached
            if now < expires_at:
                return result

        result = await self._provider.get_forecast(
            latitude, longitude, start_date, end_date
        )
        # Cache successful results and non-transient horizon misses for TTL
        self._cache[key] = (now + self._ttl, result)
        return result

    def clear_cache(self) -> None:
        self._cache.clear()
