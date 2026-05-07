from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager, suppress

from fastapi import FastAPI, HTTPException, Request
from pydantic import ValidationError

from models import NutritionProfileRequest, NutritionProfileResponse, SuggestionsRequest, SuggestionsResponse
from pipeline.classifier import NutritionClassifier
from pipeline.openai_client import OpenAIClient
from pipeline.rag_ingest import ingest_knowledge_base
from pipeline.rag_query import NutritionRAGService
from pipeline.safety import apply_safety_checks
from pipeline.suggestions import NutritionSuggestionsEngine
from pipeline.synthesizer import NutritionSynthesizer


async def initialize_rag(app: FastAPI) -> None:
    try:
        knowledge_base = await ingest_knowledge_base(app.state.openai_client)
        app.state.rag = NutritionRAGService(knowledge_base, app.state.openai_client)
        app.state.rag_ready = True
        app.state.startup_error = None
        print("✅ Nutrition knowledge base initialized.")
    except Exception as exc:  # pragma: no cover - surfaced through /health and request errors
        app.state.rag = None
        app.state.rag_ready = False
        app.state.startup_error = str(exc)
        print(f"❌ Nutrition knowledge base failed to initialize: {exc}")
    finally:
        app.state.rag_init_task = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    openai_client = OpenAIClient()
    app.state.openai_client = openai_client
    app.state.startup_error = None
    app.state.classifier = NutritionClassifier(openai_client)
    app.state.synthesizer = NutritionSynthesizer(openai_client)
    app.state.suggestions = NutritionSuggestionsEngine(openai_client)
    app.state.rag = None
    app.state.rag_ready = False
    app.state.rag_init_task = asyncio.create_task(initialize_rag(app))

    try:
        yield
    finally:
        task = app.state.rag_init_task
        if task is not None and not task.done():
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task


app = FastAPI(title="DineOn Nutrition Server", version="0.1.0", lifespan=lifespan)


@app.get("/health")
async def health(request: Request) -> dict[str, str | bool | None]:
    return {
        "ok": True,
        "openai_configured": request.app.state.openai_client.is_configured,
        "rag_ready": request.app.state.rag_ready,
        "rag_initializing": request.app.state.rag_init_task is not None,
        "startup_error": request.app.state.startup_error,
    }


@app.post("/nutrition/profile", response_model=NutritionProfileResponse)
async def analyze_nutrition_profile(
    payload: NutritionProfileRequest,
    request: Request,
) -> NutritionProfileResponse:
    if not request.app.state.openai_client.is_configured:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured.")
    if request.app.state.startup_error is not None:
        raise HTTPException(status_code=503, detail=request.app.state.startup_error)
    if request.app.state.rag is None:
        raise HTTPException(status_code=503, detail="Nutrition knowledge base is still initializing. Please retry in a moment.")

    try:
        intent = await request.app.state.classifier.classify(payload)
        retrieval = await request.app.state.rag.retrieve(intent, payload.healthkit)
        profile = await request.app.state.synthesizer.synthesize(request=payload, retrieval=retrieval)
        return apply_safety_checks(profile=profile, request=payload, intent=intent)
    except ValidationError as exc:
        raise HTTPException(status_code=400, detail=exc.errors()) from exc


@app.post("/nutrition/suggestions", response_model=SuggestionsResponse)
async def generate_nutrition_suggestions(
    payload: SuggestionsRequest,
    request: Request,
) -> SuggestionsResponse:
    if not request.app.state.openai_client.is_configured:
        raise HTTPException(status_code=503, detail="OPENAI_API_KEY is not configured.")

    try:
        return await request.app.state.suggestions.generate(payload)
    except ValidationError as exc:
        raise HTTPException(status_code=400, detail=exc.errors()) from exc
