from pipeline.rag_ingest import build_narrative_chunks, parse_daily_servings


def test_daily_servings_table_parses_all_calorie_rows() -> None:
    rows = parse_daily_servings()

    assert len(rows) == 12
    assert rows[0].calorie_level == 1000
    assert rows[-1].calorie_level == 3200
    assert rows[3].protein_servings_min == 2.5
    assert rows[3].protein_servings_max == 3.5


def test_narrative_chunking_generates_metadata() -> None:
    chunks = build_narrative_chunks()

    assert len(chunks) >= 20
    assert any(chunk.source_file == "Dietary_Guidelines_For_Americans.md" for chunk in chunks)
    assert any(chunk.source_file == "Scientific_Foundations.md" for chunk in chunks)
    assert all(chunk.heading_path for chunk in chunks)
