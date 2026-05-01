# Agent Instructions for statix

Guidelines for AI coding agents (GitHub Copilot, Claude, Cursor, etc.) working in this repository.

---

## Documentation map

There are **three README files** in this repo. Each is scoped to a different audience and layer. Always read the relevant one before making changes to that layer.

| File | Scope | Use it when… |
|---|---|---|
| `README.md` | High-level user guide | You need to understand what statix is, how to install it end-to-end, or what the one-line commands are. This is the entry point for new users. |
| `client/README.md` | Client agent only | You are working on `client/system_stats/`, `client/install.sh`, or `client/uninstall.sh`. Contains: install/uninstall commands, service management (launchd/systemd), all client env vars, the REST API surface (`GET /system`, `GET /health`), and the payload format sent to the server. `GET /system` includes a `docker` key with container counts and per-container details (or `available: false` with an error code when Docker is absent or the daemon is down). |
| `server/README.md` | Server only | You are working on `server/server.py`, `server/Dockerfile`, `server/install.sh`, `server/uninstall.sh`, or `server/templates/dashboard.html`. Contains: Docker Hub install command, Compose usage, all server env vars (including security vars), the full API endpoint table with auth requirements, Docker Hub tag strategy, and useful ops commands. |

When a task touches **both** client and server, read all three. When updating env vars, config, or API surface, update the matching README(s) as part of the same change.

---

## What this repo is

**statix** is a self-hosted system monitoring stack:

| Layer | Technology | Location |
|---|---|---|
| Host agent — metrics collector | FastAPI + psutil | `client/system_stats/` |
| Host agent — forwarder | Python script | `client/system_stats/forwarder.py` |
| Monitoring server | Flask + SQLite | `server/server.py` |
| Dashboard | Chart.js (single HTML template) | `server/templates/dashboard.html` |
| One-line installers | Bash | `client/install.sh`, `server/install.sh` |
| Uninstallers | Bash | `client/uninstall.sh`, `server/uninstall.sh` |
| Container image | Docker (multi-arch) | `midnightappcoder/statix` on Docker Hub |
| CI/CD | GitHub Actions | `.github/workflows/docker-publish.yml` |

---

## Repo structure

```
statix/
├── AGENTS.md                   ← you are here
├── ARCHITECTURE.md             ← high-level data flow and design
├── CONTRIBUTING.md             ← contributor guide and learning path
├── README.md                   ← quick-start for users
├── docker-compose.yml          ← server orchestration (pulls Docker Hub image)
├── client/
│   ├── install.sh              ← one-line installer (macOS + Raspberry Pi)
│   ├── uninstall.sh            ← one-line uninstaller
│   ├── pyproject.toml          ← Python package metadata
│   ├── setup.py
│   ├── README.md
│   ├── service/
│   │   ├── launchd/            ← macOS plist templates
│   │   └── systemd/            ← Linux unit file templates
│   └── system_stats/
│       ├── __init__.py
│       ├── api.py              ← FastAPI app (GET /system, GET /health)
│       ├── config.py           ← env-var config constants
│       ├── forwarder.py        ← polls /system, POSTs to monitoring server
│       ├── main.py             ← uvicorn entrypoint
│       └── metrics.py          ← psutil data collection
└── server/
    ├── install.sh              ← one-line Docker server installer
    ├── uninstall.sh            ← removes container, optionally image/data
    ├── Dockerfile              ← build context is server/ (not repo root)
    ├── README.md
    ├── server.py               ← Flask app — ingestion, storage, API, dashboard
    └── templates/
        └── dashboard.html      ← Chart.js dashboard (single-page)
```

---

## Key conventions

### Python (client)
- **Python 3.9+** required. No walrus operator, no 3.10+ match statements.
- All config comes from **environment variables** defined in `client/system_stats/config.py`.
- `metrics.py` returns plain dicts — keep it free of web framework imports.
- `api.py` imports from `metrics.py` and `config.py` only. No circular imports.
- `forwarder.py` must remain a single-file, self-contained script — no new dependencies.
- Package is installed as `system-stats-service` and `system-stats-forwarder` console scripts.

### Python (server)
- **Flask** only — do not introduce additional web frameworks.
- All config is via **environment variables** (see `server/server.py` top-level constants).
- Database access uses `sqlite3` with `closing()` context managers — always close connections explicitly.
- Security decorators `_require_api_key` and `_rate_limit` must be applied to any new write or delete endpoint.
- Never log raw exception details from user-supplied data (prevent info leakage).
- `app.run(debug=False)` — never enable debug mode.

### Bash installers
- Written for **bash 3.2** compatibility (macOS ships bash 3.2). No `${var,,}`, no `declare -A`, no bash 4+ features.
- Always check for an existing install before writing files (upgrade path).
- Use `tr '[:upper:]' '[:lower:]'` for case folding, not `${var,,}`.
- Do not use `sudo` — everything installs into the user's home directory.
- Exit on any error (`set -euo pipefail`) at the top of every script.

