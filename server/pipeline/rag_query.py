from __future__ import annotations

import math
import re

from models import HealthKitSnapshot, NarrativeEvidenceChunk, NutritionIntent, RetrievalPayload, StructuredServingRow
from pipeline.openai_client import OpenAIClient
from pipeline.rag_ingest import KnowledgeBase


class NutritionRAGService:
    def __init__(self, knowledge_base: KnowledgeBase, openai_client: OpenAIClient) -> None:
        self.knowledge_base = knowledge_base
        self.openai_client = openai_client

    async def retrieve(self, intent: NutritionIntent, healthkit: HealthKitSnapshot) -> RetrievalPayload:
        narrative_chunks = await self._retrieve_narrative_chunks(intent)
        provisional_target = self._derive_provisional_calorie_target(intent, healthkit)
        serving_rows = self._select_serving_rows(provisional_target)
        return RetrievalPayload(
            intent=intent,
            narrative_chunks=narrative_chunks,
            serving_rows=serving_rows,
            provisional_calorie_target=provisional_target,
        )

    async def _retrieve_narrative_chunks(self, intent: NutritionIntent) -> list[NarrativeEvidenceChunk]:
        if not self.openai_client.is_configured:
            return []

        query_hints = [hint for hint in intent.rag_query_hints if hint.strip()]
        if not query_hints:
            return []

        collection = self.knowledge_base.chroma_client.get_collection(self.knowledge_base.collection_name)
        embeddings = await self.openai_client.embed_texts(query_hints)
        collected: dict[str, NarrativeEvidenceChunk] = {}
        exact_terms = self._build_exact_term_set(intent)

        for hint, embedding in zip(query_hints, embeddings, strict=True):
            result = collection.query(
                query_embeddings=[embedding],
                n_results=4,
                include=["documents", "metadatas", "distances"],
            )
            documents = result.get("documents", [[]])[0]
            metadatas = result.get("metadatas", [[]])[0]
            distances = result.get("distances", [[]])[0]
            ids = result.get("ids", [[]])[0]

            for chunk_id, document, metadata, distance in zip(ids, documents, metadatas, distances, strict=True):
                overlap_bonus = self._keyword_overlap_score(document, exact_terms)
                similarity = 1 / (1 + float(distance))
                score = similarity + overlap_bonus + (0.05 if hint.casefold() in document.casefold() else 0)
                candidate = NarrativeEvidenceChunk(
                    chunk_id=chunk_id,
                    source_file=str(metadata.get("source_file", "")),
                    heading_path=str(metadata.get("heading_path", "")),
                    text=document,
                    score=round(score, 6),
                )
                existing = collected.get(chunk_id)
                if existing is None or candidate.score > existing.score:
                    collected[chunk_id] = candidate

        ranked = sorted(collected.values(), key=lambda item: item.score, reverse=True)
        selected: list[NarrativeEvidenceChunk] = []
        source_counts: dict[str, int] = {}

        for candidate in ranked:
            source_key = f"{candidate.source_file}:{candidate.heading_path}"
            source_penalty = source_counts.get(source_key, 0)
            adjusted_score = candidate.score - (source_penalty * 0.08)
            if adjusted_score <= 0:
                continue
            selected.append(candidate.model_copy(update={"score": round(adjusted_score, 6)}))
            source_counts[source_key] = source_penalty + 1
            if len(selected) == 8:
                break

        return selected

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
            return rows[:1]

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

