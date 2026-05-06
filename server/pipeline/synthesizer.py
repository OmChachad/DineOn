from __future__ import annotations

from typing import Any

from models import NutritionProfileRequest, NutritionProfileResponse, RetrievalPayload
from pipeline.openai_client import OpenAIClient, SYNTHESIZER_MODEL


class NutritionSynthesizer:
    def __init__(self, openai_client: OpenAIClient) -> None:
        self.openai_client = openai_client

    async def synthesize(
        self,
        *,
        request: NutritionProfileRequest,
        retrieval: RetrievalPayload,
    ) -> NutritionProfileResponse:
        schema = {
            "type": "object",
            "additionalProperties": False,
            "required": [
                "daily_calories",
                "protein_g",
                "carbs_g",
                "fat_g",
                "calorie_rationale",
                "meal_pattern",
                "foods_to_prioritize",
                "foods_to_avoid",
                "watch_nutrients",
                "sleep_note",
                "summary",
                "sources",
                "warnings",
            ],
            "properties": {
                "daily_calories": {"type": ["integer", "null"]},
                "protein_g": {"type": ["integer", "null"]},
                "carbs_g": {"type": ["integer", "null"]},
                "fat_g": {"type": ["integer", "null"]},
                "calorie_rationale": {"type": "string"},
                "meal_pattern": {"type": "string"},
                "foods_to_prioritize": {"type": "array", "items": {"type": "string"}},
                "foods_to_avoid": {"type": "array", "items": {"type": "string"}},
                "watch_nutrients": {"type": "array", "items": {"type": "string"}},
                "sleep_note": {"type": "string"},
                "summary": {"type": "string"},
                "sources": {"type": "array", "items": {"type": "string"}},
                "warnings": {"type": "array", "items": {"type": "string"}},
            },
        }
        instructions = """
You are generating a nutrition profile that will later drive meal recommendations.
Return JSON only.

Use the structured serving rows as the primary numeric anchor for calorie-band servings.
Use the narrative evidence to justify foods, nutrient watchouts, and behavior notes.
Treat the highest-scoring, most specific evidence as more important than generic life-stage or introductory text.
Keep the summary to 3-4 sentences in plain English.
Prefer realistic guidance over aggressive targets.
Only cite sources that are present in the supplied evidence.
""".strip()
        payload: dict[str, Any] = {
            "request": self._compact_request(request),
            "intent": retrieval.intent.model_dump(mode="json"),
            "provisional_calorie_target": retrieval.provisional_calorie_target,
            "serving_rows": [self._compact_serving_row(row) for row in retrieval.serving_rows],
            "narrative_evidence": [self._compact_chunk(chunk) for chunk in retrieval.narrative_chunks],
        }
        response = await self.openai_client.generate_json(
            model=SYNTHESIZER_MODEL,
            schema_name="nutrition_profile_response",
            schema=schema,
            instructions=instructions,
            payload=payload,
            max_output_tokens=900,
        )
        return NutritionProfileResponse.model_validate(response)

    def _compact_request(self, request: NutritionProfileRequest) -> dict[str, Any]:
        healthkit = {
            key: value
            for key, value in request.healthkit.model_dump(mode="json").items()
            if value is not None
        }
        return {
            "schema_version": request.schema_version,
            "preference_notes": request.preference_notes,
            "healthkit": healthkit,
        }

    def _compact_serving_row(self, row: Any) -> dict[str, Any]:
        return {
            "source": f"Daily Servings By Calorie Level - {row.calorie_level} kcal",
            "calorie_level": row.calorie_level,
            "protein_servings": [row.protein_servings_min, row.protein_servings_max],
            "dairy_servings": row.dairy_servings,
            "vegetable_servings": row.vegetable_servings,
            "fruit_servings": row.fruit_servings,
            "whole_grains": [row.whole_grains_min, row.whole_grains_max],
            "healthy_fats": row.healthy_fats,
        }

    def _compact_chunk(self, chunk: Any) -> dict[str, Any]:
        text = " ".join(chunk.text.split())
        if len(text) > 900:
            text = f"{text[:897].rstrip()}..."
        return {
            "source": f"{chunk.source_file} - {chunk.heading_path}",
            "evidence": text,
        }
