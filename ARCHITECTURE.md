# Monitoring Stack Architecture

## Overview
The repository contains three layers:
- A FastAPI-based **System Stats Service** that runs directly on a host to expose CPU, memory, disk, network, uptime, temperature, OS update status, and Docker container info via REST.
- A lightweight **Forwarder Utility** that polls `/system`, normalises the payload, and POSTs it into the monitoring server.
- A Flask **Monitoring Server** that persists metrics (via `/metrics` ingestion) and renders the Chart.js dashboard.

These components can run on the same machine for local monitoring or be distributed across multiple hosts.

## Components
- **System Stats Service (`client/system_stats/`)** — Installable Python package that uses `psutil` to collect live host metrics and serves them from `/system`. Collects:
  - CPU usage, frequency, core counts, and **temperature** (psutil on Linux/RPi with a sysfs `/sys/class/thermal/thermal_zone0/temp` fallback for restricted systemd environments; `osx-cpu-temp` on macOS Intel; `null` on Apple Silicon).
  - **Processor name** via `/proc/cpuinfo` (`model name:` on x86, `Hardware:` on ARM/Raspberry Pi), falling back to `uname.machine` (e.g. `aarch64`) when the file is absent.
  - All active (up, non-loopback, IPv4) network interfaces with link speed and type. Speed is detected via `ifconfig` media line on macOS and `iw dev link` on Linux WiFi. Entire interface list is cached 5 min.
  - **OS pending update count** via `softwareupdate --list` (macOS), `apt list --upgradable` (Debian/RPi via `/usr/bin/apt`), or `dnf`/`yum check-update` (RHEL). Cached 24 h.
  - Docker container status via `docker ps --all`, including a **per-image update check** (`docker pull --dry-run` on Docker 24+). Cached 24 h per image.
  - Hardware model detected once at startup: device-tree on Raspberry Pi, `sysctl hw.model` on macOS, DMI on x86 Linux.
- **Forwarder (`system-stats-forwarder`)** — Console script that periodically polls the FastAPI endpoint and forwards condensed metrics (`cpu`, `ram`, `swap_percent`, `disk`, `disk_read`, `disk_write`, `net_read`, `net_write`, `load1`, `load5`, `load15`, `cpu_cores`) alongside the rich snapshot to the monitoring server. `disk_read`/`disk_write` and `net_read`/`net_write` are in **MB/s**; the dashboard converts network to Mbps (×8) for display. Supports multiple destinations via comma-separated `MONITORING_SERVER_METRICS_URL`; each destination is contacted independently.
- **Monitoring Server (`server/`)** — Flask API backed by SQLite. Provides `/metrics` for ingestion, `/details` for host snapshots, `/data` for retrieval, `/dashboard` for visualization, and `/health` for readiness checks (including `version` and `expected_client_version` fields for stale-deployment detection). Published to Docker Hub as `midnightappcoder/statix`.
- **Dashboard** — Chart.js-powered page (`server/templates/dashboard.html`) that:
  - Renders live trend charts (CPU %, Per-Core CPU %, Load Average, RAM % + Swap %, Disk I/O MB/s, Network I/O Mbps) with drag-to-reorder. Network values are stored as MB/s and multiplied ×8 for display in Mbps (matching ISP convention). X-axis hides the date component for short timeframes (≤1 h) to reduce label clutter.
  - Shows detail cards for CPU (with temperature), memory, storage, system info (OS update badge), all network interfaces, uptime, **Temperatures** (all sensors, hidden on macOS/Windows), and **Docker** (full-width card with per-container CPU % and memory bars, update badges).
  - Applies **user-configurable alert thresholds**: per-card colour (Amber / Red / Blue / Green / Purple / custom hex), percentage threshold, on/off toggle. Settings persisted in `localStorage`. Cards re-colour instantly on modal close.
  - Shows a **version mismatch warning banner** when the server or any connected client is running a different git SHA than expected. Fetches `expected_client_version` from `/health` at page load; compares against `statix_client_version` in each host’s `/details` snapshot.
  - Responsive layout: single-column on mobile, multi-column card grid on desktop, ultra-wide chart grid on large screens. Supports dark/light theme and multi-host auto-cycling.
