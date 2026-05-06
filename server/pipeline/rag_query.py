from __future__ import annotations

import math
import re
from dataclasses import dataclass

from models import HealthKitSnapshot, NarrativeEvidenceChunk, NutritionIntent, RetrievalPayload, StructuredServingRow
from pipeline.openai_client import OpenAIClient
from pipeline.rag_ingest import KnowledgeBase

MAX_QUERY_HINTS = 3
RESULTS_PER_HINT = 3
MAX_NARRATIVE_CHUNKS = 5
MIN_ACCEPTED_SCORE = 0.35

GENERIC_HEADING_TERMS = {"background", "introduction", "overview"}
SPECIAL_POPULATION_PATTERNS = {
    "older_adult": ("older adults", "recommendation: older adults"),
    "young_adulthood": ("young adulthood", "recommendation: young adulthood"),
    "pregnancy": ("pregnant women", "recommendations: pregnant women"),
    "lactation": ("lactating women", "recommendations: lactating women"),
    "vegetarian": ("vegetarian", "vegan"),
    "reproductive_women": ("women of reproductive age",),
    "testosterone_health": ("testosterone health in men",),
}


@dataclass(frozen=True)
class RetrievalContext:
    exact_terms: set[str]
    requested_diet_patterns: set[str]
    requested_populations: set[str]
    age: int | None


