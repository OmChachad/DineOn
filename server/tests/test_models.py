import pytest

from models import MAX_PREFERENCE_NOTE_LENGTH, NutritionProfileRequest


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
