from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

SCHEMA_VERSION = 1
MAX_PREFERENCE_NOTE_LENGTH = 150


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", populate_by_name=True)


class HealthKitSnapshot(StrictModel):
    age: int | None = Field(default=None, ge=0, le=130)
    sex: Literal["female", "male", "other", "unknown"] | None = None
    height_cm: float | None = Field(default=None, ge=0, le=300)
    weight_kg: float | None = Field(default=None, ge=0, le=500)
    bmi: float | None = Field(default=None, ge=0, le=100)
    resting_calories: float | None = Field(default=None, ge=0, le=10000)
    active_calories_avg: float | None = Field(default=None, ge=0, le=10000)
    tdee: float | None = Field(default=None, ge=0, le=10000)
    steps_daily_avg: float | None = Field(default=None, ge=0, le=100000)
    exercise_sessions_per_week: float | None = Field(default=None, ge=0, le=100)
    sleep_hrs_avg: float | None = Field(default=None, ge=0, le=24)
    resting_hr_avg: float | None = Field(default=None, ge=0, le=300)
    weight_trend_30d_kg: float | None = Field(default=None, ge=-100, le=100)

    @model_validator(mode="after")
    def derive_tdee(self) -> "HealthKitSnapshot":
        if self.tdee is None and self.resting_calories is not None and self.active_calories_avg is not None:
            self.tdee = round(self.resting_calories + self.active_calories_avg, 2)
        if self.bmi is None and self.height_cm and self.weight_kg:
            height_m = self.height_cm / 100
            if height_m > 0:
                self.bmi = round(self.weight_kg / (height_m * height_m), 1)
        return self


class NutritionProfileRequest(StrictModel):
    schema_version: int = Field(default=SCHEMA_VERSION)
    preference_notes: list[str] = Field(default_factory=list)
    healthkit: HealthKitSnapshot = Field(default_factory=HealthKitSnapshot)

    @field_validator("preference_notes", mode="before")
    @classmethod
    def normalize_notes(cls, value: list[str] | None) -> list[str]:
        if value is None:
            return []
        cleaned: list[str] = []
        for note in value:
            normalized = " ".join((note or "").split())
            if not normalized:
                continue
            if len(normalized) > MAX_PREFERENCE_NOTE_LENGTH:
                raise ValueError(
                    f"Each preference note must be {MAX_PREFERENCE_NOTE_LENGTH} characters or fewer."
                )
            cleaned.append(normalized)
        return cleaned

    @model_validator(mode="after")
    def ensure_notes_present(self) -> "NutritionProfileRequest":
        if not self.preference_notes:
            raise ValueError("At least one non-empty preference note is required.")
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(f"Unsupported schema_version: {self.schema_version}")
        return self


class NutritionIntent(StrictModel):
    primary_goal: str
    secondary_goals: list[str] = Field(default_factory=list)
    dietary_restrictions: list[str] = Field(default_factory=list)
    special_flags: list[str] = Field(default_factory=list)
    medical_flags: list[str] = Field(default_factory=list)
    rag_query_hints: list[str] = Field(default_factory=list)


class NarrativeEvidenceChunk(StrictModel):
    chunk_id: str
    source_file: str
    heading_path: str
    text: str
    score: float


class StructuredServingRow(StrictModel):
    calorie_level: int
    protein_servings_min: float
    protein_servings_max: float
    dairy_servings: float
    vegetable_servings: float
    fruit_servings: float
    whole_grains_min: float
    whole_grains_max: float
    healthy_fats: float
    source_text: str


class RetrievalPayload(StrictModel):
    intent: NutritionIntent
    narrative_chunks: list[NarrativeEvidenceChunk] = Field(default_factory=list)
    serving_rows: list[StructuredServingRow] = Field(default_factory=list)
    provisional_calorie_target: int | None = None


