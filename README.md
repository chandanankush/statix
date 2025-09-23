# Monitoring Stack

A lightweight monitoring server with an optional system stats microservice. The FastAPI-based client runs directly on macOS or Linux to expose host metrics, while the Flask server stores metrics and renders the dashboard.

## Repository Layout
```
client/                   # System stats FastAPI service (installable package + service templates)
server/                   # Flask API, dashboard, and container definition
docker-compose.yml        # Monitoring server deployment
docker-compose.server.yml # Alias compose file for the server
docker-compose.client.yml # Optional containerised system-stats service (container metrics)
ARCHITECTURE.md           # High-level overview of interactions and data flow
README.md                 # Root project guide
```

## Prerequisites
- Docker Engine 20.10+ (for the server container)
- Docker Compose V2
- Python 3.9+ (for installing/running the system stats service natively)

## Deploying the Monitoring Server
Run the Flask dashboard via Docker Compose:
```sh
docker-compose up --build -d
```
Override the exposed port with `MONITOR_PORT` if required, then browse to `http://localhost:5000/dashboard` (or the port you set). Stop the stack with `docker-compose down` and remove persisted metrics using `docker-compose down -v`.

## System Stats Service (Client)
The client service is now a standalone FastAPI application intended to run directly on the host so it can observe real system metrics. Installation, API details, and background service templates are documented in `client/README.md`.

An optional `docker-compose.client.yml` is available for development, but metrics collected inside a container reflect container namespaces rather than the host.

## Documentation
- `ARCHITECTURE.md` – component responsibilities, data flow, and deployment overview.

## License
This project is intended for open-source use. Choose and update this section with an appropriate license before publishing.
