# Contributing to statix

Welcome! This document is for humans who want to understand, extend, or contribute to statix. It covers what you can learn from the codebase, how to set up a local development environment, and how to get a change merged.

---

## What you can learn from this project

statix is deliberately built with a small, readable stack — no magic frameworks, no heavy tooling. Every layer is approachable.

| Topic | Where to find it |
|---|---|
| **psutil** — collecting CPU, memory, disk, network metrics | `client/system_stats/metrics.py` |
| **FastAPI** — building a typed REST API, health checks, startup events | `client/system_stats/api.py` |
| **Config via env vars** — twelve-factor app pattern | `client/system_stats/config.py` |
| **Flask** — minimal web server, route decorators, template rendering | `server/server.py` |
| **SQLite from stdlib** — schema init, parameterised queries, `closing()` | `server/server.py` → `_init_db`, `_store_metrics` |
| **Security decorators** — bearer token auth, in-process rate limiting | `server/server.py` → `_require_api_key`, `_rate_limit` |
| **Input validation** — hostname length, payload size caps | `server/server.py` → `POST /metrics` handler |
| **Chart.js** — line charts, dynamic host filter | `server/templates/dashboard.html` |
| **XSS prevention** — why `.innerHTML` is dangerous, safe DOM API patterns | `server/templates/dashboard.html` → `renderHostList()` |
| **Bash scripting** — POSIX/bash 3.2 portability, idempotent installers | `client/install.sh`, `server/install.sh` |
| **Python packaging** — `pyproject.toml`, console scripts, pip editable installs | `client/pyproject.toml` |
| **Dockerising a Flask app** — minimal Dockerfile, build context rules, gunicorn | `server/Dockerfile` |
| **Docker Compose** — named volumes, env-var overrides, named services | `docker-compose.yml` |
| **Multi-arch Docker builds** — `linux/amd64` + `linux/arm64` via buildx | `.github/workflows/docker-publish.yml` |
| **GitHub Actions** — Docker Hub push, path-filtered triggers, manual dispatch | `.github/workflows/docker-publish.yml` |
| **Service management** — launchd (macOS), systemd --user (Linux), auto-restart | `client/service/` templates, `client/install.sh` |

---

## Quick orientation

Read the files in this order for the fastest mental model:

1. **`README.md`** — two-minute user overview.
2. **`ARCHITECTURE.md`** — data flow and component responsibilities.
3. **`client/system_stats/metrics.py`** — data collection, no dependencies other than psutil.
4. **`client/system_stats/api.py`** — how metrics are served.
5. **`client/system_stats/forwarder.py`** — how metrics are forwarded.
6. **`server/server.py`** — ingest, store, serve; the entire server in ~500 lines.
7. **`server/templates/dashboard.html`** — the UI; Chart.js config and the fetch loops.
8. **`AGENTS.md`** — rules and conventions for working in this codebase.

---

## Local development setup

### Prerequisites

- Python 3.9+ (`python3 --version`)
- Docker Desktop (for server testing)
- `curl`, `git`

### Client (FastAPI service + forwarder)

```sh
git clone https://github.com/chandanankush/statix.git
cd statix/client

python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"          # installs package + any dev extras

# Start the stats service on :5001
system-stats-service

# In a second terminal, start the forwarder
MONITORING_SERVER_METRICS_URL=http://localhost:5050/metrics \
SYSTEM_STATS_FORWARD_INTERVAL=10 \
  system-stats-forwarder
```

Test it:
```sh
curl http://localhost:5001/system    # full host snapshot
curl http://localhost:5001/health
```

### Server (Flask + SQLite)

Option A — Docker (recommended, mirrors production exactly):
```sh
cd statix/server
docker build -t statix-local .
docker run --rm -p 5050:5000 -v statix_data:/app/data \
  -e DATABASE_PATH=/app/data/metrics.db \
  statix-local
```

Option B — direct Python (fastest iteration):
```sh
cd statix/server
python3 -m venv .venv
source .venv/bin/activate
pip install flask gunicorn
mkdir -p data
DATABASE_PATH=./data/metrics.db python server.py
```

Visit `http://localhost:5050/dashboard`.

---

