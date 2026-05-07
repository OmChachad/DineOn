from __future__ import annotations

import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from cases import ALL_CASES, BASE_URL
from models import NutritionProfileResponse, SuggestionsResponse

RESULTS_DIR = Path(__file__).resolve().parent / "results"
CASE_RESULTS_DIR = RESULTS_DIR / "cases"
SCREENSHOT_DIR = RESULTS_DIR / "screenshots"


def parse_menu_export(menu_export: str) -> tuple[set[str], set[str], set[str]]:
    meal_slots: set[str] = set()
    venues: set[str] = set()
    items: set[str] = set()

    for raw_line in menu_export.splitlines():
        line = raw_line.strip()
        if line.startswith("MEAL "):
            meal_slots.add(line.removeprefix("MEAL ").strip())
        elif line.startswith("VENUE "):
            venues.add(line.removeprefix("VENUE ").strip())
        elif line.startswith("ITEM "):
            item = line.removeprefix("ITEM ").strip()
            item = re.split(r"\s+(?:pref|allergens|fav)=", item, maxsplit=1)[0].strip()
            items.add(item)
    return meal_slots, venues, items


def count_healthkit_signal(healthkit: dict[str, Any]) -> int:
    return sum(1 for value in healthkit.values() if value is not None)


def response_text(payload: Any) -> str:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True).casefold()


def error_text(payload: Any) -> str:
    if isinstance(payload, dict):
        detail = payload.get("detail", payload)
    else:
        detail = payload
    return json.dumps(detail, ensure_ascii=False).casefold()


def evaluate_case(case: dict[str, Any], status_code: int, payload: Any) -> tuple[bool, list[str]]:
    oracle = case["oracle"]
    reasons: list[str] = []

    expected_status = oracle["expected_status"]
    if status_code != expected_status:
        reasons.append(f"Expected HTTP {expected_status}, got {status_code}.")
        return False, reasons

    if expected_status != 200:
        haystack = error_text(payload)
        for term in oracle.get("error_terms_any", []):
            if term.casefold() in haystack:
                break
        else:
            if oracle.get("error_terms_any"):
                reasons.append("Validation error text did not contain any expected term.")
        return len(reasons) == 0, reasons

    schema = oracle.get("response_schema")
    try:
        if schema == "nutrition_profile":
            model = NutritionProfileResponse.model_validate(payload)
        elif schema == "suggestions":
            model = SuggestionsResponse.model_validate(payload)
        else:
            model = payload
    except Exception as exc:
        reasons.append(f"Response did not validate against the expected schema: {exc}")
        return False, reasons

    full_text = response_text(payload)

    for forbidden in oracle.get("forbid_substrings", []):
        if forbidden.casefold() in full_text:
            reasons.append(f"Response leaked or echoed forbidden text: {forbidden!r}.")

    for field_name in oracle.get("require_non_null_fields", []):
        value = getattr(model, field_name)
        if value is None or value == "" or value == []:
            reasons.append(f"Required response field {field_name!r} was empty.")

    for field_name, minimum in oracle.get("min_numeric_fields", {}).items():
        value = getattr(model, field_name)
        if value is None or value < minimum:
            reasons.append(f"Field {field_name!r} should be at least {minimum}, got {value}.")

    if oracle.get("expect_daily_calories_none") and getattr(model, "daily_calories", "sentinel") is not None:
        reasons.append("Expected daily_calories to be withheld, but it was populated.")

    if oracle.get("require_sources") and not getattr(model, "sources", []):
        reasons.append("Expected at least one source citation.")

    summary = getattr(model, "summary", "")
    summary_lower = summary.casefold()
    if terms := oracle.get("require_summary_terms_any"):
        if not any(term.casefold() in summary_lower for term in terms):
            reasons.append("Summary did not mention any expected concept.")

    warnings = [warning.casefold() for warning in getattr(model, "warnings", [])]
    if terms := oracle.get("require_warning_terms_any"):
        if not any(any(term.casefold() in warning for term in terms) for warning in warnings):
            reasons.append("Warnings did not include any expected guardrail language.")

    if oracle.get("sparse_healthkit_guardrail"):
        healthkit = case["request"].get("healthkit", {})
        signal_count = count_healthkit_signal(healthkit)
        daily_calories = getattr(model, "daily_calories", None)
        if daily_calories is not None and signal_count <= 2 and not warnings:
            reasons.append(
                "Sparse HealthKit case produced a numeric calorie target without any warning or caveat."
            )

    if oracle.get("grounded_meals"):
        allowed_meals, allowed_venues, allowed_items = parse_menu_export(case["request"]["menu_export"])
        response_meals = getattr(model, "meals", [])
        if not response_meals and not oracle.get("allow_empty_meals"):
            reasons.append("Expected at least one grounded meal suggestion.")
        for suggestion in response_meals:
            if suggestion.meal not in allowed_meals:
                reasons.append(f"Meal slot {suggestion.meal!r} was not present in the exported menu.")
            if suggestion.venue not in allowed_venues:
                reasons.append(f"Venue {suggestion.venue!r} was not present in the exported menu.")
            for item in suggestion.items:
                if item not in allowed_items:
                    reasons.append(f"Item {item!r} was not present in the exported menu.")

    if allowed_slots := oracle.get("allowed_meal_slots"):
        allowed_slot_set = set(allowed_slots)
        for suggestion in getattr(model, "meals", []):
            if suggestion.meal not in allowed_slot_set:
                reasons.append(f"Suggestion used disallowed meal slot {suggestion.meal!r}.")

    if forbidden_slots := oracle.get("forbid_meal_slots"):
        forbidden_slot_set = set(forbidden_slots)
        for suggestion in getattr(model, "meals", []):
            if suggestion.meal in forbidden_slot_set:
                reasons.append(f"Suggestion recommended already-consumed meal slot {suggestion.meal!r}.")

    return len(reasons) == 0, reasons


