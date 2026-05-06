from __future__ import annotations

from typing import Any

from models import NutritionIntent, NutritionProfileRequest
from pipeline.openai_client import CLASSIFIER_MODEL, OpenAIClient

MEDICAL_KEYWORDS = {
    "diabetes",
    "prediabetes",
    "pcos",
    "hypertension",
    "blood pressure",
    "anemia",
    "thyroid",
    "crohn",
    "celiac",
    "ibs",
}

EATING_DISORDER_KEYWORDS = {
    "starve",
    "stop eating",
    "eat nothing",
    "purge",
    "binge",
    "anorexia",
    "bulimia",
    "unsafe weight loss",
}


class NutritionClassifier:
    def __init__(self, openai_client: OpenAIClient) -> None:
        self.openai_client = openai_client

    async def classify(self, request: NutritionProfileRequest) -> NutritionIntent:
        schema = {
            "type": "object",
            "additionalProperties": False,
            "required": [
                "primary_goal",
                "secondary_goals",
                "dietary_restrictions",
                "special_flags",
                "medical_flags",
                "rag_query_hints",
            ],
            "properties": {
                "primary_goal": {"type": "string"},
                "secondary_goals": {"type": "array", "items": {"type": "string"}},
                "dietary_restrictions": {"type": "array", "items": {"type": "string"}},
                "special_flags": {"type": "array", "items": {"type": "string"}},
                "medical_flags": {"type": "array", "items": {"type": "string"}},
                "rag_query_hints": {
                    "type": "array",
                    "minItems": 1,
                    "maxItems": 4,
                    "items": {"type": "string"},
                },
            },
        }
        instructions = """
You are a nutrition intent classifier for a meal-planning system.
Return JSON only.

Normalize the user's free-form notes into:
- primary_goal: concise snake_case label such as weight_loss, maintenance, muscle_gain, energy_improvement, gut_health, blood_sugar_support
- secondary_goals: additional snake_case goals
- dietary_restrictions: explicit food pattern or exclusions from the notes only
- special_flags: behavioral or context flags such as low_sleep, low_activity, eating_disorder_risk
- medical_flags: only if the note explicitly mentions a medical condition
- rag_query_hints: 2-4 short search-ready nutrition retrieval hints grounded in the notes and health data

Do not mention menu filters or dining halls.
Prefer conservative, clinically neutral labels.
""".strip()
        payload: dict[str, Any] = {
            "preference_notes": request.preference_notes,
            "healthkit": request.healthkit.model_dump(mode="json"),
        }
        response = await self.openai_client.generate_json(
            model=CLASSIFIER_MODEL,
            schema_name="nutrition_intent",
            schema=schema,
            instructions=instructions,
            payload=payload,
            max_output_tokens=600,
        )
        intent = NutritionIntent.model_validate(response)
        return self._augment_intent(intent, request.preference_notes)

    def _augment_intent(self, intent: NutritionIntent, notes: list[str]) -> NutritionIntent:
        lower_notes = " ".join(notes).casefold()
        special_flags = list(intent.special_flags)
        medical_flags = list(intent.medical_flags)

        if any(keyword in lower_notes for keyword in EATING_DISORDER_KEYWORDS):
            special_flags.append("eating_disorder_risk")
        if any(keyword in lower_notes for keyword in MEDICAL_KEYWORDS):
            medical_flags.append("medical_condition_mentioned")
        if "sleep" in lower_notes and "tired" in lower_notes and "low_sleep" not in special_flags:
            special_flags.append("low_sleep")

        normalized = NutritionIntent(
            primary_goal=intent.primary_goal,
            secondary_goals=list(dict.fromkeys(intent.secondary_goals)),
            dietary_restrictions=list(dict.fromkeys(intent.dietary_restrictions)),
            special_flags=list(dict.fromkeys(special_flags)),
            medical_flags=list(dict.fromkeys(medical_flags)),
            rag_query_hints=list(dict.fromkeys(intent.rag_query_hints))[:4],
        )
        return normalized