class NutritionProfileResponse(StrictModel):
    schema_version: int = Field(default=SCHEMA_VERSION)
    generated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    daily_calories: int | None = Field(default=None, ge=0, le=10000)
    protein_g: int | None = Field(default=None, ge=0, le=1000)
    carbs_g: int | None = Field(default=None, ge=0, le=1000)
    fat_g: int | None = Field(default=None, ge=0, le=500)
    calorie_rationale: str
    meal_pattern: str
    foods_to_prioritize: list[str] = Field(default_factory=list)
    foods_to_avoid: list[str] = Field(default_factory=list)
    watch_nutrients: list[str] = Field(default_factory=list)
    sleep_note: str
    summary: str
    sources: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)

    @field_validator(
        "foods_to_prioritize",
        "foods_to_avoid",
        "watch_nutrients",
        "sources",
        "warnings",
        mode="before",
    )
    @classmethod
    def clean_string_list(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        items: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                items.append(normalized)
        return items


class SuggestionsPreferences(StrictModel):
    has_aaz_access: bool = False
    has_dietary_restrictions: bool = False
    selected_allergens: list[str] = Field(default_factory=list)
    selected_dietary_preferences: list[str] = Field(default_factory=list)
    excluded_keywords: list[str] = Field(default_factory=list)
    favorite_dishes: list[str] = Field(default_factory=list)

    @field_validator(
        "selected_allergens",
        "selected_dietary_preferences",
        "excluded_keywords",
        "favorite_dishes",
        mode="before",
    )
    @classmethod
    def clean_preference_list(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                cleaned.append(normalized)
        return cleaned


class SuggestionsHealthContext(HealthKitSnapshot):
    active_calories_today: float | None = Field(default=None, ge=0, le=10000)


class SuggestionsClientContext(StrictModel):
    consumed_meal_keys: list[str] = Field(default_factory=list)

    @field_validator("consumed_meal_keys", mode="before")
    @classmethod
    def clean_meal_keys(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                cleaned.append(normalized)
        return cleaned


class SuggestionsRequest(StrictModel):
    schema_version: int = Field(default=SCHEMA_VERSION)
    date: str
    meal_slots: list[str] = Field(default_factory=list)
    preferences: SuggestionsPreferences = Field(default_factory=SuggestionsPreferences)
    nutrition_profile: NutritionProfileResponse | None = None
    healthkit: SuggestionsHealthContext = Field(default_factory=SuggestionsHealthContext)
    menu_export: str
    client_context: SuggestionsClientContext = Field(default_factory=SuggestionsClientContext)

    @field_validator("date")
    @classmethod
    def validate_date(cls, value: str) -> str:
        normalized = " ".join((value or "").split())
        try:
            datetime.strptime(normalized, "%Y-%m-%d")
        except ValueError as exc:
            raise ValueError("date must use YYYY-MM-DD format.") from exc
        return normalized

    @field_validator("meal_slots", mode="before")
    @classmethod
    def clean_meal_slots(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                cleaned.append(normalized)
        return cleaned

    @field_validator("menu_export")
    @classmethod
    def clean_menu_export(cls, value: str) -> str:
        normalized = value.strip()
        if not normalized:
            raise ValueError("menu_export is required.")
        return normalized

    @model_validator(mode="after")
    def ensure_request_is_actionable(self) -> "SuggestionsRequest":
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(f"Unsupported schema_version: {self.schema_version}")
        if not self.meal_slots:
            raise ValueError("At least one meal slot is required.")
        return self


class MealSuggestion(StrictModel):
    meal: str
    meal_key: str
    venue: str
    items: list[str] = Field(default_factory=list)
    estimated_calories: int | None = Field(default=None, ge=0, le=10000)
    estimated_protein_g: int | None = Field(default=None, ge=0, le=1000)
    estimated_carbs_g: int | None = Field(default=None, ge=0, le=1000)
    estimated_fat_g: int | None = Field(default=None, ge=0, le=500)
    rationale: str
    optional_caution: str | None = None

    @field_validator("meal", "meal_key", "venue", "rationale")
    @classmethod
    def clean_required_text(cls, value: str) -> str:
        normalized = " ".join((value or "").split())
        if not normalized:
            raise ValueError("Field must not be empty.")
        return normalized

    @field_validator("optional_caution")
    @classmethod
    def clean_optional_text(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = " ".join(value.split())
        return normalized or None

    @field_validator("items", mode="before")
    @classmethod
    def clean_items(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                cleaned.append(normalized)
        return cleaned


class SuggestionsResponse(StrictModel):
    schema_version: int = Field(default=SCHEMA_VERSION)
    generated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    date: str
    daily_calorie_target: int | None = Field(default=None, ge=0, le=10000)
    active_calories_today: int | None = Field(default=None, ge=0, le=10000)
    meals: list[MealSuggestion] = Field(default_factory=list)
    summary: str
    warnings: list[str] = Field(default_factory=list)

    @field_validator("date")
    @classmethod
    def validate_response_date(cls, value: str) -> str:
        normalized = " ".join((value or "").split())
        try:
            datetime.strptime(normalized, "%Y-%m-%d")
        except ValueError as exc:
            raise ValueError("date must use YYYY-MM-DD format.") from exc
        return normalized

    @field_validator("summary")
    @classmethod
    def clean_summary(cls, value: str) -> str:
        normalized = " ".join((value or "").split())
        if not normalized:
            raise ValueError("summary is required.")
        return normalized

    @field_validator("warnings", mode="before")
    @classmethod
    def clean_warnings(cls, value: list[str] | None) -> list[str]:
        if not value:
            return []
        cleaned: list[str] = []
        seen: set[str] = set()
        for item in value:
            normalized = " ".join((item or "").split())
            key = normalized.casefold()
            if normalized and key not in seen:
                seen.add(key)
                cleaned.append(normalized)
        return cleaned
