from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import chromadb
import tiktoken

from models import NarrativeEvidenceChunk, StructuredServingRow
from pipeline.openai_client import OpenAIClient

BASE_DIR = Path(__file__).resolve().parent.parent
KNOWLEDGE_DIR = BASE_DIR / "knowledge"
VECTOR_STORE_DIR = BASE_DIR / "vector_store"
ARTIFACTS_DIR = BASE_DIR / "artifacts"
NARRATIVE_CHUNKS_PATH = ARTIFACTS_DIR / "narrative_chunks.json"
SERVING_ROWS_PATH = ARTIFACTS_DIR / "daily_servings_lookup.json"
INGESTION_MANIFEST_PATH = ARTIFACTS_DIR / "ingestion_manifest.json"
NARRATIVE_COLLECTION_NAME = "nutrition_narrative_chunks"
MAX_CHUNK_TOKENS = 650
OVERLAP_TOKENS = 100
INGESTION_PIPELINE_VERSION = 2

DIETARY_GUIDELINES_FILE = "Dietary_Guidelines_For_Americans.md"
SCIENTIFIC_FOUNDATIONS_FILE = "Scientific_Foundations.md"
SERVINGS_FILE = "Daily_Servings_By_Calorie_Level.md"

SCIENTIFIC_ALLOWED_SECTIONS: dict[str, set[str]] = {
    "Chapter 3. Highly Processed Foods": {
        "Evidence",
        "How can you identify highly processed foods?",
        "Recommendation: Highly Processed Foods",
    },
    "Chapter 4. Carbohydrates": {
        "Overview",
        "Concentrated Sources of Sugars and Chemical Sweeteners in U.S. Diets",
        "Evidence",
        "Recommendations: Added Sugars",
        "Refined Grains and Starches in the U.S. Food Supply",
        "Refined Grains and Starches are Sugar",
        "Separating the Wheat from the Chaff",
        "Microbiome",
        "Recommendations: Whole Grains and Refined Carbohydrates",
        "Recommendations: Vegetables and Fruits",
    },
    "Chapter 5. Fats and Oils": {
        "Introduction",
        "A Century of Change: From Animal Fats to Industrial Fats and Oils",
        "Modern Fat Sources and the Linoleic Acid Dominant Profile",
        "Omega-3 Fatty Acids",
        "Evaluating the Evidence for Saturated-Fat Reduction and Replacement",
        "Linoleic Acid Peroxidation and Health Implications of Heated Oils",
        "Dairy as a Case Example",
        "Emerging Evidence of Adverse Effects",
        "Recommendations: Healthy Fats",
        "Recommendations: Dairy",
    },
    "Chapter 6. Dietary Protein": {
        "Background",
        "Effect of Protein Intake of 1.2 to 1.6 g/kg/day on Body Composition",
        "Protein Sources and Nutrient Quality",
        "Animal-Source Protein Foods",
        "Plant-Source Protein Foods",
        "Processing and Preparation",
        "Recommendations: Protein",
    },
    "Chapter 7. Sodium and Other Micronutrients": {
        "Vitamins and Minerals",
        "Sodium",
        "Recommendations: Sodium",
    },
    "Chapter 8. Special Considerations for Life Stages and Vegetarians & Vegans": {
        "Young Adulthood",
        "Non-pregnant, non-lactating women of reproductive age",
        "Supporting testosterone health in men",
        "Recommendation: Young Adulthood",
        "Pregnant Women",
        "Recommendations: Pregnant Women",
        "Lactating Women",
        "Recommendations: Lactating Women",
        "Older Adults",
        "Recommendation: Older Adults",
        "Vegetarian and Vegan Diets",
        "Recommendations: Vegetarians and Vegans",
    },
}


@dataclass(frozen=True)
class NarrativeChunk:
    chunk_id: str
    text: str
    source_file: str
    heading_path: str


