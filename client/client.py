"""Simple monitoring client that collects system metrics and posts them to the monitoring server."""
import json
import logging
import os
import socket
import time
from typing import Dict, Any

import psutil
import requests


DEFAULT_INTERVAL_SECONDS = 30.0
DEFAULT_CPU_SAMPLE_SECONDS = 1.0
DEFAULT_SERVER_URL = "http://server:5000/metrics"


def configure_logging() -> None:
    """Configure basic logging for the client."""
    logging_level = os.getenv("CLIENT_LOG_LEVEL", "INFO").upper()
    logging.basicConfig(
        level=getattr(logging, logging_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(message)s",
    )


def collect_metrics(sample_interval: float) -> Dict[str, Any]:
    """Collect CPU, RAM, and disk usage percentages."""
    cpu_percent = psutil.cpu_percent(interval=sample_interval)
    return {
        "hostname": socket.gethostname(),
        "cpu": cpu_percent,
        "ram": psutil.virtual_memory().percent,
        "disk": psutil.disk_usage("/").percent,
        "timestamp": int(time.time()),
    }


def post_metrics(server_url: str, payload: Dict[str, Any]) -> bool:
    """Send collected metrics to the monitoring server."""
    try:
        response = requests.post(
            server_url,
            headers={"Content-Type": "application/json"},
            data=json.dumps(payload),
            timeout=10,
        )
        if response.status_code != 200:
            logging.warning("Unexpected response %s: %s", response.status_code, response.text)
            return False
        return True
    except requests.RequestException as exc:
        logging.error("Failed to post metrics: %s", exc)
        return False


def main() -> None:
    configure_logging()

    server_url = os.getenv("SERVER_URL", DEFAULT_SERVER_URL)
    interval = float(os.getenv("SCRAPE_INTERVAL", DEFAULT_INTERVAL_SECONDS))
    cpu_sample_interval = float(os.getenv("CPU_SAMPLE_INTERVAL", DEFAULT_CPU_SAMPLE_SECONDS))

    # Ensure the CPU sample duration does not exceed the reporting cadence.
    cpu_sample_interval = min(cpu_sample_interval, interval)

    logging.info(
        "Starting monitoring client targeting %s with interval %.1fs (CPU sample %.1fs)",
        server_url,
        interval,
        cpu_sample_interval,
    )

    while True:
        cycle_start = time.time()
        metrics = collect_metrics(cpu_sample_interval)
        logging.debug("Collected metrics: %s", metrics)
        if post_metrics(server_url, metrics):
            logging.info("Successfully sent metrics")
        else:
            logging.warning("Failed to send metrics; will retry on next interval")

        elapsed = time.time() - cycle_start
        sleep_duration = max(0.0, interval - elapsed)
        time.sleep(sleep_duration)


if __name__ == "__main__":
    main()
