# Monitoring Server

Flask application that ingests metrics from the system stats forwarder, persists them in SQLite, and exposes both APIs and a Chart.js dashboard.

## Architecture Summary
- `server.py` uses Flask to define REST endpoints, handle persistence, and render the dashboard template.
- Metrics are stored in two tables:
  - `metrics` – time-series of `hostname`, `cpu`, `ram`, `disk`, `timestamp`.
  - `host_details` – latest rich snapshot (`details_json`) per host for dashboard summary cards.
- Templates live under `server/templates/`; `dashboard.html` uses Chart.js and vanilla JS to plot trends and render detail cards.

## Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/metrics` | Accepts JSON payload `{hostname, cpu, ram, disk, timestamp, details?}`. Persists metrics and optional `details` snapshot. |
| `GET` | `/data` | Returns `{count, data}` filtered by `hostname` and/or `timeframe` (`1h`, `24h`, `7d`). |
| `GET` | `/details` | Returns latest snapshot for a given `hostname`. |
| `GET` | `/dashboard` | Renders the dashboard UI. |
| `GET` | `/health` | Health check. |

## Configuration
Environment variables:
- `DATABASE_PATH` (default `server/data/metrics.db`) – SQLite database location. Ensure parent directory exists or use Docker volume/bind mount.

## Running Locally (without Docker)
```sh
python3 -m venv .venv
source .venv/bin/activate
pip install flask gunicorn
export DATABASE_PATH=./data/metrics.db
python server.py
```
Dashboard: `http://127.0.0.1:5050/dashboard`

## Docker Usage
Dockerfile (located in `server/`) installs dependencies and runs `gunicorn`.
### Build & Run
```sh
docker build -t monitoring-server server

docker run --rm \
  --name monitoring-server \
  -p 5050:5000 \
  -e DATABASE_PATH=/app/data/metrics.db \
  -v $(pwd)/server/data:/app/data \
  monitoring-server
```
### Build & Transfer to Another Docker Host
```sh
# Build the image locally
docker build -t monitoring-server:latest server

# Export it to a tarball for copy/scp to another machine
docker save monitoring-server:latest -o monitoring-server.tar

# On the target host, load (and optionally re-tag + push)
docker load -i monitoring-server.tar
docker tag monitoring-server:latest myregistry.example.com/monitoring-server:latest
docker push myregistry.example.com/monitoring-server:latest  # optional
```

> Tip: swap `myregistry.example.com/monitoring-server:latest` with your own registry/namespace. If you use `docker context`
> to point at a remote engine, you can run the build directly on that host instead of saving/loading.

### Compose
`docker-compose.yml` handles build/run and persists data using the `server_data` named volume. Launch with `docker-compose up --build -d`.

## Data Schema
```sql
CREATE TABLE metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp INTEGER NOT NULL,
  hostname TEXT NOT NULL,
  cpu REAL NOT NULL,
  ram REAL NOT NULL,
  disk REAL NOT NULL
);
CREATE INDEX idx_metrics_host_time ON metrics(hostname, timestamp);

CREATE TABLE host_details (
  hostname TEXT PRIMARY KEY,
  details_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

## Dashboard Behaviour
- Polls `/data` every second using the selected `hostname` and `timeframe` filters.
- Updates trend charts for CPU/RAM/Disk usage.
- When a specific host is selected, fetches `/details?hostname=...` to populate summary cards (CPU info, memory usage, storage, system info, network info, uptime).

## Development Notes
- Designed for Python 3.11 in Docker; running locally requires matching dependencies.
- Logging uses `logging.basicConfig` at INFO level. Adjust as needed.
- Extendable: add new tables/endpoints to support additional metrics or alternate persistence layers (PostgreSQL, TimescaleDB, etc.).

## Troubleshooting
- **No data on dashboard** – Ensure forwarder is pushing metrics to `/metrics`; check server logs (`docker-compose logs` or stdout).
- **SQLite locked errors** – Typically transient; consider moving to a server-grade DB if multiple writers are expected.
- **Large datasets** – Add pagination/aggregation or migrate to a database optimised for time series.
