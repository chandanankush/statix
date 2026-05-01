# Monitoring Stack

This project combines a host-native system stats agent with a lightweight monitoring server and dashboard. The agent gathers CPU, memory, disk, network, and uptime information directly from each machine; the server persists readings, serves APIs, and renders a responsive dashboard with trend charts and host summary cards.

![stats](https://github.com/user-attachments/assets/2e0ffe7d-c37e-4acd-9ea9-997891104216)

## Quick Usage

### 1. Start the monitoring server
Requires Docker. Pulls the pre-built image from Docker Hub:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```
Or with Docker Compose (also pulls from Docker Hub by default):
```sh
docker-compose up -d
```
Visit `http://localhost:5050/dashboard` (override port with `--port` flag or `MONITOR_PORT` env var).

### 2. Install the agent on each host (macOS or Raspberry Pi)
A single command installs, configures, and starts both the stats service and the forwarder as persistent background daemons:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```
The script detects your platform, creates an isolated Python environment, registers services (launchd on macOS, systemd on Linux), and sets them to start automatically on boot/login.

Pass flags to skip the interactive prompts:
```sh
curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh \
  | bash -s -- --server-url http://192.168.0.209:5050 --interval 30
```

Re-running the same command upgrades the package and restarts services without losing your config.

To uninstall:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/uninstall.sh)
```

### 3. View metrics
Open `http://YOUR_SERVER:5050/dashboard` and filter by hostname and timeframe to inspect live charts and hardware details.

## Components
- **client/** – FastAPI stats service, forwarder, and one-line installer/uninstaller. See `client/README.md`.
- **server/** – Flask ingestion API, SQLite storage, and Chart.js dashboard. See `server/README.md`.
- **ARCHITECTURE.md** – High-level design and data flow.
- **docker-compose.yml** – Container orchestration for the monitoring server.

## Getting Help
- `client/README.md` — installation, configuration, and service management for the agent.
- `server/README.md` — server configuration, Docker usage, and API endpoints.
- `ARCHITECTURE.md` — overview for new contributors.
