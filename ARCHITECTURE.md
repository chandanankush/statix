# Monitoring Stack Architecture

## Overview
The repository contains three layers:
- A FastAPI-based **System Stats Service** that runs directly on a host to expose CPU, memory, disk, network, uptime, temperature, OS update status, and Docker container info via REST.
- A lightweight **Forwarder Utility** that polls `/system`, normalises the payload, and POSTs it into the monitoring server.
- A Flask **Monitoring Server** that persists metrics (via `/metrics` ingestion) and renders the Chart.js dashboard.

These components can run on the same machine for local monitoring or be distributed across multiple hosts.

## Components
- **System Stats Service (`client/system_stats/`)** — Installable Python package that uses `psutil` to collect live host metrics and serves them from `/system`. Collects:
  - CPU usage, frequency, core counts, and **temperature** (psutil on Linux/RPi; `osx-cpu-temp` on macOS Intel; `null` on Apple Silicon).
  - All active (up, non-loopback, IPv4) network interfaces with link speed and type. Speed is detected via `ifconfig` media line on macOS and `iw dev link` on Linux WiFi. Entire interface list is cached 5 min.
  - **OS pending update count** via `softwareupdate --list` (macOS), `apt-get -s upgrade` (Debian/RPi), or `dnf`/`yum check-update` (RHEL). Cached 24 h.
  - Docker container status via `docker ps --all`, including a **per-image update check** (`docker pull --dry-run` on Docker 24+). Cached 24 h per image.
  - Hardware model detected once at startup: device-tree on Raspberry Pi, `sysctl hw.model` on macOS, DMI on x86 Linux.
- **Forwarder (`system-stats-forwarder`)** — Console script that periodically polls the FastAPI endpoint and forwards condensed metrics alongside the rich snapshot to the monitoring server. Supports multiple destinations via comma-separated `MONITORING_SERVER_METRICS_URL`; each destination is contacted independently.
- **Monitoring Server (`server/`)** — Flask API backed by SQLite. Provides `/metrics` for ingestion, `/details` for host snapshots, `/data` for retrieval, `/dashboard` for visualization, and `/health` for readiness checks. Published to Docker Hub as `midnightappcoder/statix`.
- **Dashboard** — Chart.js-powered page (`server/templates/dashboard.html`) that:
  - Renders live trend charts (CPU %, RAM %, Disk I/O, Network I/O) with drag-to-reorder.
  - Shows detail cards for CPU (with temperature), memory, storage, system info (OS update badge), all network interfaces, uptime, and Docker (with per-container update badges).
  - Applies **user-configurable alert thresholds**: per-card colour (Amber / Red / Blue / Green / Purple / custom hex), percentage threshold, on/off toggle. Settings persisted in `localStorage`. Cards re-colour instantly on modal close.
  - Supports dark/light theme and multi-host auto-cycling.
- **Storage** — SQLite database persisted at `/app/data/metrics.db`. Docker Compose mounts the `statix_data` named volume so history survives container restarts.
- **Docker Compose (`docker-compose.yml`)** — Runs the monitoring server container pulling `midnightappcoder/statix:latest` from Docker Hub. The client runs natively on each monitored host.
- **CI/CD (`.github/workflows/docker-publish.yml`)** — Automatically builds and pushes a multi-arch image (`linux/amd64` + `linux/arm64`) to Docker Hub on every push to `main` that touches `server/**`.

## Data Flow
1. System Stats Service gathers metrics locally with `psutil` and serves them via `GET /system`.
2. The forwarder fetches `/system`, extracts the required fields (including Docker container info), appends the host identifier and timestamp, and POSTs the payload to `/metrics` on each configured monitoring server.
3. The monitoring server validates, stores incoming metrics in SQLite, and records the rich snapshot for the `/details` endpoint.
4. The dashboard issues `/data?hostname=...&timeframe=...` to visualise historical readings and `/details?hostname=...` to populate the summary cards and apply alert threshold colouring.

## Deployment Considerations
- **System Stats Service** — Install on each monitored machine with a single `bash <(curl ...)` command (`client/install.sh`). Creates an isolated Python venv, registers launchd (macOS) or systemd (Linux) services, and starts them automatically.
- **Forwarder** — Installed alongside the service by the same installer. Configured with the monitoring server URL and poll interval at install time.
- **Server Persistence** — Keep the `statix_data` Docker volume or bind mount to retain history. Back up `/app/data/metrics.db` regularly (`docker cp statix:/app/data/metrics.db ./backup.db`).
- **Security** — Set `STATIX_API_KEY` to protect destructive endpoints (DELETE/clean). Add TLS via a reverse proxy (nginx, Caddy) in front of the container.
- **Horizontal Scaling** — Run the FastAPI service and forwarder on as many hosts as needed. All agents point at the single monitoring server.

## Extensibility
- Extend `client/system_stats/metrics.py` to capture additional metrics (GPU, per-core temperatures, custom sensors).
- Replace SQLite with PostgreSQL or TimescaleDB in `server/server.py` for improved scaling.
- Integrate alerting via `STATIX_ALERT_WEBHOOK_URL` or extend the forwarder to publish to MQTT/webhook.
