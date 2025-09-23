# System Stats Service

FastAPI-based daemon that exposes host system metrics (CPU, memory, disk, network I/O, uptime) via a REST API. Designed to run directly on macOS or Linux/Raspberry Pi hosts so that metrics reflect the underlying machine rather than a container sandbox.

## Installation
```sh
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
```
This installs the `system-stats-service` API and the `system-stats-forwarder` bridge utility.

## Usage
Run the service:
```sh
system-stats-service
```
The API listens on `http://0.0.0.0:5001` by default. Override host/port via environment variables:
```sh
export SYSTEM_STATS_HOST=127.0.0.1
export SYSTEM_STATS_PORT=8000
export SYSTEM_STATS_LOG_LEVEL=debug
system-stats-service
```

### API
- `GET /system` – Returns JSON payload with CPU, memory, swap, disk usage, network counters, uptime, and boot time.
- `GET /health` – Lightweight readiness check.

## Forwarding Metrics to the Monitoring Server
Run the forwarder alongside the service to push readings to the Flask monitoring server:
```sh
export SYSTEM_STATS_URL=http://127.0.0.1:5001/system
export MONITORING_SERVER_METRICS_URL=http://127.0.0.1:5050/metrics
export SYSTEM_STATS_FORWARD_INTERVAL=30
system-stats-forwarder
```
Environment variables:
- `SYSTEM_STATS_URL` – Source FastAPI endpoint (default `http://127.0.0.1:5001/system`).
- `MONITORING_SERVER_METRICS_URL` – Destination monitoring server endpoint (default `http://127.0.0.1:5050/metrics`).
- `SYSTEM_STATS_FORWARD_INTERVAL` – Seconds between polls (default `30`).
- `SYSTEM_STATS_FORWARD_LOG_LEVEL` – Logging level (`INFO` by default).

## Running as a Background Service
Templates are provided under `service/` for both systemd (Linux/Raspberry Pi) and launchd (macOS).

### Linux / systemd
1. Copy the template and adjust paths (notably `User`, `Environment`, and `ExecStart`):
   ```sh
   sudo cp service/systemd/system-stats.service /etc/systemd/system/system-stats.service
   sudoedit /etc/systemd/system/system-stats.service
   ```
2. Reload systemd and enable the service:
   ```sh
   sudo systemctl daemon-reload
   sudo systemctl enable system-stats.service
   sudo systemctl start system-stats.service
   ```
3. Check status/logs:
   ```sh
   systemctl status system-stats.service
   journalctl -u system-stats.service -f
   ```

### macOS / launchd
1. Copy the plist (update the binary path and log locations):
   ```sh
   mkdir -p ~/Library/LaunchAgents
   cp service/launchd/com.local.systemstats.plist ~/Library/LaunchAgents/
   nano ~/Library/LaunchAgents/com.local.systemstats.plist
   ```
2. Load and start:
   ```sh
   launchctl load ~/Library/LaunchAgents/com.local.systemstats.plist
   launchctl start com.local.systemstats
   ```
3. View logs:
   ```sh
   tail -f ~/Library/Logs/system-stats-service.log
   ```

## Development Notes
- Logging defaults to INFO level on stdout; adjust with `SYSTEM_STATS_LOG_LEVEL`.
- Because metrics rely on the host kernel, run the service directly on the target machine instead of inside Docker unless the container has full access to host namespaces.
