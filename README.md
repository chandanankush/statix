# Monitoring Stack

This project combines a host-native system stats agent with a lightweight monitoring server and dashboard. The agent gathers CPU, memory, disk, network, and uptime information directly from each machine; the server persists readings, serves APIs, and renders a responsive dashboard with trend charts and host summary cards.

<img width="5120" height="4448" alt="screencapture-piserver-local-5050-dashboard-2025-09-23-23_58_44" src="https://github.com/user-attachments/assets/5a75b62e-ff05-4f0d-b133-2167372034b7" />



## Quick Usage
1. **Start the monitoring server** (via Docker Compose):
   ```sh
   docker-compose up --build -d
   ```
   Visit `http://localhost:5050/dashboard` (use `MONITOR_PORT` to override).

2. **Install the system stats agent** on each host:
   ```sh
   pip install ./client
   system-stats-service &
   system-stats-forwarder &
   ```
   Configure environment variables as needed (see component READMEs).

3. **View metrics** on the dashboard and filter by hostname/timeframe to inspect live charts and hardware details.

## Components
- **client/** – FastAPI service and forwarder that collect host metrics (detailed docs in `client/README.md`).
- **server/** – Flask ingestion API, SQLite storage, and Chart.js dashboard (detailed docs in `server/README.md`).
- **ARCHITECTURE.md** – High-level design and data flow.
- **docker-compose.yml** – Container orchestration for the monitoring server.

## Getting Help
- `client/README.md` explains installation, configuration, and service templates for the agent/forwarder.
- `server/README.md` covers server configuration, Docker usage, and API endpoints.
- `ARCHITECTURE.md` provides an overview for new contributors.
