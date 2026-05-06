from models import NutritionIntent, NutritionProfileRequest, NutritionProfileResponse
from pipeline.safety import apply_safety_checks


def make_response(**overrides) -> NutritionProfileResponse:
    payload = {
        "schema_version": 1,
        "generated_at": "2026-05-06T20:15:00Z",
        "daily_calories": 1100,
        "protein_g": 100,
        "carbs_g": 140,
        "fat_g": 45,
        "calorie_rationale": "Initial rationale",
        "meal_pattern": "3 meals",
        "foods_to_prioritize": ["lentils"],
        "foods_to_avoid": ["soda"],
        "watch_nutrients": ["iron"],
        "sleep_note": "Sleep note",
        "summary": "Summary",
        "sources": ["Dietary_Guidelines_For_Americans.md"],
        "warnings": [],
    }
    payload.update(overrides)
    return NutritionProfileResponse.model_validate(payload)


def test_safety_applies_female_floor() -> None:
    profile = make_response(daily_calories=1100)
    request = NutritionProfileRequest.model_validate(
        {"schema_version": 1, "preference_notes": ["Lose weight"], "healthkit": {"sex": "female", "tdee": 1900, "weight_kg": 78}}
    )
    intent = NutritionIntent(
        primary_goal="weight_loss",
        secondary_goals=[],
        dietary_restrictions=[],
        special_flags=[],
        medical_flags=[],
        rag_query_hints=["weight loss"],
    )

    checked = apply_safety_checks(profile=profile, request=request, intent=intent)

    assert checked.daily_calories == 1200
    assert any("1,200 kcal" in warning for warning in checked.warnings)


def test_safety_redacts_eating_disorder_risk() -> None:
    profile = make_response()
    request = NutritionProfileRequest.model_validate(
        {"schema_version": 1, "preference_notes": ["I want to starve myself"], "healthkit": {}}
    )
    intent = NutritionIntent(
        primary_goal="weight_loss",
        secondary_goals=[],
        dietary_restrictions=[],
        special_flags=["eating_disorder_risk"],
        medical_flags=[],
        rag_query_hints=["weight loss"],
    )

    checked = apply_safety_checks(profile=profile, request=request, intent=intent)

    assert checked.daily_calories is None
    assert checked.protein_g is None
    assert "withheld" in " ".join(checked.warnings).lower()