### Docker
- Dockerfile build context is `server/` (not the repo root). COPY paths must be relative to `server/`.
- Image published as `midnightappcoder/statix` with tags: `latest`, `1.0.1`, and short git SHA.
- Multi-arch: `linux/amd64` + `linux/arm64` (for Raspberry Pi).

### JavaScript (dashboard)
- Vanilla JS only — no bundler, no npm.
- Never set `.innerHTML` with user-supplied data. Use DOM API (`createElement`, `textContent`, `appendChild`).
- The `AUTH_REQUIRED` constant comes from the Flask template. Always call `getAuthHeaders()` on destructive API calls.

---

## Security rules — never violate

1. All new POST/PUT/PATCH/DELETE endpoints **must** use `@_require_api_key`.
2. Never trust user-supplied hostname strings — enforce `MAX_HOSTNAME_LEN = 253`.
3. Any blob stored to SQLite from user input must be capped (see `MAX_DETAILS_BYTES`).
4. Dashboard HTML: no `.innerHTML` with API-sourced strings.
5. Rate limiting (`@_rate_limit`) must be applied to any high-frequency ingest endpoint.
6. `flask run` or `app.run(debug=True)` is never acceptable in production code paths.

---

## Environment variables reference

### Server (`server/server.py`)

| Variable | Default | Purpose |
|---|---|---|
| `DATABASE_PATH` | `/app/data/metrics.db` | SQLite path inside container |
| `STATIX_API_KEY` | *(unset)* | Bearer token for write/delete endpoints |
| `STATIX_RATE_LIMIT` | `60` | Max POST `/metrics` requests / IP / minute |
| `STATIX_MAX_CONTENT_LENGTH` | `524288` | Max accepted body size (bytes) |
| `STATIX_MAX_DETAILS_BYTES` | `65536` | Max stored details blob size (bytes) |

### Client (`client/system_stats/config.py`)

| Variable | Default | Purpose |
|---|---|---|
| `SYSTEM_STATS_HOST` | `0.0.0.0` | FastAPI bind address |
| `SYSTEM_STATS_PORT` | `5001` | FastAPI port |
| `SYSTEM_STATS_LOG_LEVEL` | `info` | uvicorn log level |
| `MONITORING_SERVER_METRICS_URL` | `http://192.168.0.209:5050/metrics` | Forwarder destination(s). Accepts a single URL or a comma-separated list for multi-server forwarding. Each destination fails independently. |
| `SYSTEM_STATS_FORWARD_INTERVAL` | `30` | Poll interval (seconds) |
| `SYSTEM_STATS_DISK_PATH` | `/` | Disk mount to report |

---

## Common tasks

### Run the server locally (without Docker)
```sh
cd server
pip install flask gunicorn
DATABASE_PATH=./data/metrics.db python server.py
```

### Run the client locally (dev mode)
```sh
cd client
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
system-stats-service &   # FastAPI on :5001
system-stats-forwarder   # polls :5001 → monitoring server
```

### Build the Docker image
```sh
cd server
docker build -t statix-local .
docker run -p 5050:5000 -v statix_data:/app/data statix-local
```

### Test the API (server running locally)
```sh
# Health check
curl http://localhost:5050/health

# Push a test metric
curl -X POST http://localhost:5050/metrics \
  -H "Content-Type: application/json" \
  -d '{"hostname":"test-host","cpu":5.2,"ram":40.1,"disk":20.0,"timestamp":1746092624}'

# List hosts
curl http://localhost:5050/hosts

# Query data
curl "http://localhost:5050/data?hostname=test-host&timeframe=1h"
```

### Add a new metric field
1. Collect it in `client/system_stats/metrics.py` (add to `get_system_info()` return dict).
2. Expose it in `client/system_stats/api.py` if needed (it auto-includes via `details`).
3. If it belongs in the top-level metrics payload, add it to the forwarder's POST in `forwarder.py`.
4. Add a DB column in `server/server.py` → `_init_db()` `CREATE TABLE` statement.
5. Populate it in `_store_metrics()` and expose it via `GET /data`.
6. Update `dashboard.html` to visualise it.

---

## Pull request checklist

- [ ] No new dependency added to `forwarder.py`.
- [ ] New server endpoints have `@_require_api_key` (write) and `@_rate_limit` (ingest).
- [ ] No `.innerHTML` with API-sourced strings in dashboard JS.
- [ ] Bash scripts tested on macOS (bash 3.2) and on Raspberry Pi OS.
- [ ] Dockerfile COPY paths are relative to `server/` build context.
- [ ] `server/README.md` config table updated if new server env vars were added.
- [ ] `client/README.md` config table updated if new client env vars were added.
- [ ] `ARCHITECTURE.md` updated if the data flow or component list changed.
