"""API request and response schemas."""

from app.schemas.city import (
    CityCreate,
    CityRead,
    CityResolve,
    GoogleCitySuggestion,
    GooglePlaceDetails,
)
from app.schemas.place import GoogleNearbyPlace, PlaceCreate, PlaceRead
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
from app.schemas.route_optimization import (
    OptimizedPlaceRead,
    RouteOptimizationRead,
)

__all__ = [
    "CityCreate",
    "CityRead",
    "CityResolve",
    "GoogleCitySuggestion",
    "GooglePlaceDetails",
    "GoogleNearbyPlace",
    "PlaceCreate",
    "PlaceRead",
    "DiscoveryCategory",
    "RecommendationRead",
    "RecommendationRequest",
    "SavedPlaceCreate",
    "SavedPlaceUpdate",
    "SavedPlaceOrder",
    "SavedPlaceRead",
    "SavedPlaceReorder",
    "OptimizedPlaceRead",
    "RouteOptimizationRead",
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
]
