# Monitoring Stack Architecture

## Overview
The repository now contains three layers:
- A FastAPI-based **System Stats Service** that runs directly on a host to expose CPU, memory, disk, network, uptime, and boot-time data via REST.
- A lightweight **Forwarder Utility** that polls `/system`, normalises the payload, and POSTs it into the monitoring server.
- A Flask **Monitoring Server** that persists metrics (via `/metrics` ingestion) and renders the Chart.js dashboard.

These components can run on the same machine for local monitoring or be distributed across multiple hosts.

## Components
- **System Stats Service (`client/system_stats/`)** – Installable Python package that relies on `psutil` to collect live host metrics and serves them from `/system`. Includes packaging metadata plus systemd and launchd templates for long-running deployments.
- **Forwarder (`system-stats-forwarder`)** – Console script that periodically polls the FastAPI endpoint and forwards condensed metrics (`hostname`, `cpu`, `ram`, `disk`, `timestamp`) to the monitoring server. Environment-variable driven for easy cron/service usage.
- **Monitoring Server (`server/`)** – Flask API backed by SQLite. Provides `/metrics` for ingestion, `/data` for retrieval, `/dashboard` for visualization, and `/health` for readiness checks. Dockerised for simple hosting.
- **Dashboard** – Chart.js-powered page rendered from `server/templates/dashboard.html` that polls `/data` and visualises trends across hosts and timeframes.
- **Storage** – SQLite database persisted at `server/data/metrics.db` (or the path in `DATABASE_PATH`). Docker Compose mounts a named volume so history survives container restarts.
- **Docker Compose (`docker-compose.yml`)** – Runs the monitoring server container. Additional compose file `docker-compose.client.yml` builds the FastAPI service for development, though native installation is recommended for real host metrics.

## Data Flow
1. System Stats Service gathers metrics locally with `psutil` and serves them via `GET /system`.
2. The forwarder (or any external scheduler) fetches `/system`, extracts the required fields, appends the host identifier and timestamp, and POSTs the payload to `/metrics` on the monitoring server.
3. The monitoring server validates and stores incoming metrics in SQLite.
4. The dashboard issues `/data?hostname=...&timeframe=...` to visualise historical readings.

## Deployment Considerations
- **System Stats Service** – Install directly on each monitored machine; configure via environment variables or the provided service templates. Logging goes to stdout/stderr for integration with systemd/launchd logs.
- **Forwarder** – Can share the same process manager (systemd/launchd) as the API or run under cron. Ensure it points to the correct monitoring server URL and poll interval.
- **Server Persistence** – Keep the `server_data` volume or bind mount to retain history. Regularly back up the SQLite file if metrics are critical.
- **Security** – Add TLS and authentication in production. Restrict dashboard and API access to trusted networks.
- **Horizontal Scaling** – Run the FastAPI service and forwarder on as many hosts as needed. Use automation (Ansible, cron jobs, etc.) to deploy the pair across the fleet.

## Extensibility
- Extend `system_stats/metrics.py` to capture additional metrics (GPU, temperatures, per-interface network stats) and adjust the forwarder/server schema accordingly.
- Replace SQLite with PostgreSQL or TimescaleDB in `server/server.py` for improved scaling and retention policies.
- Integrate alerting by having the forwarder publish to other systems (MQTT, webhook) in addition to the monitoring server.
