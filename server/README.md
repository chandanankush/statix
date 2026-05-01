# Statix Server

Flask-based monitoring server that ingests host metrics, persists them in SQLite, and renders a Chart.js dashboard. Published to Docker Hub as [`midnightappcoder/statix`](https://hub.docker.com/r/midnightappcoder/statix) — built for `linux/amd64` and `linux/arm64` (Raspberry Pi).

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

## Manual Docker Run

```sh
# Latest
docker run -d \
  --name statix \
  --restart unless-stopped \
  -p 5050:5000 \
  -v statix_data:/app/data \
  -e DATABASE_PATH=/app/data/metrics.db \
  midnightappcoder/statix:latest
```

Dashboard: `http://localhost:5050/dashboard`

---

## Docker Compose

```sh
docker compose up -d
```

Override the port:
```sh
MONITOR_PORT=8080 docker compose up -d
```

Force a local build instead of pulling from Docker Hub:
```sh
docker compose up --build -d
```

---

## Configuration

All settings are environment variables passed to the container.

### Storage

| Variable | Default | Description |
|---|---|---|
| `DATABASE_PATH` | `/app/data/metrics.db` | SQLite database path inside the container. Always mount a volume at `/app/data` to persist data across restarts. |

### Security

| Variable | Default | Description |
|---|---|---|
| `STATIX_API_KEY` | *(unset)* | When set, all write/delete endpoints require `Authorization: Bearer <key>`. Leave unset on trusted networks. The dashboard will prompt for the key automatically. |
| `STATIX_RATE_LIMIT` | `60` | Maximum POST `/metrics` requests per IP per minute before a `429` is returned. |
| `STATIX_MAX_CONTENT_LENGTH` | `524288` (512 KB) | Maximum accepted request body size in bytes for POST `/metrics`. |
| `STATIX_MAX_DETAILS_BYTES` | `65536` (64 KB) | Maximum size of the `details` snapshot stored per host. Oversized blobs are dropped with a log warning. |

### Data retention

| Variable | Default | Description |
|---|---|---|
| `STATIX_RETENTION_DAYS` | `30` | Delete metric rows older than this many days. A background thread runs hourly. Set to `0` to keep data forever. |

### Host status

| Variable | Default | Description |
|---|---|---|
| `STATIX_OFFLINE_THRESHOLD` | `300` | Seconds since the last metric before a host is considered offline in `GET /hosts`. Must match the dashboard's expectation (default 5 min). |

### Alerting (optional)

| Variable | Default | Description |
|---|---|---|
| `STATIX_ALERT_WEBHOOK_URL` | *(unset)* | URL to POST a JSON alert payload to when a threshold is breached. Leave unset to disable alerting. |
| `STATIX_ALERT_CPU_THRESHOLD` | `0` (disabled) | CPU % at or above which an alert fires. `0` disables CPU alerts. |
| `STATIX_ALERT_RAM_THRESHOLD` | `0` (disabled) | RAM % at or above which an alert fires. `0` disables RAM alerts. |
| `STATIX_ALERT_COOLDOWN` | `300` | Minimum seconds between repeated alerts for the same host + metric. |

Alert payload sent to the webhook:
```json
{"hostname": "my-host", "metric": "cpu", "value": 95.2, "threshold": 90.0, "timestamp": 1746092624}
```

Example with API key enabled:
```sh
docker run -d \
  --name statix \
  --restart unless-stopped \
  -p 5050:5000 \
  -v statix_data:/app/data \
  -e DATABASE_PATH=/app/data/metrics.db \
  -e STATIX_API_KEY=your-secret-key \
  midnightappcoder/statix:1.0.1
```

---

## API Endpoints

| Method | Endpoint | Auth required | Description |
|---|---|---|---|
| `POST` | `/metrics` | No | Ingest a metrics payload from the forwarder. |
| `GET` | `/data` | No | Query stored metrics. Params: `hostname`, `timeframe` (`1h`, `24h`, `7d`). |
| `GET` | `/details` | No | Latest rich snapshot for a host. Param: `hostname`. |
| `GET` | `/hosts` | No | List all known hosts with last-seen timestamps. |
| `POST` | `/hosts/<hostname>/clean` | **Yes** | Delete metric history for a host (keeps host_details). |
| `DELETE` | `/hosts/<hostname>` | **Yes** | Remove a host and all its data entirely. |
| `GET` | `/dashboard` | No | Chart.js dashboard UI. |
| `GET` | `/health` | No | Health check — returns `{"status": "ok", "version": "<sha>", "expected_client_version": "<sha>", "latest_version": "<sha-or-null>"}`. `latest_version` is the current HEAD SHA on `main` from GitHub (cached 1 h, `null` when unreachable). The dashboard uses it to detect a stale server image. |

"Auth required" applies only when `STATIX_API_KEY` is set. Pass the token as:
```
Authorization: Bearer <your-key>
```

---

## Docker Hub & CI

The image is automatically built and pushed to Docker Hub on every push to `main` that touches `server/**`, via `.github/workflows/docker-publish.yml`. Images are built for both `linux/amd64` and `linux/arm64`.

Each build bakes the git commit SHA into the image as environment variables via a `GIT_SHA` build arg:
- `STATIX_SERVER_VERSION` — the SHA of the server build
- `STATIX_EXPECTED_CLIENT_VERSION` — the SHA the dashboard expects the client to be on (same commit, same repo)

The dashboard reads these at startup via `/health` and shows a yellow warning banner if:
- A connected client is on a different SHA than the server (`expected_client_version` check).
- The running server image is behind the latest commit on `main` (`latest_version` vs `version` check — the server polls the GitHub API once per hour and caches the result in memory).

To build locally and pass the SHA:
```sh
cd server
docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t statix-local .
```
Omitting `--build-arg` leaves both env vars as `"dev"`, so a local build paired with a locally-installed client (also showing `"dev"`) will not trigger a mismatch warning.

Tags:
- `midnightappcoder/statix:latest` — most recent `main` build
- `midnightappcoder/statix:<git-sha>` — immutable per-commit tag

### One-time Docker Hub secrets setup (repo owner)

1. **GitHub → repo → Settings → Secrets and variables → Actions**
2. Add `DOCKERHUB_USERNAME` = `midnightappcoder`
3. Add `DOCKERHUB_TOKEN` = Docker Hub access token (hub.docker.com → Account Settings → Security → New Access Token)

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

# Backup the database
docker cp statix:/app/data/metrics.db ./metrics-backup.db
```
