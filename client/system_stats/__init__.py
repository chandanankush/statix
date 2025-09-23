"""System stats FastAPI service."""
from importlib.metadata import version

from .api import create_app

__all__ = ["create_app", "__version__"]

try:
    __version__ = version("system-stats-service")
except Exception:  # pragma: no cover - fallback when package metadata missing
    __version__ = "0.1.0"
