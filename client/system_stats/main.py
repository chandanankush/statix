"""CLI entrypoint for launching the FastAPI service with Uvicorn."""
from __future__ import annotations

import logging

import uvicorn

from .api import app
from .config import get_settings


def main() -> None:
    settings = get_settings()
    logging.basicConfig(level=settings.log_level.upper(), format="%(asctime)s %(levelname)s %(message)s")

    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level,
    )


if __name__ == "__main__":
    main()
