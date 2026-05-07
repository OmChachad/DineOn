from __future__ import annotations

from typing import Any

from models import MealSuggestion, SuggestionsRequest, SuggestionsResponse
from pipeline.openai_client import OpenAIClient, SYNTHESIZER_MODEL


class NutritionSuggestionsEngine:
    def __init__(self, openai_client: OpenAIClient) -> None:
        self.openai_client = openai_client

    async def generate(self, request: SuggestionsRequest) -> SuggestionsResponse:
        schema = {
            "type": "object",
            "additionalProperties": False,
            "required": ["meals", "summary", "warnings"],
            "properties": {
                "meals": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "additionalProperties": False,
                        "required": [
                            "meal",
                            "meal_key",
                            "venue",
                            "items",
                            "estimated_calories",
                            "estimated_protein_g",
                            "estimated_carbs_g",
                            "estimated_fat_g",
                            "rationale",
                            "optional_caution",
                        ],
                        "properties": {
                            "meal": {"type": "string"},
                            "meal_key": {"type": "string"},
                            "venue": {"type": "string"},
                            "items": {"type": "array", "items": {"type": "string"}},
                            "estimated_calories": {"type": ["integer", "null"]},
                            "estimated_protein_g": {"type": ["integer", "null"]},
                            "estimated_carbs_g": {"type": ["integer", "null"]},
                            "estimated_fat_g": {"type": ["integer", "null"]},
                            "rationale": {"type": "string"},
                            "optional_caution": {"type": ["string", "null"]},
                        },
                    },
                },
                "summary": {"type": "string"},
                "warnings": {"type": "array", "items": {"type": "string"}},
            },
        }
        instructions = """
You are choosing exactly what a user should eat at USC dining halls for the requested date.
Return JSON only.

Rules:
- Use only meal slots from `meal_slots`.
- Use only venue names and item names that appear verbatim in `menu_export`.
- Recommend at most one structured suggestion per meal slot.
- Optimize for the nutrition profile when present, especially daily calories and macros.
- If no nutrition profile is present, do a best-effort plan using favorites, dietary filters, exclusions, and reasonable balance.
- Favorites are a strong positive signal and may outweigh softer preference phrasing such as "preferably no" when the overall day still looks reasonable.
- Prefer realistic, easy-to-find plates over complicated combinations.
- Estimated calories and macros should be reasonable approximations, not blank unless genuinely unknowable.
- Keep the summary to 2-3 sentences in plain English.
- Warnings should be short and only included when they help the user avoid a poor fit.
""".strip()
        payload: dict[str, Any] = {
            "date": request.date,
            "meal_slots": request.meal_slots,
            "preferences": request.preferences.model_dump(mode="json"),
            "nutrition_profile": request.nutrition_profile.model_dump(mode="json") if request.nutrition_profile else None,
            "healthkit": request.healthkit.model_dump(mode="json"),
            "client_context": request.client_context.model_dump(mode="json"),
            "menu_export": request.menu_export,
        }
        raw_response = await self.openai_client.generate_json(
            model=SYNTHESIZER_MODEL,
            schema_name="nutrition_suggestions_response",
            schema=schema,
            instructions=instructions,
            payload=payload,
            max_output_tokens=1400,
        )

        response = SuggestionsResponse.model_validate(
            {
                "schema_version": 1,
                "date": request.date,
                "daily_calorie_target": request.nutrition_profile.daily_calories if request.nutrition_profile else None,
                "active_calories_today": (
                    round(request.healthkit.active_calories_today)
                    if request.healthkit.active_calories_today is not None
                    else None
                ),
                "meals": raw_response["meals"],
                "summary": raw_response["summary"],
                "warnings": raw_response["warnings"],
            }
        )
        return self._normalized_response(response, meal_slots=request.meal_slots)

    def _normalized_response(
        self,
        response: SuggestionsResponse,
        *,
        meal_slots: list[str],
    ) -> SuggestionsResponse:
        allowed = {slot.casefold(): slot for slot in meal_slots}
        ordered_meals: list[MealSuggestion] = []
        seen: set[str] = set()

        for suggestion in response.meals:
            key = suggestion.meal_key.casefold()
            meal_name = suggestion.meal.casefold()
            matched_slot = allowed.get(key) or allowed.get(meal_name)
            if matched_slot is None or matched_slot.casefold() in seen:
                continue

            seen.add(matched_slot.casefold())
            ordered_meals.append(
                suggestion.model_copy(
                    update={
                        "meal": matched_slot,
                        "meal_key": matched_slot,
                    }
                )
            )

        ordered_meals.sort(key=lambda suggestion: meal_slots.index(suggestion.meal))
        return response.model_copy(update={"meals": ordered_meals})
