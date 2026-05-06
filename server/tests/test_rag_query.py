import asyncio

from models import HealthKitSnapshot, NutritionIntent, StructuredServingRow
from pipeline.rag_ingest import KnowledgeBase
from pipeline.rag_query import NutritionRAGService


class StubOpenAIClient:
    is_configured = False


def make_service(rows: list[StructuredServingRow]) -> NutritionRAGService:
    knowledge_base = KnowledgeBase(chroma_client=None, collection_name="unused", serving_rows=rows)  # type: ignore[arg-type]
    return NutritionRAGService(knowledge_base, StubOpenAIClient())  # type: ignore[arg-type]


class StubCollection:
    def __init__(self, result: dict) -> None:
        self.result = result

    def query(self, **_: object) -> dict:
        return self.result


class StubChromaClient:
    def __init__(self, result: dict) -> None:
        self.result = result

    def get_collection(self, _: str) -> StubCollection:
        return StubCollection(self.result)


class ConfiguredStubOpenAIClient:
    is_configured = True

    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        return [[0.1] for _ in texts]


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


def test_serving_row_selection_uses_no_fallback_when_target_unknown() -> None:
    rows = [
        StructuredServingRow(
            calorie_level=1400,
            protein_servings_min=2,
            protein_servings_max=2.5,
            dairy_servings=2.5,
            vegetable_servings=1.75,
            fruit_servings=1.5,
            whole_grains_min=1.75,
            whole_grains_max=3.25,
            healthy_fats=2.5,
            source_text="1400 row",
        ),
    ]
    service = make_service(rows)

    assert service._select_serving_rows(None) == []


def test_retrieve_filters_irrelevant_and_duplicate_population_chunks() -> None:
    result = {
        "documents": [[
            "Higher-protein diets of 1.2-1.6 g/kg/day improved fat loss and preserved lean mass during calorie restriction.",
            "Young adults should follow general dietary guidelines with whole foods and healthy fats.",
            "Following the Dietary Guidelines will support optimal health during young adulthood with healthy fats and protein.",
        ]],
        "metadatas": [[
            {"source_file": "Scientific_Foundations.md", "heading_path": "Chapter 6. Dietary Protein > Effect of Protein Intake of 1.2 to 1.6 g/kg/day on Body Composition"},
            {"source_file": "Scientific_Foundations.md", "heading_path": "Chapter 8. Special Considerations for Life Stages and Vegetarians & Vegans > Recommendation: Young Adulthood"},
            {"source_file": "Dietary_Guidelines_For_Americans.md", "heading_path": "Young Adulthood"},
        ]],
        "distances": [[0.15, 0.16, 0.17]],
        "ids": [[
            "protein-1",
            "young-science-1",
            "young-guidelines-1",
        ]],
    }
    knowledge_base = KnowledgeBase(
        chroma_client=StubChromaClient(result),  # type: ignore[arg-type]
        collection_name="unused",
        serving_rows=[],
    )
    service = NutritionRAGService(knowledge_base, ConfiguredStubOpenAIClient())  # type: ignore[arg-type]
    intent = NutritionIntent(
        primary_goal="weight_loss",
        secondary_goals=["visceral_fat_reduction"],
        dietary_restrictions=[],
        special_flags=["low_sleep"],
        medical_flags=[],
        rag_query_hints=["calorie deficit protein satiety"],
    )
    healthkit = HealthKitSnapshot(age=34)

    selected = asyncio.run(service._retrieve_narrative_chunks(intent, healthkit))

    assert [chunk.chunk_id for chunk in selected] == ["protein-1"]


def test_retrieve_drops_seafood_and_medical_chunks_when_not_requested() -> None:
    result = {
        "documents": [[
            "Higher-protein diets of 1.2-1.6 g/kg/day improved fat loss and preserved lean mass during calorie restriction.",
            "The experimental group replaced fats with Norwegian sardines canned in cod liver oil and other seafood sources.",
            "Following the Dietary Guidelines can help prevent chronic disease. If you have chronic disease, talk with your health care professional.",
        ]],
        "metadatas": [[
            {"source_file": "Scientific_Foundations.md", "heading_path": "Chapter 6. Dietary Protein > Effect of Protein Intake of 1.2 to 1.6 g/kg/day on Body Composition"},
            {"source_file": "Scientific_Foundations.md", "heading_path": "Chapter 5. Fats and Oils > Initial Recommendations to reduce saturated fat intake"},
            {"source_file": "Dietary_Guidelines_For_Americans.md", "heading_path": "Adults"},
        ]],
        "distances": [[0.15, 0.14, 0.16]],
        "ids": [[
            "protein-1",
            "seafood-fats-1",
            "medical-guidance-1",
        ]],
    }
    knowledge_base = KnowledgeBase(
        chroma_client=StubChromaClient(result),  # type: ignore[arg-type]
        collection_name="unused",
        serving_rows=[],
    )
    service = NutritionRAGService(knowledge_base, ConfiguredStubOpenAIClient())  # type: ignore[arg-type]
    intent = NutritionIntent(
        primary_goal="fat_loss",
        secondary_goals=["maintenance"],
        dietary_restrictions=["no_beef", "preferably_no_seafood"],
        special_flags=["low_sleep"],
        medical_flags=[],
        rag_query_hints=["visceral fat reduction nutrition", "high protein calorie control", "no beef no seafood meal planning"],
    )
    healthkit = HealthKitSnapshot(age=19)

    selected = asyncio.run(service._retrieve_narrative_chunks(intent, healthkit))

    assert [chunk.chunk_id for chunk in selected] == ["protein-1"]
