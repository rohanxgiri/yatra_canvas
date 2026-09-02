"""Centralized weather advisory constants, conditions, and thresholds.

Initial thresholds represent product design heuristics for tourist comfort
and safety awareness, not meteorological or official safety guarantees.
"""

from enum import StrEnum
from typing import Final


class WeatherCondition(StrEnum):
    NORMAL = "normal"
    HOT = "hot"
    VERY_HOT = "very_hot"
    COLD = "cold"
    VERY_COLD = "very_cold"
    HEAVY_RAIN = "heavy_rain"
    STORM = "storm"
    HIGH_WIND = "high_wind"


class AdvisorySeverity(StrEnum):
    INFO = "info"
    ADVISORY = "advisory"
    WARNING = "warning"


# --- Duration & Overlap Thresholds ---
# Minimum consecutive hours an adverse condition must persist to trigger an advisory.
MIN_ADVERSE_DURATION_HOURS: Final[int] = 2

# --- Temperature Thresholds (Apparent Temperature in Celsius) ---
# Apparent temperature (heat index / wind chill) accounts for humidity and wind.
VERY_HOT_APPARENT_TEMP_C: Final[float] = 42.0
HOT_APPARENT_TEMP_C: Final[float] = 38.0
COLD_APPARENT_TEMP_C: Final[float] = 8.0
VERY_COLD_APPARENT_TEMP_C: Final[float] = 3.0

# --- Precipitation Thresholds ---
# Rain rate in mm/hr for heavy rain.
HEAVY_RAIN_MM_PER_HOUR: Final[float] = 7.5
MODERATE_RAIN_MM_PER_HOUR: Final[float] = 4.0
HIGH_PRECIPITATION_PROBABILITY_PCT: Final[float] = 80.0

# --- Wind Thresholds (km/h) ---
HIGH_WIND_SPEED_KMH: Final[float] = 40.0
HIGH_WIND_GUST_KMH: Final[float] = 55.0
STORM_WIND_GUST_KMH: Final[float] = 65.0

# --- WMO Weather Codes for Storm / Thunderstorm ---
# Open-Meteo uses WMO 4677 weather interpretation codes:
# 95: Thunderstorm (slight or moderate)
# 96: Thunderstorm with slight hail
# 99: Thunderstorm with heavy hail
STORM_WEATHER_CODES: Final[frozenset[int]] = frozenset({95, 96, 99})

# Heavy precipitation WMO codes:
# 65: Rain: Heavy intensity
# 67: Freezing Rain: Heavy intensity
# 75: Snow fall: Heavy intensity
# 82: Rain showers: Violent
HEAVY_PRECIPITATION_WMO_CODES: Final[frozenset[int]] = frozenset({65, 67, 75, 82})

# --- Fallback Planning Touring Windows ---
# Standard daytime touring window (09:00 - 18:00) used when exact per-place
# arrival/departure times are not explicitly recorded on the itinerary.
DEFAULT_PLANNING_WINDOW_START_HOUR: Final[int] = 9
DEFAULT_PLANNING_WINDOW_END_HOUR: Final[int] = 18

# Sub-windows for scheduling/rearranging:
MORNING_WINDOW_START_HOUR: Final[int] = 9
MORNING_WINDOW_END_HOUR: Final[int] = 12
AFTERNOON_WINDOW_START_HOUR: Final[int] = 12
AFTERNOON_WINDOW_END_HOUR: Final[int] = 16
LATE_AFTERNOON_WINDOW_START_HOUR: Final[int] = 16
LATE_AFTERNOON_WINDOW_END_HOUR: Final[int] = 19

# Forecast horizon for standard Open-Meteo public endpoints (days)
MAX_FORECAST_HORIZON_DAYS: Final[int] = 16
