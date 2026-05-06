from __future__ import annotations

from models import NutritionIntent, NutritionProfileRequest, NutritionProfileResponse


def apply_safety_checks(
    *,
    profile: NutritionProfileResponse,
    request: NutritionProfileRequest,
    intent: NutritionIntent,
) -> NutritionProfileResponse:
    warnings = list(profile.warnings)
    summary = profile.summary.strip()
    calorie_rationale = profile.calorie_rationale

    if "eating_disorder_risk" in intent.special_flags:
        referral = (
            "Your notes suggest you may need more individualized support. "
            "DineOn will avoid calorie targets here and recommend talking with a qualified clinician."
        )
        warnings.append("Calorie and macro targets were withheld because the notes may indicate eating-disorder risk.")
        summary = referral
        calorie_rationale = referral
        profile = profile.model_copy(
            update={
                "daily_calories": None,
                "protein_g": None,
                "carbs_g": None,
                "fat_g": None,
                "meal_pattern": "Focus on regular meals and clinician-guided support.",
                "summary": summary,
                "calorie_rationale": calorie_rationale,
            }
        )

    floor_warning: str | None = None
    if profile.daily_calories is not None:
        sex = request.healthkit.sex
        if sex == "female" and profile.daily_calories < 1200:
            profile = profile.model_copy(update={"daily_calories": 1200})
            floor_warning = "Daily calories were raised to 1,200 kcal as a conservative minimum for female profiles."
        elif sex == "male" and profile.daily_calories < 1500:
            profile = profile.model_copy(update={"daily_calories": 1500})
            floor_warning = "Daily calories were raised to 1,500 kcal as a conservative minimum for male profiles."
        elif sex in {None, "unknown", "other"} and profile.daily_calories < 1200:
            floor_warning = (
                "Daily calories look unusually low, and sex was unavailable or non-binary, so no automatic floor was applied."
            )
    if floor_warning:
        warnings.append(floor_warning)

    if (
        profile.daily_calories is not None
        and request.healthkit.tdee is not None
        and request.healthkit.weight_kg is not None
        and profile.daily_calories < request.healthkit.tdee
    ):
        weekly_loss_kg = ((request.healthkit.tdee - profile.daily_calories) * 7) / 7700
        if request.healthkit.weight_kg > 0 and (weekly_loss_kg / request.healthkit.weight_kg) > 0.01:
            warnings.append(
                "This calorie target may imply weight loss faster than 1% of body weight per week."
            )

    if intent.medical_flags:
        consult_message = "Consult your doctor or dietitian before using these targets as medical nutrition advice."
        warnings.append(consult_message)
        if consult_message not in summary:
            summary = f"{summary} {consult_message}".strip()

    return profile.model_copy(
        update={
            "summary": summary,
            "warnings": _dedupe_list(warnings),
            "sources": _dedupe_list(profile.sources),
        }
    )


def _dedupe_list(items: list[str]) -> list[str]:
    output: list[str] = []
    seen: set[str] = set()
    for item in items:
        key = item.casefold()
        if key not in seen:
            seen.add(key)
            output.append(item)
    return output

