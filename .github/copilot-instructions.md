# GitHub Copilot Instructions for statix

## Project overview
statix is a self-hosted system monitoring stack. The client (FastAPI + psutil) runs natively on each host (macOS, Raspberry Pi). The server (Flask + SQLite) runs in Docker and is published to Docker Hub as `midnightappcoder/statix`.

## Language and framework rules
- **Client**: Python 3.9+, FastAPI, psutil, uvicorn. No Python 3.10+ syntax.
- **Server**: Python 3.9+, Flask, sqlite3 (stdlib). No ORMs. No additional web frameworks.
- **Installers**: Bash 3.2-compatible. No `${var,,}`, no `declare -A`, no bash 4+ features.
- **Dashboard**: Vanilla JS. No bundler, no npm packages.

## Architecture
- `client/system_stats/metrics.py` — pure psutil data collection, no web imports.
- `client/system_stats/api.py` — FastAPI routes only, imports from metrics.py and config.py.
- `client/system_stats/forwarder.py` — standalone script, no new third-party deps.
- `server/server.py` — single-file Flask app; all config from env vars at the top.
- `server/templates/dashboard.html` — single-page Chart.js UI.
- Dockerfile build context is `server/` — all COPY paths must be relative to `server/`.

## Security — always enforce
1. New write/delete endpoints: add `@_require_api_key` decorator.
2. New ingest endpoints: add `@_rate_limit` decorator.
3. Never set `.innerHTML` with API-sourced strings in dashboard JS — use `textContent`.
4. Validate and cap user-supplied hostname length (max 253 chars).
5. Cap any blob stored from user input (see `MAX_DETAILS_BYTES`).
6. `debug=False` always in `app.run()`.

## Adding a new metric
1. Collect in `metrics.py` → `get_system_info()`.
2. Add to forwarder POST payload in `forwarder.py` if it needs a dedicated DB column.
3. Add DB column in `server.py` → `_init_db()`.
4. Populate in `_store_metrics()`, expose in `GET /data`.
5. Visualise in `dashboard.html`.
6. Update config tables in `server/README.md` and `client/README.md` if new env vars added.

## Environment variable config
- Server vars: `DATABASE_PATH`, `STATIX_API_KEY`, `STATIX_RATE_LIMIT`, `STATIX_MAX_CONTENT_LENGTH`, `STATIX_MAX_DETAILS_BYTES`
- Client vars: `SYSTEM_STATS_HOST`, `SYSTEM_STATS_PORT`, `MONITORING_SERVER_METRICS_URL`, `SYSTEM_STATS_FORWARD_INTERVAL`, `SYSTEM_STATS_DISK_PATH`

## Do not
- Add `sudo` to any installer script.
- Use `pip install --user` or `pip install --break-system-packages` — use the project venv at `~/.local/share/statix/venv`.
- Import from server modules in client code, or vice versa.
- Enable Flask debug mode.
- Use `.innerHTML` for user data in the dashboard.
- Guess or hardcode the Docker Hub namespace — it is always `midnightappcoder/statix`.
