"""Flask-based monitoring server that stores metrics and serves a simple dashboard."""
import logging
import os
import sqlite3
import time
from contextlib import closing
from pathlib import Path
from typing import Dict, Iterable, Optional

from flask import Flask, jsonify, render_template, request


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_DB_PATH = BASE_DIR / "data" / "metrics.db"
DB_PATH = os.getenv("DATABASE_PATH", str(DEFAULT_DB_PATH))
TIMEFRAME_PRESETS: Dict[str, int] = {
    "1h": 60 * 60,
    "24h": 24 * 60 * 60,
    "7d": 7 * 24 * 60 * 60,
}

app = Flask(__name__, template_folder=str(BASE_DIR / "templates"))
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


def ensure_database() -> None:
    """Create the SQLite database and metrics table if they do not already exist."""
    db_dir = Path(DB_PATH).parent
    db_dir.mkdir(parents=True, exist_ok=True)
    with closing(sqlite3.connect(DB_PATH)) as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                hostname TEXT NOT NULL,
                cpu REAL NOT NULL,
                ram REAL NOT NULL,
                disk REAL NOT NULL
            )
            """
        )
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_metrics_host_time ON metrics(hostname, timestamp)"
        )
        conn.commit()


def open_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def insert_metric(payload: Dict[str, float]) -> None:
    with closing(open_connection()) as conn:
        conn.execute(
            "INSERT INTO metrics(timestamp, hostname, cpu, ram, disk) VALUES (?, ?, ?, ?, ?)",
            (
                payload["timestamp"],
                payload["hostname"],
                payload["cpu"],
                payload["ram"],
                payload["disk"],
            ),
        )
        conn.commit()


def query_metrics(hostname: Optional[str], timeframe: Optional[str]) -> Iterable[sqlite3.Row]:
    sql = "SELECT timestamp, hostname, cpu, ram, disk FROM metrics"
    params = []
    conditions = []

    if hostname:
        conditions.append("hostname = ?")
        params.append(hostname)

    if timeframe:
        window = TIMEFRAME_PRESETS.get(timeframe)
        if window is None:
            return []
        cutoff = int(time.time()) - window
        conditions.append("timestamp >= ?")
        params.append(cutoff)

    if conditions:
        sql += " WHERE " + " AND ".join(conditions)

    sql += " ORDER BY timestamp ASC"

    with closing(open_connection()) as conn:
        return conn.execute(sql, params).fetchall()


def get_known_hostnames() -> Iterable[str]:
    with closing(open_connection()) as conn:
        rows = conn.execute("SELECT DISTINCT hostname FROM metrics ORDER BY hostname ASC").fetchall()
    return [row[0] for row in rows]


@app.route("/metrics", methods=["POST"])
def receive_metrics():
    payload = request.get_json(silent=True)
    if not payload:
        return jsonify({"error": "Invalid JSON payload"}), 400

    required_fields = {"hostname", "cpu", "ram", "disk", "timestamp"}
    if not required_fields.issubset(payload.keys()):
        missing = required_fields - set(payload.keys())
        return jsonify({"error": f"Missing fields: {', '.join(sorted(missing))}"}), 400

    try:
        timestamp = int(payload["timestamp"])
        metric = {
            "hostname": str(payload["hostname"]),
            "cpu": float(payload["cpu"]),
            "ram": float(payload["ram"]),
            "disk": float(payload["disk"]),
            "timestamp": timestamp,
        }
    except (TypeError, ValueError) as exc:
        logging.warning("Invalid metric payload: %s", exc)
        return jsonify({"error": "Invalid field types"}), 400

    insert_metric(metric)
    return jsonify({"status": "ok"})


@app.route("/data", methods=["GET"])
def data_endpoint():
    hostname = request.args.get("hostname")
    timeframe = request.args.get("timeframe")

    rows = query_metrics(hostname, timeframe)
    if timeframe and timeframe not in TIMEFRAME_PRESETS:
        return jsonify({"error": "Unsupported timeframe"}), 400

    metrics = [
        {
            "timestamp": row["timestamp"],
            "hostname": row["hostname"],
            "cpu": row["cpu"],
            "ram": row["ram"],
            "disk": row["disk"],
        }
        for row in rows
    ]
    return jsonify({"count": len(metrics), "data": metrics})


@app.route("/dashboard", methods=["GET"])
def dashboard():
    hostnames = get_known_hostnames()
    return render_template(
        "dashboard.html",
        hostnames=hostnames,
        timeframe_presets=TIMEFRAME_PRESETS,
        default_timeframe="1h",
    )


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    ensure_database()
    app.run(host="0.0.0.0", port=5000)
else:
    ensure_database()
