# Monitoring Stack

A lightweight monitoring server with an optional system stats microservice. The FastAPI-based client runs directly on macOS or Linux to expose host metrics, while the Flask server stores metrics and renders the dashboard.

## Repository Layout
```
client/                   # System stats FastAPI service, forwarder utility, service templates
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
Install and launch the FastAPI service on the host to expose real system metrics:
```sh
pip install ./client
SYSTEM_STATS_PORT=5001 system-stats-service
```

Use the companion forwarder to push readings into the monitoring server:
```sh
SYSTEM_STATS_URL=http://127.0.0.1:5001/system \
MONITORING_SERVER_METRICS_URL=http://127.0.0.1:5050/metrics \
SYSTEM_STATS_FORWARD_INTERVAL=30 \
system-stats-forwarder
```

See `client/README.md` for environment variables and background service templates (systemd/launchd) for both the API and forwarder.

## Documentation
- `ARCHITECTURE.md` – component responsibilities, data flow, and deployment overview.

## License
This project is intended for open-source use. Choose and update this section with an appropriate license before publishing.
