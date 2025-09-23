# Monitoring Client

Python-based agent that collects CPU, RAM, and disk usage metrics from the host and pushes them to the monitoring server.

## Configuration
Environment variables control runtime behaviour:
- `SERVER_URL` (default `http://server:5000/metrics`): target server endpoint.
- `SCRAPE_INTERVAL` (default `30`): seconds between metric posts.
- `CPU_SAMPLE_INTERVAL` (default `1.0`): sampling window passed to `psutil.cpu_percent`.
- `CLIENT_LOG_LEVEL` (default `INFO`): Python logging level.

## Run Locally
```sh
python -m venv .venv
source .venv/bin/activate
pip install psutil requests
export SERVER_URL=http://127.0.0.1:5000/metrics
python client.py
```

## Docker Image
The Dockerfile installs dependencies and ships `client.py`.
Build and run the container directly:
```sh
docker build -t monitoring-client .
docker run --rm --name monitoring-client \
  -e SERVER_URL=http://host.docker.internal:5000/metrics \
  monitoring-client
```

When launched via `docker-compose`, the container automatically depends on the `server` service.
