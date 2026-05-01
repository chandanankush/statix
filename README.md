# Monitoring Stack

[![Docker Hub](https://img.shields.io/docker/v/midnightappcoder/statix?label=Docker%20Hub&logo=docker)](https://hub.docker.com/r/midnightappcoder/statix)
[![CI](https://github.com/chandanankush/statix/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/chandanankush/statix/actions/workflows/docker-publish.yml)

A self-hosted system monitoring stack. The agent (FastAPI + psutil) runs natively on each host (macOS, Raspberry Pi). The server (Flask + SQLite) runs in Docker and is published to Docker Hub as `midnightappcoder/statix`.

![stats](https://github.com/user-attachments/assets/2e0ffe7d-c37e-4acd-9ea9-997891104216)

## Features
- **Live charts** — CPU %, RAM %, Disk I/O, Network I/O with configurable timeframes
- **Host detail cards** — CPU info & temperature, memory, storage, system info, network, uptime, Docker
- **OS update check** — shows pending updates on macOS (`softwareupdate`) and Debian/RPi (`apt`), cached 24 h
- **Docker image update check** — per-container update badge, cached 24 h
- **All active network interfaces** — shows every up, non-loopback interface with IP, speed, and link type
- **CPU temperature** — psutil + sysfs fallback on Linux/Raspberry Pi; `osx-cpu-temp` on macOS Intel; hidden on Apple Silicon
- **Version mismatch warnings** — dashboard shows a yellow banner if the server or any client is running a different git SHA than expected; updated automatically on every deploy
- **User-configurable alert thresholds** — per-card color (Amber/Red/Blue/Green/Purple/custom hex), percentage input, on/off; persisted in `localStorage`
- **Drag-to-reorder & hide** cards and charts; order persisted in `localStorage`
- **Multi-host** — auto-cycles hosts or pin to a specific machine
- **Dark/light theme** toggle
- **Multi-arch Docker image** — `linux/amd64` + `linux/arm64` (Raspberry Pi)

## Quick Usage

### 1. Start the monitoring server
Requires Docker. Pulls the pre-built image from Docker Hub:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
```
Or manually with Docker:
```sh
docker run -d \
  --name statix \
  --restart unless-stopped \
  -p 5050:5000 \
  -v statix_data:/app/data \
  midnightappcoder/statix:latest
```
Or with Docker Compose:
```sh
docker compose up -d
```
Visit `http://localhost:5050/dashboard`.

### 2. Install the agent on each host (macOS or Raspberry Pi)
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
```
Pass flags to skip interactive prompts:
```sh
curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh \
  | bash -s -- --server-url http://YOUR_SERVER:5050 --interval 30
```
Re-running the same command upgrades the package and restarts services without losing your config.

To uninstall:
```sh
bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/uninstall.sh)
```

### 3. View metrics
Open `http://YOUR_SERVER:5050/dashboard` and filter by hostname and timeframe.

#### Optional: CPU temperature on macOS Intel
```sh
brew install osx-cpu-temp
```
Temperature is shown automatically once the tool is on PATH. Not available on Apple Silicon.

## Components
- **client/** — FastAPI stats service, forwarder, and one-line installer/uninstaller. See `client/README.md`.
- **server/** — Flask ingestion API, SQLite storage, and Chart.js dashboard. Published as `midnightappcoder/statix` on Docker Hub. See `server/README.md`.
- **ARCHITECTURE.md** — High-level design and data flow.
- **docker-compose.yml** — Container orchestration for the monitoring server.

## Getting Help
- `client/README.md` — installation, configuration, service management, and API reference for the agent.
- `server/README.md` — server configuration, Docker usage, API endpoints, and Docker Hub CI setup.
- `ARCHITECTURE.md` — high-level design and data flow.
- `CONTRIBUTING.md` — how to set up a dev environment and make changes.
- `AGENTS.md` — rules and conventions for AI coding agents working in this repo.
