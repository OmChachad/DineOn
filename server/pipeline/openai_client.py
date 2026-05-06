from __future__ import annotations

import json
import os
from typing import Any

from openai import AsyncOpenAI

CLASSIFIER_MODEL = "gpt-5.4-mini"
SYNTHESIZER_MODEL = "gpt-5.4-mini"
EMBEDDING_MODEL = "text-embedding-3-small"


class OpenAIClient:
    def __init__(self, api_key: str | None = None) -> None:
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        self._client = AsyncOpenAI(api_key=self.api_key) if self.api_key else None

    @property
    def is_configured(self) -> bool:
        return self._client is not None

    def require_client(self) -> AsyncOpenAI:
        if self._client is None:
            raise RuntimeError("OPENAI_API_KEY is not configured.")
        return self._client

    async def embed_texts(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        client = self.require_client()
        response = await client.embeddings.create(
            model=EMBEDDING_MODEL,
            input=texts,
            encoding_format="float",
        )
        return [item.embedding for item in response.data]

    async def generate_json(
        self,
        *,
        model: str,
        schema_name: str,
        schema: dict[str, Any],
        instructions: str,
        payload: dict[str, Any],
        max_output_tokens: int,
    ) -> dict[str, Any]:
        client = self.require_client()
        self._log_prompt(
            model=model,
            schema_name=schema_name,
            instructions=instructions,
            payload=payload,
        )
        response = await client.responses.create(
            model=model,
            instructions=instructions,
            input=json.dumps(payload, ensure_ascii=False, indent=2),
            max_output_tokens=max_output_tokens,
            text={
                "verbosity": "low",
                "format": {
                    "type": "json_schema",
                    "name": schema_name,
                    "schema": schema,
                    "strict": True,
                },
            },
        )
        self._log_output(
            model=model,
            schema_name=schema_name,
            output_text=response.output_text,
        )
        return json.loads(response.output_text)

    def _log_prompt(
        self,
        *,
        model: str,
        schema_name: str,
        instructions: str,
        payload: dict[str, Any],
    ) -> None:
        print(
            "\n===== OPENAI PROMPT START =====\n"
            f"model: {model}\n"
            f"schema: {schema_name}\n"
            "instructions:\n"
            f"{instructions}\n\n"
            "input:\n"
            f"{json.dumps(payload, ensure_ascii=False, indent=2)}\n"
            "===== OPENAI PROMPT END =====\n"
        )

    def _log_output(
        self,
        *,
        model: str,
        schema_name: str,
        output_text: str,
    ) -> None:
        print(
            "\n===== OPENAI OUTPUT START =====\n"
            f"model: {model}\n"
            f"schema: {schema_name}\n"
            "output:\n"
            f"{output_text}\n"
            "===== OPENAI OUTPUT END =====\n"
        )
