# Dashboard capabilities

- **Live charts** — CPU %, RAM %, Disk I/O, Network I/O with configurable timeframes
- **Host detail cards** — CPU info & temperature, memory, storage, system info, network, uptime, Docker
- **OS update check** — shows pending updates on macOS (`softwareupdate`) and Debian/RPi (`apt`), cached 24 h
- **Docker image update check** — per-container update badge, cached 24 h
- **All active network interfaces** — shows active IPv4 interfaces with IP, speed, and link type; loopback and selected virtual interfaces are excluded
- **CPU temperature** — psutil + sysfs fallback on Linux/Raspberry Pi; `osx-cpu-temp` on macOS Intel; hidden on Apple Silicon
- **Version mismatch warnings** — dashboard shows a yellow banner if the server or any client is running a different git SHA than expected; updated automatically on every deploy
- **User-configurable alert thresholds** — per-card color (Amber/Red/Blue/Green/Purple/custom hex), percentage input, on/off; persisted in `localStorage`
- **Drag-to-reorder & hide** cards and charts; order persisted in `localStorage`
- **Multi-host** — auto-cycles hosts or pin to a specific machine
- **Dark/light theme** toggle
- **Multi-arch Docker image** — `linux/amd64` + `linux/arm64` (Raspberry Pi)
