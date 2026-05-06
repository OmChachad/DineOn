from models import HealthKitSnapshot, NutritionIntent, StructuredServingRow
from pipeline.rag_ingest import KnowledgeBase
from pipeline.rag_query import NutritionRAGService


class StubOpenAIClient:
    is_configured = False


def make_service(rows: list[StructuredServingRow]) -> NutritionRAGService:
    knowledge_base = KnowledgeBase(chroma_client=None, collection_name="unused", serving_rows=rows)  # type: ignore[arg-type]
    return NutritionRAGService(knowledge_base, StubOpenAIClient())  # type: ignore[arg-type]


def test_provisional_target_uses_weight_loss_adjustment() -> None:
    service = make_service([])
    intent = NutritionIntent(
        primary_goal="weight_loss",
        secondary_goals=[],
        dietary_restrictions=[],
        special_flags=[],
        medical_flags=[],
        rag_query_hints=["weight loss protein"],
    )
    healthkit = HealthKitSnapshot(tdee=1900)

    assert service._derive_provisional_calorie_target(intent, healthkit) == 1650


def test_serving_row_selection_brackets_nearest_rows() -> None:
    rows = [
        StructuredServingRow(
            calorie_level=1600,
            protein_servings_min=2.5,
            protein_servings_max=3.5,
            dairy_servings=3,
            vegetable_servings=2.5,
            fruit_servings=1.5,
            whole_grains_min=1.75,
            whole_grains_max=3.25,
            healthy_fats=3.5,
            source_text="1600 row",
        ),
        StructuredServingRow(
            calorie_level=1800,
            protein_servings_min=2.5,
            protein_servings_max=3.5,
            dairy_servings=3,
            vegetable_servings=3,
            fruit_servings=1.5,
            whole_grains_min=2,
            whole_grains_max=4,
            healthy_fats=4,
            source_text="1800 row",
        ),
    ]
    service = make_service(rows)

    selected = service._select_serving_rows(1700)

    assert [row.calorie_level for row in selected] == [1600, 1800]
