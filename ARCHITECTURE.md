# Monitoring Stack Architecture

## Overview
The stack captures host-level metrics (CPU, RAM, disk) from one or more agents and centralizes storage and visualisation on a Flask server. Docker Compose orchestrates the services so the client containers automatically talk to the server by name.

## Components
- **Client (`client/`)** – Python agent that samples metrics using `psutil` and posts JSON payloads to the server at a configurable interval.
- **Server (`server/`)** – Flask API backed by SQLite. Ingests client payloads, exposes `/data` for retrieval, `/metrics` for ingestion, `/dashboard` for visual analytics, and `/health` for service checks.
- **Dashboard** – Chart.js-powered page rendered from `server/templates/dashboard.html` that polls `/data` and visualises trends per host.
- **Storage** – SQLite database persisted in `server/data/metrics.db` (or a path specified via `DATABASE_PATH`). Docker Compose mounts a named volume to retain history across restarts.
- **Docker Compose (`docker-compose.yml`)** – Defines the client/server services, build contexts, and network. Scaling clients is handled via the `--scale client=N` flag.

## Data Flow
1. Client collects metrics locally with `psutil`.
2. Client posts a JSON payload `{hostname, cpu, ram, disk, timestamp}` to the server's `/metrics` endpoint.
3. Server validates the payload and inserts it into SQLite.
4. Dashboard requests `/data?hostname=...&timeframe=...` to retrieve aggregated metrics.
5. Users interact with the dashboard to filter by host and timeframe, leveraging presets defined in `server/server.py`.

## Deployment Considerations
- **Scaling clients** – Horizontal scaling via Docker Compose or separate hosts; each client needs network access to the server's `/metrics` endpoint.
- **Persistence** – Ensure the server's data directory is mounted or backed up if long-term history matters.
- **Security** – Add authentication/TLS for production. Current setup trusts internal networks.
- **Monitoring** – Use `/health` endpoint with container orchestrators (Docker, Kubernetes) for liveness checks.

## Extensibility
- Add more metrics (network, GPU) by extending `client/client.py` and updating validation in `server/server.py`.
- Swap SQLite for PostgreSQL or TimescaleDB by adjusting database helpers and connection strings.
- Integrate alerting by emitting events when readings cross thresholds.