## Making changes

### Before you start
- Read `AGENTS.md` — it lists every rule that CI will enforce.
- Check that no open issue or pull request already covers your change.

### Branch and commit conventions

```sh
git checkout -b feat/my-feature    # features
git checkout -b fix/short-description
git checkout -b docs/update-readme
git checkout -b chore/update-deps
```

Commit messages follow the `type: short description` pattern used throughout this repo:
```
feat: add GPU temperature metric
fix: handle missing psutil attribute on Raspberry Pi
docs: add GPU metric to client/README.md config table
chore: bump gunicorn to 22.0
```

### Adding a new metric — step by step

1. **Collect** it in `client/system_stats/metrics.py` inside `get_system_info()`.
2. **Verify** it appears in `GET /system` locally (`curl http://localhost:5001/system`).
3. **Forward** it: add the field to the POST payload dict in `forwarder.py`.
4. **Store** it: add a column in `server/server.py` → `_init_db()` `CREATE TABLE IF NOT EXISTS` statement, and populate it in `_store_metrics()`.
5. **Expose** it: add it to the dict returned by `GET /data`.
6. **Visualise** it: add a new Chart.js dataset or stat card in `dashboard.html`.
7. **Document** it: update the config table in `client/README.md` and `server/README.md` if any new env var was introduced.

### Adding a new API endpoint

```python
@app.route("/my-endpoint", methods=["POST"])
@_rate_limit          # required for any ingest endpoint
@_require_api_key     # required for any write/delete endpoint
def my_endpoint():
    ...
```

Run `curl -X POST http://localhost:5050/my-endpoint` and confirm it returns `401` when `STATIX_API_KEY` is set without a valid token.

### Changing the installer scripts

Test on both platforms before opening a PR:
- **macOS** — run `client/install.sh` in a fresh shell. Check `launchctl list | grep systemstats`.
- **Raspberry Pi / Linux** — test in a Docker container that mimics Raspberry Pi OS:
  ```sh
  docker run --rm -it --platform linux/arm64 \
    debian:bookworm bash
  # inside: apt-get update && apt-get install -y curl python3
  # then paste the install command
  ```

Remember: macOS ships **bash 3.2**. Avoid all bash 4+ syntax.

---

## Pull request checklist

Before opening a PR, confirm every item:

- [ ] New server endpoints have `@_require_api_key` (write) and/or `@_rate_limit` (ingest).
- [ ] No `.innerHTML` with API-sourced data in dashboard JS — only `textContent`/DOM API.
- [ ] `forwarder.py` has no new third-party imports.
- [ ] Bash scripts pass on macOS bash 3.2 (no `${var,,}`, no `declare -A`).
- [ ] Dockerfile COPY paths are relative to `server/` (the build context), not the repo root.
- [ ] `server/README.md` config table updated if new server env vars added.
- [ ] `client/README.md` config table updated if new client env vars added.
- [ ] `ARCHITECTURE.md` updated if the component list or data flow changed.

---

## Project roadmap ideas

The following improvements are not yet implemented and would make good first contributions:

| Idea | Difficulty | Notes |
|---|---|---|
| Alert threshold notifications | Medium | Trigger webhook when CPU/RAM exceeds a threshold |
| GPU temperature metric | Easy | `psutil` has limited GPU support; may need `pynvml` for NVIDIA |
| Per-process CPU/memory breakdown | Medium | Already available in psutil, needs schema changes |
| Authentication on the dashboard UI | Medium | Currently only protects the delete/clean endpoints |
| Prometheus `/metrics` endpoint | Medium | Add an exporter alongside `/data` |
| Time-zone aware timestamps | Easy | Store UTC, convert in dashboard |
| Dark mode toggle | Easy | CSS variable swap in `dashboard.html` |
| PostgreSQL backend | Hard | Abstraction layer in `server.py`, Docker Compose update |
| Alertmanager integration | Hard | Pub/sub or webhook from the server on threshold breach |

---

## Getting help

- Open an issue on GitHub with a description of the bug or feature.
- For security issues, do not open a public issue — contact the maintainer directly.
- Read `AGENTS.md` for the canonical list of codebase rules before asking an AI assistant for help.
