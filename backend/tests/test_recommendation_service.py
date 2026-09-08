"""Focused tests for the explainable recommendation score."""

from uuid import uuid4

from app.models import Place
from app.services.recommendation_service import (
    calculate_recommendation_score,
)


def make_place(
    *,
    rating: float,
    review_count: int,
    is_popular: bool = False,
    is_heritage: bool = False,
    is_local_speciality: bool = False,
) -> Place:
    return Place(
        city_id=uuid4(),
        name="Test place",
        category="food",
        latitude=23.0,
        longitude=75.0,
        rating=rating,
        review_count=review_count,
        is_popular=is_popular,
        is_heritage=is_heritage,
        is_local_speciality=is_local_speciality,
    )


def test_review_confidence_can_outweigh_a_small_rating_difference() -> None:
    high_rating_low_reviews = make_place(rating=4.9, review_count=20)
    proven_rating = make_place(rating=4.6, review_count=20000)

    low_confidence_score = calculate_recommendation_score(
        high_rating_low_reviews,
        matched_category_count=1,
        selected_category_count=1,
    )
    proven_score = calculate_recommendation_score(
        proven_rating,
        matched_category_count=1,
        selected_category_count=1,
    )

    assert proven_score > low_confidence_score


def test_score_uses_all_boolean_bonuses_and_is_capped_at_100() -> None:
    place = make_place(
        rating=5.0,
        review_count=20000,
        is_popular=True,
        is_heritage=True,
        is_local_speciality=True,
    )

    assert (
        calculate_recommendation_score(
            place,
            matched_category_count=3,
            selected_category_count=3,
        )
        == 100.0
    )


def test_known_trip_start_adds_bounded_proximity_signal() -> None:
    place = make_place(rating=4.0, review_count=100)

    nearby = calculate_recommendation_score(place, distance_from_city_km=1.0)
    distant = calculate_recommendation_score(place, distance_from_city_km=30.0)

    assert nearby > distant
    assert nearby - distant <= 8.0