- **Storage** — SQLite database persisted at `/app/data/metrics.db`. Docker Compose mounts the `statix_data` named volume so history survives container restarts.
- **Docker Compose (`docker-compose.yml`)** — Runs the monitoring server container pulling `midnightappcoder/statix:latest` from Docker Hub. The client runs natively on each monitored host.
- **CI/CD (`.github/workflows/docker-publish.yml`)** — Automatically builds and pushes a multi-arch image (`linux/amd64` + `linux/arm64`) to Docker Hub on every push to `main`. Passes the git commit SHA as `GIT_SHA` build arg so `STATIX_SERVER_VERSION` and `STATIX_EXPECTED_CLIENT_VERSION` are baked into each image. The client installer records the same SHA to `~/.local/share/statix/client_version` at install time. Together these enable the dashboard's zero-configuration version mismatch detection.

## Data Flow
1. System Stats Service gathers metrics locally with `psutil` and serves them via `GET /system`.
2. The forwarder fetches `/system`, extracts the required fields (including Docker container info), appends the host identifier and timestamp, and POSTs the payload to `/metrics` on each configured monitoring server.
3. The monitoring server validates, stores incoming metrics in SQLite, and records the rich snapshot for the `/details` endpoint.
4. The dashboard issues `/data?hostname=...&timeframe=...` to visualise historical readings and `/details?hostname=...` to populate the summary cards and apply alert threshold colouring.

## Deployment Considerations
- **System Stats Service** — Install on each monitored machine with a single `bash <(curl ...)` command (`client/install.sh`). Creates an isolated Python venv, registers launchd (macOS) or systemd (Linux) services, and starts them automatically. On upgrade, the installer checks whether the existing venv is healthy (imports `fastapi`, `uvicorn`, `psutil`); if any dependency is missing it wipes the venv and does a full reinstall, making it self-healing.
- **Forwarder** — Installed alongside the service by the same installer. Configured with the monitoring server URL and poll interval at install time.
- **Server Persistence** — Keep the `statix_data` Docker volume or bind mount to retain history. Back up `/app/data/metrics.db` regularly (`docker cp statix:/app/data/metrics.db ./backup.db`).
- **Security** — Set `STATIX_API_KEY` to protect destructive endpoints (DELETE/clean). Add TLS via a reverse proxy (nginx, Caddy) in front of the container.
- **Horizontal Scaling** — Run the FastAPI service and forwarder on as many hosts as needed. All agents point at the single monitoring server.

## Extensibility
- Extend `client/system_stats/metrics.py` to capture additional metrics (GPU, per-core temperatures, custom sensors).
- Replace SQLite with PostgreSQL or TimescaleDB in `server/server.py` for improved scaling.
- Integrate alerting via `STATIX_ALERT_WEBHOOK_URL` or extend the forwarder to publish to MQTT/webhook.

---

## Version Sync Architecture

This section explains how statix keeps track of whether the server and every client are running the latest code — with zero manual version bumping.

### Design goals
1. Any push to `main` automatically becomes the new "expected" version.
2. The dashboard always knows what the current latest version is — without being redeployed.
3. Every client reports its own installed version so the dashboard can flag stale hosts individually.
4. Everything works across Docker Hub (server) and pip-from-git (client).

---

### How a version is represented

A **short git SHA** (first 7 characters of the commit hash, e.g. `fd1a0b9`) is used as the version token. There are no manually maintained version strings, no semver bumps required.

---

### Where each SHA comes from

#### Server
```
git push to main
       │
       ▼
 GitHub Actions CI (.github/workflows/docker-publish.yml)
       │  extracts short SHA via docker/metadata-action
       │  passes --build-arg GIT_SHA=<sha>
       ▼
 Docker build (server/Dockerfile)
       │  ARG GIT_SHA=dev
       │  ENV STATIX_SERVER_VERSION=$GIT_SHA
       │  ENV STATIX_EXPECTED_CLIENT_VERSION=$GIT_SHA
       ▼
 Running container
       │  server.py reads os.getenv("STATIX_SERVER_VERSION", "dev")
       │  server.py reads os.getenv("STATIX_EXPECTED_CLIENT_VERSION", "dev")
       ▼
 GET /health  →  { "version": "fd1a0b9", "expected_client_version": "fd1a0b9", "latest_version": "..." }
```

- `version` — the SHA baked into this specific Docker image.
- `expected_client_version` — the SHA the server considers compatible (same build, same commit).
- `latest_version` — fetched **live** from GitHub API (`/repos/chandanankush/statix/commits/main`) by a background thread that runs once at startup then every hour. This is what lets the dashboard know when the *running* image is older than the *latest available* image on Docker Hub.

