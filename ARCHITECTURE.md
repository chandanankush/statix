# Monitoring Stack Architecture

## Overview
The repository now contains two loosely coupled pieces:
- A FastAPI-based **System Stats Service** that runs directly on a host to expose CPU, memory, disk, network, uptime, and boot-time data via REST.
- A Flask **Monitoring Server** that persists metrics (via `/metrics` ingestion) and renders the Chart.js dashboard.

The services can be used independently or combined by adding a lightweight poller that calls `/system` on each host and forwards the payload to the monitoring server.

## Components
- **System Stats Service (`client/`)** – Installable Python package that relies on `psutil` to collect live host metrics and serves them from `/system`. Includes packaging metadata plus systemd and launchd templates for long-running deployments.
- **Monitoring Server (`server/`)** – Flask API backed by SQLite. Provides `/metrics` for ingestion, `/data` for retrieval, `/dashboard` for visualization, and `/health` for readiness checks. Dockerised for simple hosting.
- **Dashboard** – Chart.js-powered page rendered from `server/templates/dashboard.html` that polls `/data` and visualises trends across hosts and timeframes.
- **Storage** – SQLite database persisted at `server/data/metrics.db` (or the path in `DATABASE_PATH`). Docker Compose mounts a named volume so history survives container restarts.
- **Docker Compose (`docker-compose.yml`)** – Runs the monitoring server container. Additional compose file `docker-compose.client.yml` builds the FastAPI service for development, though native installation is recommended for real host metrics.

## Data Flow Example
1. System Stats Service gathers metrics locally with `psutil` and serves them via `GET /system`.
2. An external scheduler or agent (not included) fetches `/system` and forwards the payload to the monitoring server's `/metrics` endpoint.
3. The monitoring server validates and stores incoming metrics in SQLite.
4. The dashboard issues `/data?hostname=...&timeframe=...` to visualise historical readings.

## Deployment Considerations
- **System Stats Service** – Install directly on each monitored machine; configure via environment variables or the provided service templates. Logging goes to stdout/stderr for integration with systemd/launchd logs.
- **Server Persistence** – Keep the `server_data` volume or bind mount to retain history. Regularly back up the SQLite file if metrics are critical.
- **Security** – Add TLS and authentication in production. Restrict dashboard and API access to trusted networks.
- **Horizontal Scaling** – Run the FastAPI service on as many hosts as needed. Use automation (Ansible, cron jobs, etc.) to scrape and relay metrics to the central server.

## Extensibility
- Extend `system_stats/metrics.py` to capture additional metrics (GPU, temperatures, per-interface network stats).
- Replace SQLite with PostgreSQL or TimescaleDB in `server/server.py` for improved scaling and retention policies.
- Build a collector component that periodically scrapes `/system` endpoints and pushes metrics into the monitoring server, or integrate with existing observability pipelines.