class NutritionRAGService:
    def __init__(self, knowledge_base: KnowledgeBase, openai_client: OpenAIClient) -> None:
        self.knowledge_base = knowledge_base
        self.openai_client = openai_client

    async def retrieve(self, intent: NutritionIntent, healthkit: HealthKitSnapshot) -> RetrievalPayload:
        narrative_chunks = await self._retrieve_narrative_chunks(intent, healthkit)
        provisional_target = self._derive_provisional_calorie_target(intent, healthkit)
        serving_rows = self._select_serving_rows(provisional_target)
        return RetrievalPayload(
            intent=intent,
            narrative_chunks=narrative_chunks,
            serving_rows=serving_rows,
            provisional_calorie_target=provisional_target,
        )

    async def _retrieve_narrative_chunks(
        self,
        intent: NutritionIntent,
        healthkit: HealthKitSnapshot,
    ) -> list[NarrativeEvidenceChunk]:
        if not self.openai_client.is_configured:
            return []

        query_hints = [hint for hint in intent.rag_query_hints if hint.strip()][:MAX_QUERY_HINTS]
        if not query_hints:
            return []

        collection = self.knowledge_base.chroma_client.get_collection(self.knowledge_base.collection_name)
        embeddings = await self.openai_client.embed_texts(query_hints)
        collected: dict[str, NarrativeEvidenceChunk] = {}
        context = self._build_retrieval_context(intent, healthkit)

        for hint, embedding in zip(query_hints, embeddings, strict=True):
            result = collection.query(
                query_embeddings=[embedding],
                n_results=RESULTS_PER_HINT,
                include=["documents", "metadatas", "distances"],
            )
            documents = result.get("documents", [[]])[0]
            metadatas = result.get("metadatas", [[]])[0]
            distances = result.get("distances", [[]])[0]
            ids = result.get("ids", [[]])[0]

            for chunk_id, document, metadata, distance in zip(ids, documents, metadatas, distances, strict=True):
                overlap_bonus = self._keyword_overlap_score(document, context.exact_terms)
                similarity = 1 / (1 + float(distance))
                heading_path = str(metadata.get("heading_path", ""))
                section_penalty = self._section_penalty(heading_path, context)
                generic_penalty = self._generic_section_penalty(heading_path)
                score = similarity + overlap_bonus + (0.05 if hint.casefold() in document.casefold() else 0)
                score -= section_penalty + generic_penalty
                if score < MIN_ACCEPTED_SCORE:
                    continue
                candidate = NarrativeEvidenceChunk(
                    chunk_id=chunk_id,
                    source_file=str(metadata.get("source_file", "")),
                    heading_path=heading_path,
                    text=document,
                    score=round(score, 6),
                )
                existing = collected.get(chunk_id)
                if existing is None or candidate.score > existing.score:
                    collected[chunk_id] = candidate

        ranked = sorted(collected.values(), key=lambda item: item.score, reverse=True)
        selected: list[NarrativeEvidenceChunk] = []
        heading_counts: dict[str, int] = {}
        source_counts: dict[str, int] = {}
        selected_texts: list[set[str]] = []

        for candidate in ranked:
            if self._is_near_duplicate(candidate, selected_texts):
                continue

            heading_key = candidate.heading_path.casefold()
            source_key = candidate.source_file.casefold()
            adjusted_score = candidate.score
            adjusted_score -= heading_counts.get(heading_key, 0) * 0.2
            adjusted_score -= source_counts.get(source_key, 0) * 0.05
            if adjusted_score <= 0:
                continue
            selected.append(candidate.model_copy(update={"score": round(adjusted_score, 6)}))
            heading_counts[heading_key] = heading_counts.get(heading_key, 0) + 1
            source_counts[source_key] = source_counts.get(source_key, 0) + 1
            selected_texts.append(self._tokenize_text(candidate.text))
            if len(selected) == MAX_NARRATIVE_CHUNKS:
                break

        return selected

    def _build_retrieval_context(
        self,
        intent: NutritionIntent,
        healthkit: HealthKitSnapshot,
    ) -> RetrievalContext:
        raw_terms = " ".join(
            [
                intent.primary_goal,
                *intent.secondary_goals,
                *intent.dietary_restrictions,
                *intent.special_flags,
                *intent.medical_flags,
                *intent.rag_query_hints,
            ]
        ).casefold()
        requested_diet_patterns = {
            pattern
            for pattern in {"vegetarian", "vegan", "plant", "pescatarian"}
            if pattern in raw_terms
        }
        requested_populations: set[str] = set()
        if "older adult" in raw_terms or "senior" in raw_terms:
            requested_populations.add("older_adult")
        if "young adult" in raw_terms:
            requested_populations.add("young_adulthood")
        if "pregnan" in raw_terms:
            requested_populations.add("pregnancy")
        if "lactat" in raw_terms or "breastfeed" in raw_terms:
            requested_populations.add("lactation")
        if "reproductive age" in raw_terms:
            requested_populations.add("reproductive_women")
        if "testosterone" in raw_terms:
            requested_populations.add("testosterone_health")

        return RetrievalContext(
            exact_terms={term for term in re.findall(r"[a-zA-Z]{4,}", raw_terms)},
            requested_diet_patterns=requested_diet_patterns,
            requested_populations=requested_populations,
            age=healthkit.age,
        )

    def _build_exact_term_set(self, intent: NutritionIntent) -> set[str]:
        raw_terms = " ".join(
            [
                intent.primary_goal,
                *intent.secondary_goals,
                *intent.dietary_restrictions,
                *intent.special_flags,
                *intent.medical_flags,
                *intent.rag_query_hints,
            ]
        )
        return {term for term in re.findall(r"[a-zA-Z]{4,}", raw_terms.casefold())}

    def _keyword_overlap_score(self, document: str, exact_terms: set[str]) -> float:
        if not exact_terms:
            return 0.0
        words = set(re.findall(r"[a-zA-Z]{4,}", document.casefold()))
        overlap = len(words & exact_terms)
        return min(0.35, overlap * 0.05)

    def _section_penalty(self, heading_path: str, context: RetrievalContext) -> float:
        heading = heading_path.casefold()
        penalty = 0.0

        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["vegetarian"]) and not context.requested_diet_patterns:
            penalty += 0.3
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["older_adult"]):
            if context.age is None or context.age < 60:
                penalty += 0.5
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["young_adulthood"]):
            if context.age is None or not (18 <= context.age <= 29):
                penalty += 0.6
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["pregnancy"]) and "pregnancy" not in context.requested_populations:
            penalty += 0.45
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["lactation"]) and "lactation" not in context.requested_populations:
            penalty += 0.45
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["reproductive_women"]) and "reproductive_women" not in context.requested_populations:
            penalty += 0.25
        if any(token in heading for token in SPECIAL_POPULATION_PATTERNS["testosterone_health"]) and "testosterone_health" not in context.requested_populations:
            penalty += 0.2

        return penalty

    def _generic_section_penalty(self, heading_path: str) -> float:
        heading = heading_path.casefold()
        return 0.12 if any(term in heading for term in GENERIC_HEADING_TERMS) else 0.0

    def _tokenize_text(self, text: str) -> set[str]:
        return {term for term in re.findall(r"[a-zA-Z]{4,}", text.casefold())}

    def _is_near_duplicate(self, candidate: NarrativeEvidenceChunk, selected_texts: list[set[str]]) -> bool:
        candidate_terms = self._tokenize_text(candidate.text)
        if not candidate_terms:
            return False
        for existing_terms in selected_texts:
            overlap = len(candidate_terms & existing_terms)
            union = len(candidate_terms | existing_terms)
            if union and (overlap / union) >= 0.72:
                return True
        return False

    def _derive_provisional_calorie_target(
        self,
        intent: NutritionIntent,
        healthkit: HealthKitSnapshot,
    ) -> int | None:
        baseline = healthkit.tdee
        if baseline is None and healthkit.resting_calories is not None and healthkit.active_calories_avg is not None:
            baseline = healthkit.resting_calories + healthkit.active_calories_avg
        if baseline is None:
            return None

        goal = intent.primary_goal.casefold()
        adjustment = 0
        if "weight_loss" in goal or "fat_loss" in goal:
            adjustment = -250
        elif "gain" in goal or "muscle" in goal or "bulk" in goal:
            adjustment = 250
        target = max(1000, int(round((baseline + adjustment) / 50.0) * 50))
        return target

    def _select_serving_rows(self, provisional_target: int | None) -> list[StructuredServingRow]:
        rows = sorted(self.knowledge_base.serving_rows, key=lambda row: row.calorie_level)
        if not rows:
            return []
        if provisional_target is None:
            return []

        exact = [row for row in rows if row.calorie_level == provisional_target]
        if exact:
            return exact

        lower = [row for row in rows if row.calorie_level < provisional_target]
        higher = [row for row in rows if row.calorie_level > provisional_target]
        selected: list[StructuredServingRow] = []
        if lower:
            selected.append(lower[-1])
        if higher:
            selected.append(higher[0])
        if selected:
            return selected

        nearest = min(rows, key=lambda row: math.fabs(row.calorie_level - provisional_target))
        return [nearest]
