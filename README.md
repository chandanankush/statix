# Monitoring Stack

A lightweight, containerized system monitoring setup with a Python client that ships host metrics to a Flask server for storage and dashboard visualisation.

## Repository Layout
```
client/                   # Metric collection agent and container definition
server/                   # Flask API, dashboard, and container definition
docker-compose.yml        # Combined stack (client + server)
docker-compose.server.yml # Server-only deployment
docker-compose.client.yml # Client-only deployment
ARCHITECTURE.md           # High-level overview of interactions and data flow
README.md                 # Root project guide
```

## Prerequisites
- Docker Engine 20.10+
- Docker Compose V2
- (Optional) Python 3.9+ for local development outside containers

## Deployment Options
- **Full stack (default compose file):**
  ```sh
  docker-compose up --build
  ```
  Visit http://localhost:5000/dashboard.

- **Server only:**
  ```sh
  docker-compose -f docker-compose.server.yml up --build
  ```
  Exposes the API/dashboard on `MONITOR_PORT` (default 5000) and persists data in the `server_data` volume.

- **Client only:**
  ```sh
  export SERVER_URL="http://your-server-host:5000/metrics"
  docker-compose -f docker-compose.client.yml up --build
  ```
  Sends metrics to the URL provided in `SERVER_URL`. Adjust `SCRAPE_INTERVAL` or `CPU_SAMPLE_INTERVAL` as needed via environment variables.

Stop services when finished with `docker-compose down` (matching the compose file you used). Remove volumes with `docker-compose down -v` to reset stored metrics.

### Scaling Clients (full stack)
Simulate multiple monitored nodes by scaling the `client` service:
```sh
docker-compose up --build --scale client=3
```
Each container reports metrics under its unique hostname.

## Local Development
- See `client/README.md` for running the agent directly.
- See `server/README.md` for running the Flask server locally.

## Documentation
- `ARCHITECTURE.md` – component responsibilities, data flow, and deployment overview.

## License
This project is intended for open-source use. Choose and update this section with an appropriate license before publishing.
