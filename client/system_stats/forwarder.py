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


def transform_payload(stats: Dict[str, Any]) -> Dict[str, Any]:
    memory = stats.get("memory", {})
    disk = stats.get("disk", {})
    cpu = stats.get("cpu", {})

    return {
        "hostname": socket.gethostname(),
        "cpu": float(cpu.get("percent", 0.0)),
        "ram": float(memory.get("percent", 0.0)),
        "disk": float(disk.get("percent", 0.0)),
        "timestamp": int(time.time()),
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

    while True:
        start_time = time.time()
        try:
            stats = fetch_system_stats(system_stats_url)
            payload = transform_payload(stats)
            post_metrics(metrics_url, payload)
            logging.info(
                "Forwarded metrics cpu=%.1f%% ram=%.1f%% disk=%.1f%%",
                payload["cpu"],
                payload["ram"],
                payload["disk"],
            )
        except Exception as exc:  # pylint: disable=broad-except
            logging.warning("Forwarding failed: %s", exc)
        elapsed = time.time() - start_time
        time.sleep(max(0.0, interval - elapsed))


def main() -> None:
    run_forwarder()


if __name__ == "__main__":
    main()