#### Client
```
bash <(curl .../client/install.sh)
       │
       │  pip install git+https://github.com/chandanankush/statix.git@main#subdirectory=client
       │
       │  git ls-remote https://github.com/chandanankush/statix.git refs/heads/main
       │       → resolves to full SHA, takes first 7 chars
       │
       ▼
 ~/.local/share/statix/client_version   (e.g. "fd1a0b9")
       │
       ▼
 metrics.py reads the file at import time
       │  STATIX_CLIENT_VERSION = _read_client_version()   # "fd1a0b9" or "dev"
       ▼
 GET /system  →  { ..., "statix_client_version": "fd1a0b9" }
       │
       ▼
 forwarder POSTs to /metrics  →  "details" blob contains statix_client_version
       │
       ▼
 GET /details  →  dashboard reads details.statix_client_version
```

---

### How the dashboard uses these values

On every page load the dashboard calls `GET /health` and `GET /details` (for the selected host):

```
Dashboard page load
       │
       ▼
checkServerVersion()  ←  GET /health
       │
       ├─ data.version          =  SHA baked into running container  ("fd1a0b9")
       ├─ data.latest_version   =  latest SHA on main branch         ("fd1a0b9" or newer)
       └─ data.expected_client_version  =  what clients should be on ("fd1a0b9")
              │  (stored in JS variable EXPECTED_CLIENT_VERSION)
              ▼
       Compare version vs latest_version
       ┌─────────────────────────────────────────────────────────────────┐
       │ version == latest_version  →  ✓ Server is up to date (fd1a0b9) │  green
       │ version != latest_version  →  ⚠ Newer image available: pull    │  yellow
       │ latest_version == null     →  ℹ GitHub unreachable, skipped    │  grey
       │ version == "dev"           →  ℹ Dev/source mode, skipped       │  grey
       └─────────────────────────────────────────────────────────────────┘

checkClientVersion(hostname, details)  ←  called after GET /details
       │
       ├─ details.statix_client_version  =  SHA installed on that host  ("fd1a0b9")
       └─ EXPECTED_CLIENT_VERSION        =  from /health above          ("fd1a0b9")
              ▼
       Compare the two
       ┌─────────────────────────────────────────────────────────────────────────────┐
       │ cv == expected  →  ✓ Client on "hostname" is up to date (fd1a0b9)          │  green
       │ cv != expected  →  ⚠ Client on "hostname" outdated (cv → expected). Re-run │  yellow
       │ cv missing/dev  →  ⚠ Client has no version info. Re-run installer          │  yellow
       │ expected == "dev"  →  ℹ Server is in dev mode, check skipped               │  (hidden)
       └─────────────────────────────────────────────────────────────────────────────┘
```

Results are shown in the **Version Status** panel just below the status bar — always visible, not just when something is wrong.

---

### What each deployment scenario looks like

| Scenario | `version` | `latest_version` | `client_version` | Dashboard shows |
|---|---|---|---|---|
| Everything up to date | `fd1a0b9` | `fd1a0b9` | `fd1a0b9` | ✓ Server up to date · ✓ Client up to date |
| Server image stale (not pulled in weeks) | `abc1234` | `fd1a0b9` | `fd1a0b9` | ⚠ Newer server image available: `docker pull …` |
| Client not reinstalled after server update | `fd1a0b9` | `fd1a0b9` | `abc1234` | ⚠ Client on "hostname" outdated: re-run installer |
| Both stale | `abc1234` | `fd1a0b9` | `xyz0000` | ⚠ Both warnings above |
| Dev/local build | `dev` | N/A | `dev` | ℹ Dev mode — checks skipped |
| GitHub API unreachable | `fd1a0b9` | `null` | `fd1a0b9` | ℹ Could not reach GitHub · ✓ Client up to date |

---

### How to fix a warning

| Warning | Fix |
|---|---|
| Server image outdated | Re-run `bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)` on the server host — it pulls the latest image and recreates the container, preserving the data volume. |
| Client on "hostname" outdated | SSH into that host and re-run `bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)` |
| `client_version` shows `dev` | Install via the one-line installer (not `pip install .`) so the version file is written |

---

### Fallback / "dev" mode

Both sides fall back to the string `"dev"` in the following situations — no version check is performed:
- **Server**: running `python server.py` directly from source (no `STATIX_SERVER_VERSION` env var set).
- **Client**: installed with `pip install .` manually instead of the one-line installer (no `~/.local/share/statix/client_version` file present).

When both sides show `"dev"`, the dashboard hides the per-client check entirely to avoid false positives during local development.
