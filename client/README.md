# System Stats Client

FastAPI-based daemon that exposes host system metrics (CPU, memory, disk, network I/O, uptime) via a REST API, paired with a forwarder that ships those metrics to the monitoring server. Designed to run natively on macOS and Raspberry Pi / Linux so metrics reflect the actual host hardware.

## One-Line Install

Supports **macOS** and **Raspberry Pi OS** (and any Debian-based Linux).

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```

The installer will prompt for:
- **Monitoring server URL** — defaults to `http://192.168.0.209:5050`
- **Forwarding interval** — defaults to `30` seconds

Pass flags to skip prompts:
```sh
curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh \
  | bash -s -- --server-url http://192.168.0.209:5050 --interval 30
```

### What the installer does
1. Detects your platform (macOS → launchd, Linux → systemd).
2. Checks for Python 3.9+ and installs it via `apt` on Raspberry Pi if missing.
3. Creates an isolated venv at `~/.local/share/statix/venv` — no system Python is touched.
4. Installs the package directly from this GitHub repo.
5. Registers and starts two persistent background services:
   - **system-stats-service** — the FastAPI daemon on `127.0.0.1:5001`
   - **system-stats-forwarder** — polls `/system` every N seconds and POSTs to the monitoring server
6. Both services start automatically at login/boot and restart on crash.

Re-running the same command **upgrades** to the latest version and restarts services, keeping your existing config.

### Uninstall
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/uninstall.sh)
```
Stops and removes both services, deletes the venv, and cleans up any legacy pip packages.

---

## Service Management

### macOS (launchd)
```sh
# Check status
launchctl list | grep systemstats

# View logs
tail -f ~/Library/Logs/system-stats-service.log
tail -f ~/Library/Logs/system-stats-forwarder.log

# Restart manually
launchctl unload ~/Library/LaunchAgents/com.local.systemstats.service.plist
launchctl load   ~/Library/LaunchAgents/com.local.systemstats.service.plist
```

### Raspberry Pi / Linux (systemd)
```sh
# Check status
systemctl --user status system-stats-service
systemctl --user status system-stats-forwarder

# Follow logs
journalctl --user -u system-stats-service -f
journalctl --user -u system-stats-forwarder -f

# Restart manually
systemctl --user restart system-stats-service
systemctl --user restart system-stats-forwarder
```

---

## Configuration

All settings are environment variables. The installer writes them into the service files automatically. To change them after install, edit the launchd plist or systemd unit and reload the service.

| Variable | Default | Description |
|---|---|---|
| `SYSTEM_STATS_HOST` | `0.0.0.0` | Bind address for the FastAPI service. |
| `SYSTEM_STATS_PORT` | `5001` | Port for the FastAPI service. |
| `SYSTEM_STATS_LOG_LEVEL` | `info` | Log level for the FastAPI service. |
| `SYSTEM_STATS_URL` | `http://127.0.0.1:5001/system` | Forwarder source endpoint. |
| `MONITORING_SERVER_METRICS_URL` | `http://192.168.0.209:5050/metrics` | Forwarder destination(s). Accepts a single URL or a comma-separated list (e.g. `http://192.168.0.209:5050/metrics,http://127.0.0.1:5050/metrics`). Each destination is tried independently; one unreachable server does not block the others. |
| `SYSTEM_STATS_FORWARD_INTERVAL` | `30` | Seconds between polls. |
| `SYSTEM_STATS_FORWARD_LOG_LEVEL` | `INFO` | Log level for the forwarder. |
| `SYSTEM_STATS_DISK_PATH` | `/` | Root path for disk usage (override for non-root mounts). |

---

## REST API

### `GET /system`
Returns a full snapshot of the host. Example response:
```json
{
  "collected_at": "2026-05-01T11:23:44.238212+00:00",
  "cpu": {
    "percent": 8.7,
    "logical_cores": 12,
    "physical_cores": 12,
    "frequency_mhz": 3200,
    "processor": "arm"
  },
  "memory": { "percent": 59.5, "total": 25769803776, "available": 10435428352 },
  "swap":   { "percent": 0.0, "total": 0 },
  "disk":   { "percent": 20.7, "mount": "/", "total": 494384795648 },
  "disk_io": { "read_bytes": 176723312640, "write_bytes": 80530432000 },
  "network": {
    "primary_interface": { "name": "en0", "ipv4": "192.168.0.82", "speed_mbps": 1000 }
  },
  "uptime": { "seconds": 37422, "human": "10h 23m", "boot_time": "2026-05-01T00:59:22+05:30" },
  "system": { "hostname": "chandan-mac-mini.local", "os": "Darwin", "model": "Mac16,11" },
  "docker": {
    "available": true,
    "running": 2,
    "total": 3,
    "containers": [
      {"id": "abc123def456", "name": "statix-statix-1", "image": "midnightappcoder/statix:latest", "state": "running", "status": "Up 4 minutes", "ports": "0.0.0.0:5050->5000/tcp"},
      {"id": "789ghi012jkl", "name": "statix-db-1", "image": "postgres:15", "state": "running", "status": "Up 4 minutes", "ports": ""},
      {"id": "mno345pqr678", "name": "old-container", "image": "nginx:latest", "state": "exited", "status": "Exited (0) 2 days ago", "ports": ""}
    ]
  }
}
```

### `GET /health`
```json
{ "status": "ok" }
```

---

## Payload Sent to the Monitoring Server

The forwarder POSTs the following to `/metrics` on the monitoring server every interval:
```json
{
  "hostname": "chandan-mac-mini.local",
  "cpu": 8.7,
  "ram": 59.5,
  "disk": 20.7,
  "timestamp": 1746092624,
  "disk_read": 0.12,
  "disk_write": 0.05,
  "details": { }
}
```
`disk_read` / `disk_write` are MB/s computed between consecutive polls (0.0 on the first poll). `details` contains the full `/system` snapshot used by the dashboard's host cards.

---

## Manual / Developer Install

If you prefer to manage the environment yourself:
```sh
cd client
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install .
```
Then start each process in your own process manager:
```sh
system-stats-service    # FastAPI on :5001
system-stats-forwarder  # polls :5001 → monitoring server
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `externally-managed-environment` error | Use the installer script — it creates its own venv automatically. |
| `Permission denied` creating `~/.local` | Your home directory is probably owned by root from a previous `sudo` run. Check: `ls -la /home/ \| grep $(whoami)`. If it's owned by root, fix: `sudo chown $(whoami):$(whoami) $HOME` then re-run the installer. |
| `bash: /dev/fd/63: No such file or directory` when using `sudo bash <(curl ...)` | Do not use `sudo`. The installer runs as your normal user. Use the pipe form instead: `curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh \| bash` |
| Service not starting on Raspberry Pi after reboot | Run `sudo loginctl enable-linger $(whoami)` so systemd user services survive without an active login session. |
| Disk metrics show wrong mount | Set `SYSTEM_STATS_DISK_PATH` to the mount you want to track. |
| Forwarder can't reach the monitoring server | Check the server URL and that port `5050` is reachable from this host. |
| LibreSSL warnings on macOS | Install Python via Homebrew (`brew install python`) instead of the system Python. |
