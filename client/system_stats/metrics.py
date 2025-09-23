"""Helpers for collecting host system metrics."""
from __future__ import annotations

import datetime as dt
import time
from typing import Any, Dict

import psutil


def _as_dict(stats_obj: Any) -> Dict[str, Any]:
    """Normalize psutil namedtuple output to plain dicts."""
    if hasattr(stats_obj, "_asdict"):
        return dict(stats_obj._asdict())
    return dict(stats_obj)


def collect_system_metrics() -> Dict[str, Any]:
    """Gather CPU, memory, disk, network, and uptime data from the host."""
    cpu_percent = psutil.cpu_percent(interval=0.1)
    cpu_count = psutil.cpu_count(logical=True)

    memory = _as_dict(psutil.virtual_memory())
    swap = _as_dict(psutil.swap_memory())
    disk = _as_dict(psutil.disk_usage("/"))
    net_io = _as_dict(psutil.net_io_counters())

    boot_timestamp = psutil.boot_time()
    boot_time = dt.datetime.fromtimestamp(boot_timestamp).astimezone()
    uptime_seconds = int(time.time() - boot_timestamp)

    return {
        "cpu": {
            "percent": cpu_percent,
            "count": cpu_count,
        },
        "memory": memory,
        "swap": swap,
        "disk": disk,
        "network": net_io,
        "uptime_seconds": uptime_seconds,
        "boot_time": boot_time.isoformat(),
    }
