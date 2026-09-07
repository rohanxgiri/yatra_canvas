"""API request and response schemas."""

from app.schemas.city import (
    CityCreate,
    CityDetails,
    CityRead,
    CityResolve,
    CitySuggestion,
)
from app.schemas.place import (
    GoogleNearbyPlace,
    OpeningHoursInterval,
    PlaceCreate,
    PlacePrefetchRequest,
    PlacePrefetchResponse,
    PlaceRead,
    PlaceResolveRequest,
    PlaceSearchResult,
)
from app.schemas.location import (
    LocationAutocompleteResponse,
    LocationAutocompleteResult,
)
from app.schemas.recommendation import (
    DiscoveryCategory,
    RecommendationRead,
    RecommendationRequest,
)
from app.schemas.saved_place import (
    AssignmentMode,
    SavedPlaceCreate,
    SavedPlaceUpdate,
    SavedPlaceOrder,
    SavedPlaceRead,
    SavedPlaceReorder,
)
from app.schemas.trip import (
    LocationDetails,
    LocationSuggestion,
    StartLocationType,
    TripCreate,
    TripRead,
    TripStartLocationRead,
    TripStartLocationUpdate,
    TripUpdate,
)
from app.schemas.trip_day import (
    DayType,
    TripDayRead,
    TripDayUpdate,
)
from app.schemas.route_optimization import (
    ItineraryBreakRead,
    OptimizedPlaceRead,
    RouteOptimizationRead,
)
from app.schemas.route_geometry import (
    DayRouteGeometryRead,
    RouteLegGeometryRead,
    TripRouteGeometryRead,
)
from app.schemas.smart_replanning import (
    ItineraryStopStatus,
    ItineraryStopStatusUpdate,
    MoveItineraryPlaceRequest,
    MoveItineraryPlaceResponse,
    MovedPlaceRead,
    TripReplanImpactRead,
    TripReplanPreviewRead,
)

from app.schemas.weather_advisory import (
    ApplyRearrangementRequest,
    DayRearrangePreviewRead,
    PlaceAlternativeRead,
    ProposedStopRead,
    RearrangePreviewRequest,
    TripWeatherAdvisoriesRead,
    WeatherAdvisoryRead,
)

__all__ = [
    "CityCreate",
    "CityDetails",
    "CityRead",
    "CityResolve",
    "CitySuggestion",
    "GoogleNearbyPlace",
    "OpeningHoursInterval",
    "PlaceCreate",
    "PlaceRead",
    "PlaceResolveRequest",
    "PlaceSearchResult",
    "DiscoveryCategory",
    "RecommendationRead",
    "RecommendationRequest",
    "AssignmentMode",
    "SavedPlaceCreate",
    "SavedPlaceUpdate",
    "SavedPlaceOrder",
    "SavedPlaceRead",
    "SavedPlaceReorder",
    "ItineraryBreakRead",
    "OptimizedPlaceRead",
    "RouteOptimizationRead",
    "ItineraryStopStatus",
    "ItineraryStopStatusUpdate",
    "MoveItineraryPlaceRequest",
    "MoveItineraryPlaceResponse",
    "MovedPlaceRead",
    "TripReplanImpactRead",
    "TripReplanPreviewRead",

    "DayRouteGeometryRead",
    "RouteLegGeometryRead",
    "TripRouteGeometryRead",
    "LocationDetails",
    "LocationSuggestion",
    "LocationAutocompleteResponse",
    "LocationAutocompleteResult",
    "StartLocationType",
    "TripCreate",
    "TripRead",
    "TripStartLocationRead",
    "TripStartLocationUpdate",
    "TripUpdate",
    "DayType",
    "TripDayRead",
    "TripDayUpdate",
    "WeatherAdvisoryRead",
    "TripWeatherAdvisoriesRead",
    "PlaceAlternativeRead",
    "ProposedStopRead",
    "DayRearrangePreviewRead",
    "ApplyRearrangementRequest",
    "RearrangePreviewRequest",
]
