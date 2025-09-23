"""FastAPI application exposing host system statistics."""
from __future__ import annotations

from fastapi import FastAPI

from .metrics import collect_system_metrics


def create_app() -> FastAPI:
    app = FastAPI(
        title="System Stats Service",
        description="Lightweight FastAPI service exposing host system metrics.",
        version="0.1.0",
    )

    @app.get("/system", summary="Return current host system metrics", tags=["system"])
    async def system_metrics():
        return collect_system_metrics()

    @app.get("/health", summary="Service health check", tags=["system"])
    async def health():
        return {"status": "ok"}

    return app


app = create_app()
