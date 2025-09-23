"""Utility to forward system stats service data to the monitoring server."""
from __future__ import annotations

import logging
import os
import socket
import time
from typing import Any, Dict

import requests

DEFAULT_SYSTEM_STATS_URL = "http://127.0.0.1:5001/system"
DEFAULT_MONITORING_METRICS_URL = "http://127.0.0.1:5050/metrics"
DEFAULT_INTERVAL_SECONDS = 30


def get_env(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value else default


def fetch_system_stats(url: str) -> Dict[str, Any]:
    response = requests.get(url, timeout=10)
    response.raise_for_status()
    return response.json()


def transform_payload(stats: Dict[str, Any], throughput: Dict[str, float]) -> Dict[str, Any]:
    memory = stats.get("memory", {})
    disk = stats.get("disk", {})
    cpu = stats.get("cpu", {})

    return {
        "hostname": socket.gethostname(),
        "cpu": float(cpu.get("percent", 0.0)),
        "ram": float(memory.get("percent", 0.0)),
        "disk": float(disk.get("percent", 0.0)),
        "timestamp": int(time.time()),
        "disk_read": throughput.get("read_mb_s", 0.0),
        "disk_write": throughput.get("write_mb_s", 0.0),
        "details": stats,
    }


def post_metrics(url: str, payload: Dict[str, Any]) -> None:
    response = requests.post(url, json=payload, timeout=10)
    response.raise_for_status()


def run_forwarder() -> None:
    system_stats_url = get_env("SYSTEM_STATS_URL", DEFAULT_SYSTEM_STATS_URL)
    metrics_url = get_env("MONITORING_SERVER_METRICS_URL", DEFAULT_MONITORING_METRICS_URL)
    interval = float(get_env("SYSTEM_STATS_FORWARD_INTERVAL", str(DEFAULT_INTERVAL_SECONDS)))

    logging.basicConfig(
        level=os.getenv("SYSTEM_STATS_FORWARD_LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(message)s",
    )
    logging.info(
        "Forwarder started: polling %s every %.1fs -> %s",
        system_stats_url,
        interval,
        metrics_url,
    )

    last_disk_io: Dict[str, Any] | None = None
    last_timestamp: float | None = None

    while True:
        start_time = time.time()
        try:
            stats = fetch_system_stats(system_stats_url)
            disk_io = stats.get("disk_io", {}) or {}
            now = time.time()
            read_rate = 0.0
            write_rate = 0.0
            if last_disk_io and last_timestamp:
                elapsed = max(1e-6, now - last_timestamp)
                read_rate = max(0.0, (disk_io.get("read_bytes", 0) - last_disk_io.get("read_bytes", 0)) / elapsed)
                write_rate = max(0.0, (disk_io.get("write_bytes", 0) - last_disk_io.get("write_bytes", 0)) / elapsed)

            throughput = {
                "read_mb_s": read_rate / (1024 * 1024),
                "write_mb_s": write_rate / (1024 * 1024),
            }

            stats.setdefault("throughput", {})
            stats["throughput"].update(
                {
                    "disk_read_bytes_per_sec": read_rate,
                    "disk_write_bytes_per_sec": write_rate,
                    "disk_read_mb_per_sec": throughput["read_mb_s"],
                    "disk_write_mb_per_sec": throughput["write_mb_s"],
                }
            )

            payload = transform_payload(stats, throughput)
            post_metrics(metrics_url, payload)
            logging.info(
                "Forwarded metrics cpu=%.1f%% ram=%.1f%% disk=%.1f%% read=%.2fMB/s write=%.2fMB/s",
                payload["cpu"],
                payload["ram"],
                payload["disk"],
                throughput["read_mb_s"],
                throughput["write_mb_s"],
            )
            last_disk_io = disk_io
            last_timestamp = now
        except Exception as exc:  # pylint: disable=broad-except
            logging.warning("Forwarding failed: %s", exc)
        elapsed = time.time() - start_time
        time.sleep(max(0.0, interval - elapsed))


def main() -> None:
    run_forwarder()


if __name__ == "__main__":
    main()