@dataclass
class KnowledgeBase:
    chroma_client: chromadb.PersistentClient
    collection_name: str
    serving_rows: list[StructuredServingRow]


def normalize_text(raw_text: str) -> str:
    text = raw_text.replace("\r\n", "\n").replace("\r", "\n").replace("\u00a0", " ")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def compute_file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_heading(raw_heading: str) -> str:
    heading = raw_heading.strip()
    heading = re.sub(r"[*_`]+", "", heading)
    heading = re.sub(r"\s+", " ", heading)
    return heading.strip()


def token_count(text: str) -> int:
    if TOKEN_ENCODING is not None:
        return len(TOKEN_ENCODING.encode(text))
    return max(1, len(re.findall(r"\S+", text)))


def split_section_into_chunks(source_file: str, heading_path: list[str], content: str) -> list[NarrativeChunk]:
    paragraphs = [paragraph.strip() for paragraph in re.split(r"\n\s*\n", content) if paragraph.strip()]
    if not paragraphs:
        return []

    result: list[NarrativeChunk] = []
    start_index = 0
    chunk_index = 0
    path_text = " > ".join(heading_path)
    section_fingerprint = hashlib.sha1(f"{path_text}\n{content}".encode("utf-8")).hexdigest()[:10]

    while start_index < len(paragraphs):
        current: list[str] = []
        current_tokens = 0
        end_index = start_index

        while end_index < len(paragraphs):
            paragraph = paragraphs[end_index]
            paragraph_tokens = token_count(paragraph)
            if current and current_tokens + paragraph_tokens > MAX_CHUNK_TOKENS:
                break
            current.append(paragraph)
            current_tokens += paragraph_tokens
            end_index += 1

        chunk_text = "\n\n".join(current).strip()
        if chunk_text:
            chunk_id = f"{source_file}:{path_text}:{section_fingerprint}:{chunk_index}"
            result.append(
                NarrativeChunk(
                    chunk_id=chunk_id,
                    text=chunk_text,
                    source_file=source_file,
                    heading_path=path_text,
                )
            )
            chunk_index += 1

        overlap_index = end_index
        overlap_tokens = 0
        while overlap_index > start_index:
            overlap_tokens += token_count(paragraphs[overlap_index - 1])
            if overlap_tokens >= OVERLAP_TOKENS:
                overlap_index -= 1
                break
            overlap_index -= 1

        if overlap_index == start_index:
            start_index = max(end_index, start_index + 1)
        else:
            start_index = overlap_index

    return result


def parse_markdown_sections(path: Path) -> list[tuple[list[str], str]]:
    text = normalize_text(path.read_text())
    sections: list[tuple[list[str], str]] = []
    heading_stack: list[tuple[int, str]] = []
    current_lines: list[str] = []

    def flush_current() -> None:
        if heading_stack and any(line.strip() for line in current_lines):
            sections.append(([heading for _, heading in heading_stack], "\n".join(current_lines).strip()))

    for line in text.splitlines():
        match = re.match(r"^(#{2,6})\s+(.*\S)\s*$", line)
        if match:
            flush_current()
            current_lines = []
            level = len(match.group(1))
            heading = clean_heading(match.group(2))
            while heading_stack and heading_stack[-1][0] >= level:
                heading_stack.pop()
            heading_stack.append((level, heading))
        elif heading_stack:
            current_lines.append(line)

    flush_current()
    return sections


def parse_scientific_foundations_sections(path: Path) -> list[tuple[list[str], str]]:
    text = normalize_text(path.read_text())
    sections: list[tuple[list[str], str]] = []
    current_chapter: str | None = None
    current_heading: str | None = None
    current_lines: list[str] = []

    def flush_current() -> None:
        if (
            current_chapter
            and current_heading
            and any(line.strip() for line in current_lines)
            and current_heading in SCIENTIFIC_ALLOWED_SECTIONS.get(current_chapter, set())
        ):
            sections.append(([current_chapter, current_heading], "\n".join(current_lines).strip()))

    for line in text.splitlines():
        match = re.match(r"^(#{2,6})\s+(.*\S)\s*$", line)
        if match:
            flush_current()
            current_lines = []
            heading = clean_heading(match.group(2))
            if heading.startswith("Chapter "):
                current_chapter = heading
                current_heading = None
            else:
                current_heading = heading
        elif current_heading:
            current_lines.append(line)

    flush_current()
    return sections


