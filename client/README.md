# System Stats Service

FastAPI-based daemon that exposes host system metrics (CPU, memory, disk, network I/O, uptime) via a REST API. Designed to run directly on macOS or Linux/Raspberry Pi hosts so that metrics reflect the underlying machine rather than a container sandbox.

## Features & Internals
- Collects metrics with `psutil`, including CPU load, logical/physical cores, frequency bounds, memory and swap usage, primary disk utilisation, and network interface stats.
- Captures uptime, boot time, and hardware metadata (`platform.uname`, optional model lookup via `sysctl`/DMI).
- Serves a FastAPI application with `/system` (rich JSON snapshot) and `/health` endpoints.
- Ships a forwarder (`system-stats-forwarder`) that polls `/system`, flattens the key utilisation percentages, attaches the full snapshot, and POSTs to the monitoring server’s `/metrics` endpoint.
- Configurable via environment variables (host, port, log level, poll interval, target server URLs).

## Installation
```sh
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
```
This installs both `system-stats-service` and `system-stats-forwarder` entry points.

## Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `SYSTEM_STATS_HOST` | `0.0.0.0` | Bind address for the FastAPI service. |
| `SYSTEM_STATS_PORT` | `5001` | Port for the FastAPI service. |
| `SYSTEM_STATS_LOG_LEVEL` | `info` | Logging level for the FastAPI service. |
| `SYSTEM_STATS_URL` | `http://127.0.0.1:5001/system` | Forwarder source endpoint. |
| `MONITORING_SERVER_METRICS_URL` | `http://127.0.0.1:5050/metrics` | Forwarder destination (Flask server). |
| `SYSTEM_STATS_FORWARD_INTERVAL` | `30` | Seconds between polls. |
| `SYSTEM_STATS_FORWARD_LOG_LEVEL` | `info` | Forwarder log level. |
| `SYSTEM_STATS_DISK_PATH` | `/` | Root path for disk usage metrics (override for alternative mounts). |

## Running the Service
Start the API in the foreground:
```sh
system-stats-service
```
Typical daemon launch (macOS/Linux):
```sh
SYSTEM_STATS_PORT=5001 SYSTEM_STATS_LOG_LEVEL=info \
  system-stats-service >> /var/log/system-stats-service.log 2>&1 &
```
Verify health:
```sh
curl http://127.0.0.1:5001/health
```

## Running the Forwarder
```sh
SYSTEM_STATS_URL=http://127.0.0.1:5001/system \
MONITORING_SERVER_METRICS_URL=http://127.0.0.1:5050/metrics \
SYSTEM_STATS_FORWARD_INTERVAL=30 \
system-stats-forwarder
```
The forwarder logs utilisation percentages and retries on transient failures.

### Keeping the Forwarder Running

#### Quick one-off (nohup)
```sh
nohup system-stats-forwarder \
  > ~/Library/Logs/system-stats-forwarder.log 2>&1 &
```
Set the required environment variables before running (as shown above). Stop with `pkill -f system-stats-forwarder`.

