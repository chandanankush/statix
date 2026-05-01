# Deployment Guide

Operational knowledge for deploying and upgrading statix — including lessons learned from real deployments on macOS and Raspberry Pi.

---

## Table of Contents

1. [First-Time Server Install](#1-first-time-server-install)
2. [First-Time Client Install](#2-first-time-client-install)
3. [Upgrading the Server](#3-upgrading-the-server)
4. [Upgrading the Client](#4-upgrading-the-client)
5. [Verifying Everything is Healthy](#5-verifying-everything-is-healthy)
6. [CI/CD and the Version Lifecycle](#6-cicd-and-the-version-lifecycle)
7. [Lessons Learned — Docker Gotchas](#7-lessons-learned--docker-gotchas)
8. [Lessons Learned — Client Installer Gotchas](#8-lessons-learned--client-installer-gotchas)
9. [Lessons Learned — Platform Differences](#9-lessons-learned--platform-differences)
10. [Troubleshooting Runbook](#10-troubleshooting-runbook)

---

## 1. First-Time Server Install

Requires Docker on the target machine. Run once on the host that will run the monitoring server (e.g. your Raspberry Pi server):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```

The installer will prompt for:
- **Dashboard port** — defaults to `5050`
- **Data directory** — skip this on first run; it defaults to `~/.local/share/statix/data`

**What the installer does:**
1. Pulls `midnightappcoder/statix:latest` from Docker Hub.
2. Stops and removes any existing `statix` container.
3. Creates the data directory (host path or Docker named volume).
4. Starts the container with `--restart unless-stopped` so it survives reboots.
5. Waits for `/health` to respond before returning.

After install, confirm it is running:
```sh
curl http://127.0.0.1:5050/health
# → {"status":"ok","version":"<sha>","expected_client_version":"<sha>","latest_version":"<sha>"}
```

---

## 2. First-Time Client Install

Run on **each host** you want to monitor (macOS or Raspberry Pi):

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```

Prompts:
- **Monitoring server URL** — e.g. `http://192.168.0.209:5050`
- **Forwarding interval** — defaults to `30` seconds

**What the installer does:**
1. Detects platform: macOS → launchd, Linux → systemd.
2. Creates an isolated venv at `~/.local/share/statix/venv` — no system Python is touched.
3. Installs the package from GitHub with all dependencies (`fastapi`, `uvicorn`, `psutil`).
4. Records the installed git SHA to `~/.local/share/statix/client_version`.
5. Writes and loads two persistent services:
   - `system-stats-service` — FastAPI daemon on `127.0.0.1:5001`
   - `system-stats-forwarder` — polls `/system` every N seconds → POSTs to the server

**On Raspberry Pi only:** `sudo loginctl enable-linger $(whoami)` must be run once after the first install so systemd user services survive without an active login session.

---

## 3. Upgrading the Server

Always use the installer to upgrade — **never** use `docker restart` or `docker pull` alone. See [Lesson #1](#lesson-1-docker-restart-does-not-pick-up-a-new-image) for why.

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```

The installer:
1. Reads the existing port and data volume from the running container automatically (no re-prompting).
2. Pulls the new image.
3. Stops and **removes** the old container.
4. Recreates it from the new image, mounting the same volume — data is preserved.

**If GitHub CDN is serving a stale script** (rare, but happens right after a push), use the commit SHA URL to bypass the cache:

```sh
bash <(curl -fsSL "https://raw.githubusercontent.com/chandanankush/statix/<sha>/server/install.sh")
```

---

## 4. Upgrading the Client

Re-run the installer on each host:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```

The installer detects the existing install and does an in-place upgrade:
- **Healthy venv** → `pip install --force-reinstall --no-deps` (fast, deps already present).
- **Broken venv** (missing `fastapi`/`uvicorn`/`psutil`) → wipes the venv and does a full reinstall automatically. See [Lesson #2](#lesson-2-pip---no-deps-on-a-fresh-venv-leaves-it-broken).

Your server URL and interval are read from the existing service files so you are never re-prompted.

---

## 5. Verifying Everything is Healthy

### Server
```sh
curl http://192.168.0.209:5050/health
```
Expected: `"status":"ok"` and `"version"` matches `"latest_version"`.

```sh
docker logs -f statix
```

### Client (macOS)
```sh
launchctl list | grep systemstats
tail -50 ~/Library/Logs/system-stats-service.log
tail -50 ~/Library/Logs/system-stats-forwarder.log
curl http://127.0.0.1:5001/health
```

### Client (Raspberry Pi / Linux)
```sh
systemctl --user status system-stats-service
systemctl --user status system-stats-forwarder
journalctl --user -u system-stats-service -n 50
journalctl --user -u system-stats-forwarder -n 50
curl http://127.0.0.1:5001/health
```

### Dashboard version panel
Open `http://192.168.0.209:5050/dashboard`. The version status panel shows:
- ✓ green — server and all clients are on the latest commit
- ⚠ yellow — something is outdated; follow the on-screen command
- ℹ grey — GitHub was unreachable (no internet) or running from source

---

## 6. CI/CD and the Version Lifecycle

Every `git push` to `main` triggers the GitHub Actions workflow (`.github/workflows/docker-publish.yml`):

```
git push to main
     │
     ▼
GitHub Actions
     │  extracts short SHA (first 7 chars of GITHUB_SHA)
     │  builds linux/amd64 + linux/arm64 image
     │  passes --build-arg GIT_SHA=<sha>
     ▼
Docker Hub  →  midnightappcoder/statix:latest
               midnightappcoder/statix:<sha>

     SHA baked into image as:
       STATIX_SERVER_VERSION=<sha>
       STATIX_EXPECTED_CLIENT_VERSION=<sha>
```

The server polls the GitHub API once per hour to discover the latest SHA on `main` (`latest_version` in `/health`). When `version != latest_version` the dashboard shows the server-outdated warning.

**Why CI triggers on every push (not just `server/**`):**  
Client-only changes (e.g. installer fixes) still advance `HEAD` on `main`. If the CI only rebuilt on `server/**` changes, the baked-in SHA would lag behind `HEAD` and the server would always appear outdated even after being updated. Building on every push keeps `STATIX_SERVER_VERSION` == `HEAD` at all times.

---

## 7. Lessons Learned — Docker Gotchas

### Lesson #1: `docker restart` does not pick up a new image

`docker restart` restarts the **existing container's process** — it never swaps the image. The container was created from a specific image layer and stays on it until the container is **deleted and recreated**.

| Command | Effect |
|---|---|
| `docker restart statix` | Restarts the process, same image — SHA unchanged |
| `docker pull … && docker restart statix` | Downloads the new image, but the container still uses the old one |
| `docker stop statix && docker rm statix && docker run …` | Correct — recreates from the new image |
| `bash <(curl … server/install.sh)` | Does the above automatically |

**Rule:** Always use `server/install.sh` to upgrade — never use `docker restart` for deployments.

---

### Lesson #2: Named Docker volumes live in `/var/lib/docker` — don't `mkdir` them

When a container is created with `-v statix_data:/app/data`, Docker creates a named volume managed internally at `/var/lib/docker/volumes/statix_data/_data`. This path is **root-owned**.

On upgrade, `docker inspect` returns the raw host path (`/var/lib/docker/volumes/statix_data/_data`). If the installer tried to `mkdir -p` that path as a regular user it would fail with `Permission denied`.

**Fix applied:** On upgrade, the installer skips `mkdir` entirely — the volume already exists and Docker manages it. `mkdir` only runs on fresh installs where the user has provided (or accepted) a plain host path like `~/.local/share/statix/data`.

---

### Lesson #3: GitHub's CDN caches raw file URLs for a few minutes

`raw.githubusercontent.com` CDN can serve a stale file for a few minutes after a push. If a fix is pushed but running the installer again immediately still shows the old behaviour, bypass the cache with:

```sh
# Cache-busting query string (ignored by curl, breaks CDN cache key)
bash <(curl -fsSL "https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh?$(date +%s)")

# Or fetch via the exact commit SHA (guaranteed fresh)
bash <(curl -fsSL "https://raw.githubusercontent.com/chandanankush/statix/<sha>/server/install.sh")
```

---

## 8. Lessons Learned — Client Installer Gotchas

### Lesson #4: `pip install --no-deps` on a fresh venv leaves it broken

During an upgrade, the installer uses `--force-reinstall --no-deps` (fast — only reinstalls our package, not the already-installed deps). But if the venv had never had deps installed (e.g. a previous run failed mid-way), `--no-deps` would leave `fastapi`, `uvicorn`, and `psutil` absent, causing the services to crash with `ModuleNotFoundError`.

**Fix applied:** Before deciding whether to upgrade or fresh-install, the installer probes the venv:

```bash
if "$VENV_DIR/bin/python" -c "import fastapi, uvicorn, psutil" 2>/dev/null; then
    IS_UPGRADE=true   # healthy — use --no-deps fast path
else
    rm -rf "$VENV_DIR"
    IS_UPGRADE=false  # broken — full reinstall with all deps
fi
```

This makes the installer self-healing. Re-running it on a broken host fixes it automatically.

---

### Lesson #5: `lsof` is not available on Raspberry Pi OS

The client installer has a `_free_port()` helper that kills whatever is using port 5001 before starting the service. macOS has `lsof`; Raspberry Pi OS Lite does not — it has `fuser` instead.

**Fix applied:** The helper tries `fuser` first (Linux default), then falls back to `lsof` (macOS):

```bash
_free_port() {
    local port="$1"
    if command -v fuser &>/dev/null; then
        fuser -k "${port}/tcp" &>/dev/null || true
    elif command -v lsof &>/dev/null; then
        lsof -ti :"$port" | xargs kill -9 &>/dev/null || true
    fi
}
```

---

### Lesson #6: Bash 3.2 compatibility (macOS ships bash 3.2)

All installer scripts must be bash 3.2 compatible. Bash 4+ features that are **forbidden**:
- `${var,,}` or `${var^^}` — use `tr '[:upper:]' '[:lower:]'` instead
- `declare -A` (associative arrays)
- `mapfile` / `readarray`

Always test scripts with `bash -n script.sh` and ideally run on macOS where the system bash is 3.2.

---

## 9. Lessons Learned — Platform Differences

| Feature | macOS | Raspberry Pi / Linux |
|---|---|---|
| Service manager | launchd (`launchctl`) | systemd user (`systemctl --user`) |
| Log location | `~/Library/Logs/*.log` | `journalctl --user -u <service>` |
| Port detection | `lsof -ti :5001` | `fuser -k 5001/tcp` |
| CPU temperature | `osx-cpu-temp` (Intel only); null on Apple Silicon | `psutil.sensors_temperatures()` → `/sys/class/thermal/thermal_zone0/temp` fallback |
| OS update check | `softwareupdate --list` | `apt list --upgradable` via `/usr/bin/apt` |
| Processor name | `sysctl hw.model` | `/proc/cpuinfo` → `model name:` (x86) or `Hardware:` (ARM) |
| Python venv module | Always present | May need `sudo apt install python3-venv` |
| Systemd linger | N/A | `sudo loginctl enable-linger $(whoami)` required for services to survive without a login session |

---

## 10. Troubleshooting Runbook

### Server shows ⚠ Server image is outdated

```sh
# On the Pi/server host:
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```

Do **not** use `docker restart` or `docker pull` alone — see [Lesson #1](#lesson-1-docker-restart-does-not-pick-up-a-new-image).

---

### Client shows ⚠ outdated or version shows `dev`

```sh
# On the affected host:
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```

---

### Services crash: `ModuleNotFoundError: No module named 'fastapi'`

The venv is broken. Re-run the installer — it detects missing deps, wipes the venv, and reinstalls everything:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```

---

### `mkdir: cannot create directory '/var/lib/docker': Permission denied` during server upgrade

Old installer bug — fixed. Pull the latest and re-run:

```sh
bash <(curl -fsSL "https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh?$(date +%s)")
```

---

### Installer runs but still shows old behaviour (GitHub CDN stale)

Use the commit SHA URL:

```sh
bash <(curl -fsSL "https://raw.githubusercontent.com/chandanankush/statix/<latest-sha>/server/install.sh")
```

Find the latest SHA at: `https://github.com/chandanankush/statix/commits/main`

---

### Raspberry Pi services don't start after reboot

Enable systemd linger so user services survive without an active session:

```sh
sudo loginctl enable-linger $(whoami)
```

---

### Forwarder reports `Connection refused` to `127.0.0.1:5001`

`system-stats-service` (the FastAPI daemon) is not running. Check:

```sh
# Raspberry Pi
systemctl --user status system-stats-service
journalctl --user -u system-stats-service -n 50

# macOS
launchctl list | grep systemstats
tail -50 ~/Library/Logs/system-stats-service.log
```

If it is crash-looping due to `ModuleNotFoundError`, see the broken venv fix above.

---

### Dashboard shows correct version but browser still shows warning after upgrade

Hard-refresh to clear cached `/health` response: `Cmd+Shift+R` (macOS) / `Ctrl+Shift+R` (Linux).