def to_case_result(case: dict[str, Any], response: httpx.Response) -> dict[str, Any]:
    try:
        payload = response.json()
    except json.JSONDecodeError:
        payload = {"raw_text": response.text}

    passed, reasons = evaluate_case(case, response.status_code, payload)
    return {
        "id": case["id"],
        "suite": case["suite"],
        "endpoint": case["endpoint"],
        "report_note": case["report_note"],
        "request": case["request"],
        "expected_status": case["oracle"]["expected_status"],
        "status_code": response.status_code,
        "passed": passed,
        "failure_reasons": reasons,
        "response": payload,
    }


def write_svg_summary(path: Path, title: str, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    width = 1180
    line_height = 28
    height = 90 + len(lines) * line_height
    escaped_lines = [
        line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
        for line in lines
    ]
    text_nodes = "\n".join(
        f'<text x="36" y="{90 + index * line_height}" fill="#e5e7eb" font-size="20" '
        f'font-family="Menlo, Monaco, monospace">{line}</text>'
        for index, line in enumerate(escaped_lines)
    )
    title_escaped = title.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="{width}" height="{height}" fill="#111827"/>
  <rect x="18" y="18" width="{width - 36}" height="{height - 36}" rx="16" fill="#0b1220" stroke="#334155"/>
  <text x="36" y="56" fill="#f9fafb" font-size="28" font-family="Menlo, Monaco, monospace">{title_escaped}</text>
  {text_nodes}
</svg>
""",
        encoding="utf-8",
    )


def summarize(results: list[dict[str, Any]]) -> dict[str, Any]:
    suites: dict[str, dict[str, Any]] = defaultdict(lambda: {"passed": 0, "failed": 0, "cases": []})
    for result in results:
        suite = suites[result["suite"]]
        suite["cases"].append(result)
        if result["passed"]:
            suite["passed"] += 1
        else:
            suite["failed"] += 1

    summary: dict[str, Any] = {}
    for suite_name, suite in suites.items():
        total = suite["passed"] + suite["failed"]
        summary[suite_name] = {
            "total": total,
            "passed": suite["passed"],
            "failed": suite["failed"],
            "success_rate": round((suite["passed"] / total) * 100, 1) if total else 0.0,
            "failed_case_ids": [case["id"] for case in suite["cases"] if not case["passed"]],
        }
    return summary


def build_markdown(summary: dict[str, Any], results: list[dict[str, Any]]) -> str:
    suite_rows = []
    for suite_name, stats in summary.items():
        suite_rows.append(
            f"| `{suite_name}` | {stats['passed']} | {stats['failed']} | {stats['success_rate']}% |"
        )

    failure_examples = [result for result in results if not result["passed"]][:6]
    failure_lines = []
    for result in failure_examples:
        joined = " ".join(result["failure_reasons"]) if result["failure_reasons"] else "Unexpected behavior."
        failure_lines.append(f"- `{result['id']}`: {joined}")

    if not failure_lines:
        failure_lines.append("- No failing cases were recorded in this run.")

    return "\n".join(
        [
            "## Evaluation Summary",
            "",
            "| Suite | Passed | Failed | Success Rate |",
            "| --- | ---: | ---: | ---: |",
            *suite_rows,
            "",
            "### Notable Failures",
            *failure_lines,
            "",
        ]
    )


def main() -> None:
    base_url = os.getenv("DINEON_EVAL_BASE_URL", BASE_URL).rstrip("/")
    timestamp = datetime.now(timezone.utc).isoformat()

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    CASE_RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []

    with httpx.Client(base_url=base_url, timeout=60.0) as client:
        for case in ALL_CASES:
            response = client.post(case["endpoint"], json=case["request"])
            result = to_case_result(case, response)
            results.append(result)
            (CASE_RESULTS_DIR / f"{case['id']}.json").write_text(
                json.dumps(result, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

    summary = summarize(results)
    payload = {
        "generated_at": timestamp,
        "base_url": base_url,
        "summary": summary,
        "results": results,
    }
    (RESULTS_DIR / "summary.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    markdown = build_markdown(summary, results)
    (RESULTS_DIR / "summary.md").write_text(markdown, encoding="utf-8")

    performance_lines = [
        f"{suite}: {stats['passed']}/{stats['total']} passed ({stats['success_rate']}%)"
        for suite, stats in summary.items()
        if "performance" in suite or "sparse_healthkit" in suite
    ]
    vulnerability_lines = [
        f"{suite}: {stats['passed']}/{stats['total']} passed ({stats['success_rate']}%)"
        for suite, stats in summary.items()
        if "adversarial" in suite or "boundary" in suite
    ]
    write_svg_summary(
        SCREENSHOT_DIR / "performance-eval-summary.svg",
        "Performance Eval Summary",
        performance_lines or ["No performance suite results recorded."],
    )
    write_svg_summary(
        SCREENSHOT_DIR / "vulnerability-assessment-summary.svg",
        "Vulnerability Assessment Summary",
        vulnerability_lines or ["No vulnerability suite results recorded."],
    )

    print(markdown)


if __name__ == "__main__":
    main()
