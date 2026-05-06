from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request
from pydantic import ValidationError

from models import NutritionProfileRequest, NutritionProfileResponse
from pipeline.classifier import NutritionClassifier
from pipeline.openai_client import OpenAIClient
from pipeline.rag_ingest import ingest_knowledge_base
from pipeline.rag_query import NutritionRAGService
from pipeline.safety import apply_safety_checks
from pipeline.synthesizer import NutritionSynthesizer


@asynccontextmanager
async def lifespan(app: FastAPI):
    openai_client = OpenAIClient()
    app.state.openai_client = openai_client
    app.state.startup_error = None
    app.state.classifier = NutritionClassifier(openai_client)
    app.state.synthesizer = NutritionSynthesizer(openai_client)
    app.state.rag = None

    try:
        knowledge_base = await ingest_knowledge_base(openai_client)
        app.state.rag = NutritionRAGService(knowledge_base, openai_client)
    except Exception as exc:  # pragma: no cover - surfaced through /health and request errors
        app.state.startup_error = str(exc)
    yield


app = FastAPI(title="DineOn Nutrition Server", version="0.1.0", lifespan=lifespan)


@app.get("/health")
async def health(request: Request) -> dict[str, str | bool | None]:
    return {
        "ok": request.app.state.startup_error is None,
        "openai_configured": request.app.state.openai_client.is_configured,
        "startup_error": request.app.state.startup_error,
    }


@app.post("/nutrition/profile", response_model=NutritionProfileResponse)
async def analyze_nutrition_profile(
    payload: NutritionProfileRequest,
    request: Request,
) -> NutritionProfileResponse:
    if request.app.state.startup_error is not None or request.app.state.rag is None:
        raise HTTPException(status_code=503, detail=request.app.state.startup_error or "Nutrition pipeline unavailable.")
    if not request.app.state.openai_client.is_configured:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured.")

    try:
        intent = await request.app.state.classifier.classify(payload)
        retrieval = await request.app.state.rag.retrieve(intent, payload.healthkit)
        profile = await request.app.state.synthesizer.synthesize(request=payload, retrieval=retrieval)
        return apply_safety_checks(profile=profile, request=payload, intent=intent)
    except ValidationError as exc:
        raise HTTPException(status_code=400, detail=exc.errors()) from exc
