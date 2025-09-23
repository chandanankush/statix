# Monitoring Server

Flask application that stores metrics from monitoring clients and exposes REST APIs plus a Chart.js dashboard.

## Configuration
Environment variables:
- `DATABASE_PATH` (default `server/data/metrics.db`): SQLite location for persisted metrics.

## Run Locally
```sh
python -m venv .venv
source .venv/bin/activate
pip install flask gunicorn
export DATABASE_PATH=./data/metrics.db
python server.py
```
Visit the dashboard at http://127.0.0.1:5000/dashboard.

## Docker Image
The Dockerfile installs Flask and Gunicorn and copies the application code plus templates.
Build and run manually:
```sh
docker build -t monitoring-server .
docker run --rm --name monitoring-server -p 5000:5000 \
  -e DATABASE_PATH=/app/data/metrics.db \
  -v $(pwd)/data:/app/data \
  monitoring-server
```

Within `docker-compose`, a named volume (`server_data`) persists the SQLite database.
