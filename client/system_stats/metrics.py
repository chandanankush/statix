"""Helpers for collecting host system metrics."""
from __future__ import annotations

import datetime as dt
import os
import platform
import socket
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, Optional

import psutil


def _as_dict(stats_obj: Any) -> Dict[str, Any]:
    """Normalize psutil namedtuple output to plain dicts."""
    if hasattr(stats_obj, "_asdict"):
        return dict(stats_obj._asdict())
    return dict(stats_obj)


def _human_readable_duration(seconds: int) -> str:
    seconds = int(max(0, seconds))
    delta = dt.timedelta(seconds=seconds)
    days = delta.days
    hours, remainder = divmod(delta.seconds, 3600)
    minutes, _ = divmod(remainder, 60)
    parts = []
    if days:
        parts.append(f"{days}d")
    if hours:
        parts.append(f"{hours}h")
    if minutes or not parts:
        parts.append(f"{minutes}m")
    return " ".join(parts)


def _detect_hardware_model(system_name: str) -> Optional[str]:
    try:
        if system_name == "Darwin":
            result = subprocess.run(
                ["/usr/sbin/sysctl", "-n", "hw.model"],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip() or None
        if system_name == "Linux":
            product_path = Path("/sys/devices/virtual/dmi/id/product_name")
            if product_path.exists():
                return product_path.read_text(encoding="utf-8", errors="ignore").strip() or None
    except Exception:  # pragma: no cover - best effort hardware detection
        return None
    return None


def _primary_network_interface() -> Optional[Dict[str, Any]]:
    stats = psutil.net_if_stats()
    addrs = psutil.net_if_addrs()

    duplex_map = {
        getattr(psutil, "NIC_DUPLEX_FULL", 2): "full",
        getattr(psutil, "NIC_DUPLEX_HALF", 1): "half",
        getattr(psutil, "NIC_DUPLEX_UNKNOWN", 0): "unknown",
    }

    for name, stat in stats.items():
        if not stat.isup or name.lower().startswith("lo"):
            continue
        inet_info = next((addr for addr in addrs.get(name, []) if addr.family == socket.AF_INET), None)
        if not inet_info:
            continue
        return {
            "name": name,
            "ipv4": inet_info.address,
            "netmask": inet_info.netmask,
            "broadcast": getattr(inet_info, "broadcast", None),
            "speed_mbps": stat.speed if stat.speed and stat.speed > 0 else None,
            "mtu": stat.mtu,
            "duplex": duplex_map.get(stat.duplex, "unknown"),
        }
    return None


def _resolve_root_path() -> Path:
    root = os.getenv("SYSTEM_STATS_DISK_PATH")
    if root:
        return Path(root).expanduser().resolve()
    if os.name == "nt":
        return Path(os.getenv("SystemDrive", "C:\\"))
    return Path("/")


def collect_system_metrics() -> Dict[str, Any]:
    """Gather CPU, memory, disk, network, and uptime data from the host."""
    cpu_percent = psutil.cpu_percent(interval=0.1)
    logical_cores = psutil.cpu_count(logical=True) or 0
    physical_cores = psutil.cpu_count(logical=False)
    cpu_freq = psutil.cpu_freq()

    memory = _as_dict(psutil.virtual_memory())
    swap = _as_dict(psutil.swap_memory())

    root_path = _resolve_root_path()
    disk_usage = _as_dict(psutil.disk_usage(str(root_path)))
    disk_usage["mount"] = str(root_path)

    net_io = _as_dict(psutil.net_io_counters())
    primary_interface = _primary_network_interface()

    boot_timestamp = psutil.boot_time()
    boot_time = dt.datetime.fromtimestamp(boot_timestamp, tz=dt.timezone.utc).astimezone()
    uptime_seconds = int(time.time() - boot_timestamp)

    uname = platform.uname()
    model = _detect_hardware_model(uname.system)

    return {
        "collected_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "cpu": {
            "percent": cpu_percent,
            "logical_cores": logical_cores,
            "physical_cores": physical_cores,
            "frequency_mhz": cpu_freq.current if cpu_freq else None,
            "min_frequency_mhz": cpu_freq.min if cpu_freq else None,
            "max_frequency_mhz": cpu_freq.max if cpu_freq else None,
            "processor": uname.processor or platform.processor(),
        },
        "memory": memory,
        "swap": swap,
        "disk": disk_usage,
        "network": {
            "io_counters": net_io,
            "primary_interface": primary_interface,
        },
        "uptime": {
            "seconds": uptime_seconds,
            "boot_time": boot_time.isoformat(),
            "human": _human_readable_duration(uptime_seconds),
        },
        "system": {
            "hostname": uname.node,
            "os": uname.system,
            "os_release": uname.release,
            "os_version": uname.version,
            "architecture": uname.machine,
            "platform": platform.platform(),
            "model": model,
        },
    }
