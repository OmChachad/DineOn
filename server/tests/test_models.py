import pytest

from models import MAX_PREFERENCE_NOTE_LENGTH, NutritionProfileRequest, SuggestionsRequest


def test_request_trims_blank_notes() -> None:
    request = NutritionProfileRequest.model_validate(
        {
            "schema_version": 1,
            "preference_notes": ["  Want more energy  ", "   ", "\nVegetarian meals\n"],
            "healthkit": {},
        }
    )

    assert request.preference_notes == ["Want more energy", "Vegetarian meals"]


def test_request_rejects_long_notes() -> None:
    with pytest.raises(ValueError):
        NutritionProfileRequest.model_validate(
            {
                "schema_version": 1,
                "preference_notes": ["x" * (MAX_PREFERENCE_NOTE_LENGTH + 1)],
                "healthkit": {},
            }
        )


def test_suggestions_request_allows_missing_nutrition_profile() -> None:
    request = SuggestionsRequest.model_validate(
        {
            "schema_version": 1,
            "date": "2026-05-06",
            "meal_slots": ["Lunch", "Dinner"],
            "preferences": {},
            "nutrition_profile": None,
            "healthkit": {},
            "menu_export": "Visible Dining Suggestions for 2026-05-06",
            "client_context": {},
        }
    )

    assert request.nutrition_profile is None
    assert request.meal_slots == ["Lunch", "Dinner"]