def build_narrative_chunks() -> list[NarrativeChunk]:
    dietary_sections = parse_markdown_sections(KNOWLEDGE_DIR / DIETARY_GUIDELINES_FILE)
    dietary_chunks: list[NarrativeChunk] = []
    for heading_path, content in dietary_sections:
        if heading_path and heading_path[0] in {
            "Dietary Guidelines For Americans",
            "Message from the Secretaries",
            "Welcome to the Dietary Guidelines for Americans, 2025–2030.",
            "The message is simple: eat real food.",
            "This changes today.",
            "This is the foundation that will Make America Healthy Again.",
        }:
            continue
        dietary_chunks.extend(split_section_into_chunks(DIETARY_GUIDELINES_FILE, heading_path, content))

    scientific_sections = parse_scientific_foundations_sections(KNOWLEDGE_DIR / SCIENTIFIC_FOUNDATIONS_FILE)
    scientific_chunks: list[NarrativeChunk] = []
    for heading_path, content in scientific_sections:
        scientific_chunks.extend(split_section_into_chunks(SCIENTIFIC_FOUNDATIONS_FILE, heading_path, content))

    return dietary_chunks + scientific_chunks


FRACTION_REPLACEMENTS = {
    "½": ".5",
    "¼": ".25",
    "¾": ".75",
    "⅓": ".333",
    "⅔": ".667",
}


def parse_serving_amount(raw_value: str) -> tuple[float, float]:
    normalized = raw_value.strip()
    for symbol, replacement in FRACTION_REPLACEMENTS.items():
        normalized = normalized.replace(symbol, replacement)
    normalized = normalized.replace("–", "-").replace("—", "-")
    normalized = normalized.replace(" ", "")
    if "-" in normalized:
        lower, upper = normalized.split("-", maxsplit=1)
        return float(lower), float(upper)
    value = float(normalized)
    return value, value


def parse_daily_servings() -> list[StructuredServingRow]:
    text = normalize_text((KNOWLEDGE_DIR / SERVINGS_FILE).read_text())
    rows: list[StructuredServingRow] = []
    pattern = re.compile(
        r"\*\*(?P<calories>[\d,]+) calories per day:\*\* "
        r"Protein Foods: (?P<protein>[^.]+) servings\. "
        r"Dairy: (?P<dairy>[^.]+) servings?\. "
        r"Vegetables: (?P<vegetables>[^.]+) servings?\. "
        r"Fruits: (?P<fruit>[^.]+) servings?\. "
        r"Whole Grains: (?P<grains>[^.]+) servings?\. "
        r"Healthy Fats: (?P<fats>[^.]+) servings?\.",
    )

    for match in pattern.finditer(text):
        protein_min, protein_max = parse_serving_amount(match.group("protein"))
        grains_min, grains_max = parse_serving_amount(match.group("grains"))
        dairy, _ = parse_serving_amount(match.group("dairy"))
        vegetables, _ = parse_serving_amount(match.group("vegetables"))
        fruit, _ = parse_serving_amount(match.group("fruit"))
        fats, _ = parse_serving_amount(match.group("fats"))
        rows.append(
            StructuredServingRow(
                calorie_level=int(match.group("calories").replace(",", "")),
                protein_servings_min=protein_min,
                protein_servings_max=protein_max,
                dairy_servings=dairy,
                vegetable_servings=vegetables,
                fruit_servings=fruit,
                whole_grains_min=grains_min,
                whole_grains_max=grains_max,
                healthy_fats=fats,
                source_text=match.group(0).strip(),
            )
        )
    return rows


