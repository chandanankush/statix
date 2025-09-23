"""Runtime configuration helpers."""
from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Settings:
    host: str = "0.0.0.0"
    port: int = 5001
    log_level: str = "info"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Load settings from environment variables with sensible defaults."""
    host = os.getenv("SYSTEM_STATS_HOST", "0.0.0.0")
    port = int(os.getenv("SYSTEM_STATS_PORT", "5001"))
    log_level = os.getenv("SYSTEM_STATS_LOG_LEVEL", "info").lower()
    return Settings(host=host, port=port, log_level=log_level)
