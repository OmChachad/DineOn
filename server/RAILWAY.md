# Railway Deployment

This backend is set up to deploy to Railway as a single FastAPI service from the `/server` directory.

## What is already configured

- Python is pinned to `3.13` in `.python-version`
- `railway.toml` defines:
  - the `RAILPACK` builder
  - the FastAPI start command
  - the `/health` healthcheck
  - a longer startup timeout to allow knowledge-base ingestion

## Railway setup steps

1. Push this repository to GitHub.
2. In Railway, create a new project.
3. Add a new service from your GitHub repository.
4. In the service settings:
   - set **Root Directory** to `/server`
   - set **Config File Path** to `/server/railway.toml`
5. Add the required environment variable:
   - `OPENAI_API_KEY`
6. Generate a public domain for the service from the Railway networking settings.

## Important note about startup

On startup, the app ingests the nutrition knowledge base and builds the local Chroma index in:

- `server/vector_store/`
- `server/artifacts/`

Railway containers can be restarted at any time, so these local files should be treated as ephemeral cache. The app is designed to rebuild them on startup when needed.

That means:

- the first deploy can take longer than a normal FastAPI boot
- the healthcheck timeout is intentionally higher

## Local-equivalent start command

```bash
cd server
poetry run uvicorn main:app --host 0.0.0.0 --port 8000
```
