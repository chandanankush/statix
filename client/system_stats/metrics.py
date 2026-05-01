"""Helpers for collecting host system metrics."""
from __future__ import annotations

import datetime as dt
import json
import os
import platform
import shutil
import socket
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

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


_DOCKER_FALLBACK_PATHS = (
    "/usr/local/bin/docker",           # Docker Desktop on macOS (Intel / Rosetta)
    "/opt/homebrew/bin/docker",        # Homebrew docker on Apple Silicon
    "/Applications/Docker.app/Contents/Resources/bin/docker",
)

# ── update-check cache (TTL = 24 h) ──────────────────────────────────────────
_UPDATE_CACHE_TTL: int = 24 * 3600  # seconds
_update_cache: Dict[str, Any] = {}  # key → {"value": ..., "ts": float}


def _cache_get(key: str) -> Any:
    """Return cached value if still within TTL, otherwise sentinel _MISS."""
    entry = _update_cache.get(key)
    if entry and (time.time() - entry["ts"]) < _UPDATE_CACHE_TTL:
        return entry["value"]
    return _MISS


_MISS = object()  # sentinel


def _cache_set(key: str, value: Any) -> Any:
    _update_cache[key] = {"value": value, "ts": time.time()}
    return value


def _check_os_updates_now() -> Dict[str, Any]:
    """Check for available OS updates using the platform package manager."""
    system_name = platform.system()
    try:
        if system_name == "Darwin":
            result = subprocess.run(
                ["softwareupdate", "--list"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            output = result.stdout + result.stderr
            available = "No new software available" not in output and "recommended" in output.lower()
            return {"available": available}
        if system_name == "Linux":
            if shutil.which("apt-get"):
                result = subprocess.run(
                    ["apt-get", "-s", "upgrade"],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    env={**os.environ, "DEBIAN_FRONTEND": "noninteractive"},
                )
                upgraded = sum(
                    1
                    for line in result.stdout.splitlines()
                    if line.startswith("Inst ")
                )
                return {"available": upgraded > 0, "count": upgraded}
            for pkg_mgr in ("dnf", "yum"):
                if shutil.which(pkg_mgr):
                    result = subprocess.run(
                        [pkg_mgr, "check-update", "-q"],
                        capture_output=True,
                        text=True,
                        timeout=60,
                    )
                    # exit code 100 = updates available; 0 = up to date
                    return {"available": result.returncode == 100}
    except Exception:
        pass
    return {"available": None}  # unknown / unsupported


def _get_os_updates() -> Dict[str, Any]:
    """Return OS update info, re-checking at most once every 24 hours."""
    cached = _cache_get("os_updates")
    if cached is not _MISS:
        return cached  # type: ignore[return-value]
    return _cache_set("os_updates", _check_os_updates_now())


def _check_docker_image_update_now(docker_bin: str, image: str) -> Optional[bool]:
    """Return True if a newer image is available, False if up-to-date, None if unknown."""
    try:
        result = subprocess.run(
            [docker_bin, "pull", "--dry-run", image],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if result.returncode == 0:
            output = result.stdout + result.stderr
            return "Downloaded newer image" in output or "Pull complete" in output
    except Exception:
        pass
    return None


def _get_docker_image_update(docker_bin: str, image: str) -> Optional[bool]:
    """Return image update status, re-checking at most once every 24 hours."""
    key = f"docker_image:{image}"
    cached = _cache_get(key)
    if cached is not _MISS:
        return cached  # type: ignore[return-value]
    return _cache_set(key, _check_docker_image_update_now(docker_bin, image))


def _find_docker() -> Optional[str]:
    """Return the docker executable path, or None if not found.

    shutil.which covers PATH (works in interactive shells and Linux systemd).
    The fallback list covers macOS launchd, which runs with a restricted PATH.
    """
    found = shutil.which("docker")
    if found:
        return found
    for candidate in _DOCKER_FALLBACK_PATHS:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def _collect_docker_info() -> Dict[str, Any]:
    """Return Docker container status, or an unavailable marker if Docker is absent/down."""
    docker_bin = _find_docker()
    if docker_bin is None:
        return {"available": False, "error": "not_installed"}
    try:
        result = subprocess.run(
            [docker_bin, "ps", "--all", "--format", "{{json .}}"],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except PermissionError:
        return {"available": False, "error": "permission_denied"}
    except subprocess.TimeoutExpired:
        return {"available": False, "error": "timeout"}
    except Exception:
        return {"available": False, "error": "unknown"}

    if result.returncode != 0:
        return {"available": False, "error": "daemon_not_running"}

    containers: List[Dict[str, Any]] = []
    for line in result.stdout.strip().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            raw = json.loads(line)
        except json.JSONDecodeError:
            continue
        image_name = raw.get("Image", "")
        containers.append({
            "id": raw.get("ID", ""),
            "name": raw.get("Names", "").lstrip("/"),
            "image": image_name,
            "state": raw.get("State", ""),
            "status": raw.get("Status", ""),
            "ports": raw.get("Ports", ""),
            "update_available": _get_docker_image_update(docker_bin, image_name) if image_name else None,
        })

    running = sum(1 for c in containers if c["state"] == "running")
    return {
        "available": True,
        "running": running,
        "total": len(containers),
        "containers": containers,
    }


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
    disk_io = _as_dict(psutil.disk_io_counters())

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
        "disk_io": disk_io,
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
            "os_update": _get_os_updates(),
        },
        "docker": _collect_docker_info(),
    }