#### macOS (launchd)
1. Create a LaunchAgents plist, e.g. `~/Library/LaunchAgents/com.local.systemstats.forwarder.plist`:
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
     <dict>
       <key>Label</key>
       <string>com.local.systemstats.forwarder</string>
       <key>ProgramArguments</key>
       <array>
         <string>/Users/USERNAME/Library/Python/3.9/bin/system-stats-forwarder</string>
       </array>
   <key>EnvironmentVariables</key>
   <dict>
     <key>MONITORING_SERVER_METRICS_URL</key>
      <string>http://192.168.0.139:5050/metrics</string>
     <key>SYSTEM_STATS_URL</key>
      <string>http://127.0.0.1:5001/system</string>
      <key>SYSTEM_STATS_FORWARD_INTERVAL</key>
      <string>30</string>
      <key>SYSTEM_STATS_FORWARD_LOG_LEVEL</key>
         <string>info</string>
       </dict>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
       <key>StandardOutPath</key>
       <string>/Users/USERNAME/Library/Logs/system-stats-forwarder.log</string>
       <key>StandardErrorPath</key>
       <string>/Users/USERNAME/Library/Logs/system-stats-forwarder.log</string>
     </dict>
   </plist>
   ```
2. Load and start:
   ```sh
   launchctl load ~/Library/LaunchAgents/com.local.systemstats.forwarder.plist
   launchctl start com.local.systemstats.forwarder
   ```
3. Manage with `launchctl list | grep systemstats`, `launchctl unload …`, and review logs in `~/Library/Logs/`.

## REST API
- `GET /system` – Returns the full snapshot (`cpu`, `memory`, `disk`, `network`, `system`, `uptime`, timestamps). Example:
```json
{
  "collected_at": "2025-09-23T16:18:12.743209+00:00",
  "cpu": {"percent": 12.2, "logical_cores": 12, "physical_cores": 12, ...},
  "memory": {"percent": 67.7, "total": 25769803776, ...},
  "disk": {"percent": 14.1, "mount": "/", ...},
  "network": {"primary_interface": {"name": "en1", "ipv4": "192.168.0.82", ...}},
  "uptime": {"human": "10h 17m", "boot_time": "2025-09-23T11:30:33+05:30"},
  "system": {"hostname": "chandan-mac-mini.local", "model": "Mac16,11", ...}
}
```
- `GET /health` – `{ "status": "ok" }`.

## Background Services
Templates under `service/` help run the agent and forwarder:
- `service/systemd/system-stats.service` – systemd unit. Duplicate/modify for separate forwarder unit if desired.
- `service/launchd/com.local.systemstats.plist` – launchd plist for macOS (user-level).

### Example systemd Forwarder Unit
```ini
[Unit]
Description=System Stats Forwarder
After=network-online.target

[Service]
Type=simple
User=YOUR_USER
Environment=SYSTEM_STATS_URL=http://127.0.0.1:5001/system
Environment=MONITORING_SERVER_METRICS_URL=http://192.168.0.10:5050/metrics
ExecStart=/usr/local/bin/system-stats-forwarder
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

## Development
- The package targets Python 3.9+.
- Linting/test hooks are not provided; use `ruff`, `black`, or similar as needed.
- When developing locally, hot reload is available via `uvicorn --reload` (install `uvicorn[standard]`).

## Troubleshooting
- Ensure `/system` is reachable; the forwarder logs failures to stderr/stdout.
- LibreSSL warnings on macOS stem from the system Python; install Python via Homebrew (OpenSSL) to silence them.
- If disk metrics should track a different mount (e.g. `/data`), set `SYSTEM_STATS_DISK_PATH` accordingly.

## Raspberry Pi Installation Notes

```sh
sudo apt update
sudo apt install python3-pip
```

```sh python3 -m pip --version ``` should be 23.x or newer

On modern Raspberry Pi OS releases (`/usr/bin/python3` is “externally managed”), use:

```sh
python3 -m pip install --break-system-packages .
```



If `pip` complains about stale egg-info permissions, remove the folder first:

```sh
sudo rm -rf system_stats_service.egg-info
python3 -m pip install --break-system-packages .
```

You can also wrap the services with systemd using a single command:

```sh

sudo bash -c '
cat >/etc/systemd/system/system-stats.service <<EOF
[Unit]
Description=System Stats API Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ankush
Environment=SYSTEM_STATS_PORT=5001
Environment=SYSTEM_STATS_LOG_LEVEL=info
Environment=PATH=/home/ankush/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/bin/env system-stats-service
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/system-stats-forwarder.service <<EOF
[Unit]
Description=System Stats Forwarder
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ankush
Environment=PATH=/home/ankush/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=MONITORING_SERVER_METRICS_URL=http://piserver.local:5050/metrics
Environment=SYSTEM_STATS_URL=http://127.0.0.1:5001/system
Environment=SYSTEM_STATS_FORWARD_INTERVAL=30
Environment=SYSTEM_STATS_FORWARD_LOG_LEVEL=info
ExecStart=/usr/bin/env system-stats-forwarder
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart system-stats.service
systemctl restart system-stats-forwarder.service
'
```

check using

```sh
systemctl status system-stats.service
systemctl status system-stats-forwarder.service
curl http://127.0.0.1:5001/health
```

Adjust `User`, paths, or URLs as needed (`pi` vs. your username, monitoring server IP, etc.).
