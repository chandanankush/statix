# Statix Server

Flask-based monitoring server that ingests host metrics, persists them in SQLite, and renders a Chart.js dashboard. Published to Docker Hub as [`midnightappcoder/statix`](https://hub.docker.com/r/midnightappcoder/statix) and built for `linux/amd64` and `linux/arm64` (Raspberry Pi).

## One-Line Install

Requires Docker. Works on any machine — Linux, macOS, or a server/VPS.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```

The installer will prompt for:
- **Dashboard port** — defaults to `5050`
- **Data directory** — defaults to `~/.local/share/statix/data`

Pass flags to skip prompts:
```sh
curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh \
  | bash -s -- --port 5050 --data-dir /opt/statix/data
```

Re-running the same command **upgrades** to the latest image, keeping your port and data directory.

### Uninstall
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/uninstall.sh)
```

---

## Docker Compose

If you prefer Compose:
```sh
docker-compose up -d
```
Dashboard: `http://localhost:5050/dashboard`

Override the port:
```sh
MONITOR_PORT=8080 docker-compose up -d
```

To force a local build instead of pulling from Docker Hub:
```sh
docker-compose up --build -d
```

---

## Manual Docker Run

```sh
docker run -d \
  --name statix \
  --restart unless-stopped \
  -p 5050:5000 \
  -v statix_data:/app/data \
  -e DATABASE_PATH=/app/data/metrics.db \
  midnightappcoder/statix:latest
```

---

## Configuration

| Environment Variable | Default | Description |
|---|---|---|
| `DATABASE_PATH` | `/app/data/metrics.db` | Path to the SQLite database inside the container. Mount a volume to persist data. |

---

## API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/metrics` | Ingest a metrics payload from the forwarder. |
| `GET` | `/data` | Query stored metrics. Params: `hostname`, `timeframe` (`1h`, `24h`, `7d`). |
| `GET` | `/details` | Latest rich snapshot for a host. Param: `hostname`. |
| `GET` | `/hosts` | List all known hosts with last-seen timestamps. |
| `POST` | `/hosts/<hostname>/clean` | Delete metric history for a host (keeps host_details). |
| `DELETE` | `/hosts/<hostname>` | Remove a host and all its data entirely. |
| `GET` | `/dashboard` | Chart.js dashboard UI. |
| `GET` | `/health` | Health check — returns `{"status": "ok"}`. |

---

## Docker Hub & CI

The image is automatically built and pushed to Docker Hub on every push to `main` that touches `server/**`, via the GitHub Actions workflow at `.github/workflows/docker-publish.yml`.

Images are tagged:
- `midnightappcoder/statix:latest` — always points to the most recent `main` build
- `midnightappcoder/statix:<git-sha>` — immutable per-commit tag

To pull a specific commit:
```sh
docker pull midnightappcoder/statix:<sha>
```

### Setting up Docker Hub secrets (one-time, repo owner only)

1. Go to **GitHub → Settings → Secrets and variables → Actions**
2. Add `DOCKERHUB_USERNAME` (your Docker Hub username)
3. Add `DOCKERHUB_TOKEN` (a Docker Hub Access Token — create one at hub.docker.com → Account Settings → Security)

After that, every push to `main` will automatically publish a new image.

---

## Useful Commands

```sh
# Follow logs
docker logs -f statix

# Stop / start
docker stop statix
docker start statix

# Open a shell inside the container
docker exec -it statix bash

# Check health
curl http://127.0.0.1:5050/health
```