def load_manifest() -> dict[str, str]:
    if not INGESTION_MANIFEST_PATH.exists():
        return {}
    return json.loads(INGESTION_MANIFEST_PATH.read_text())


def save_manifest(manifest: dict[str, str]) -> None:
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    INGESTION_MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, sort_keys=True))


async def ingest_knowledge_base(openai_client: OpenAIClient) -> KnowledgeBase:
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    VECTOR_STORE_DIR.mkdir(parents=True, exist_ok=True)
    manifest = load_manifest()
    current_manifest = {
        "pipeline_version": str(INGESTION_PIPELINE_VERSION),
        DIETARY_GUIDELINES_FILE: compute_file_hash(KNOWLEDGE_DIR / DIETARY_GUIDELINES_FILE),
        SCIENTIFIC_FOUNDATIONS_FILE: compute_file_hash(KNOWLEDGE_DIR / SCIENTIFIC_FOUNDATIONS_FILE),
        SERVINGS_FILE: compute_file_hash(KNOWLEDGE_DIR / SERVINGS_FILE),
    }

    pipeline_changed = manifest.get("pipeline_version") != current_manifest["pipeline_version"]
    servings_changed = (
        pipeline_changed
        or manifest.get(SERVINGS_FILE) != current_manifest[SERVINGS_FILE]
        or not SERVING_ROWS_PATH.exists()
    )
    narrative_changed = any(
        manifest.get(name) != current_manifest[name]
        for name in (DIETARY_GUIDELINES_FILE, SCIENTIFIC_FOUNDATIONS_FILE)
    ) or pipeline_changed or not NARRATIVE_CHUNKS_PATH.exists()

    chroma_client = chromadb.PersistentClient(path=str(VECTOR_STORE_DIR))

    if servings_changed:
        serving_rows = parse_daily_servings()
        SERVING_ROWS_PATH.write_text(
            json.dumps([row.model_dump() for row in serving_rows], indent=2, ensure_ascii=False)
        )
    else:
        serving_rows = [StructuredServingRow.model_validate(item) for item in json.loads(SERVING_ROWS_PATH.read_text())]

    if narrative_changed:
        narrative_chunks = build_narrative_chunks()
        NARRATIVE_CHUNKS_PATH.write_text(
            json.dumps(
                [
                    {
                        "chunk_id": chunk.chunk_id,
                        "source_file": chunk.source_file,
                        "heading_path": chunk.heading_path,
                        "text": chunk.text,
                    }
                    for chunk in narrative_chunks
                ],
                indent=2,
                ensure_ascii=False,
            )
        )

        if not openai_client.is_configured:
            raise RuntimeError(
                "OPENAI_API_KEY is required to build narrative embeddings for the nutrition knowledge base."
            )

        try:
            chroma_client.delete_collection(NARRATIVE_COLLECTION_NAME)
        except Exception:
            pass

        collection = chroma_client.create_collection(name=NARRATIVE_COLLECTION_NAME, metadata={"version": "1"})
        documents = [chunk.text for chunk in narrative_chunks]
        embeddings = await openai_client.embed_texts(documents)
        collection.add(
            ids=[chunk.chunk_id for chunk in narrative_chunks],
            documents=documents,
            embeddings=embeddings,
            metadatas=[
                {"source_file": chunk.source_file, "heading_path": chunk.heading_path}
                for chunk in narrative_chunks
            ],
        )
    else:
        collection = chroma_client.get_collection(NARRATIVE_COLLECTION_NAME)

    save_manifest(current_manifest)
    return KnowledgeBase(
        chroma_client=chroma_client,
        collection_name=collection.name,
        serving_rows=serving_rows,
    )


try:
    TOKEN_ENCODING = tiktoken.get_encoding("cl100k_base")
except Exception:
    TOKEN_ENCODING = None
