# Dashboard capabilities

- **History charts** — CPU %, per-core CPU % (one line per core), CPU temperature, load average, memory + swap, disk I/O and network I/O over 15 min to 30 days. Long ranges are downsampled on the server (about 600 points per chart) and the dashed lines show each bucket's peak, so short spikes are not averaged away.
- **Stable axes** — a real time axis pinned to the selected window (outages show as gaps); CPU, memory and temperature use fixed scales, and Disk, Network and Load keep a high-water-mark ceiling that grows but never shrinks.
- **Host detail cards** — CPU info & temperature, memory, storage, system info, network, uptime, Docker
- **Docker table** — one row per container: state and uptime/health, CPU %, memory, cumulative network in/out, published ports, image-update badge, plus fleet totals. Memory is Docker's own figure where the host provides it; on kernels with the memory cgroup disabled (the Raspberry Pi OS default) it is an estimate from process RSS (shown with `~`) or `n/a`.
- **OS update check** — shows pending updates on macOS (`softwareupdate`) and Debian/RPi (`apt`), cached 24 h
- **Docker image update check** — per-container update badge, cached 24 h
- **All active network interfaces** — shows active IPv4 interfaces with IP, speed, and link type; loopback and selected virtual interfaces are excluded
- **CPU temperature** — psutil + sysfs fallback on Linux/Raspberry Pi; `osx-cpu-temp` on macOS Intel; unavailable on Apple Silicon (the temperature chart is hidden for hosts without a sensor). History starts from the first sample a server stores; earlier data is not backfilled.
- **Version mismatch warnings** — dashboard shows a yellow banner if the server or any client is running a different git SHA than expected; updated automatically on every deploy
- **User-configurable alert thresholds** — per-card color (Amber/Red/Blue/Green/Purple/custom hex), percentage input, on/off; persisted in `localStorage`
- **Drag-to-reorder & hide** cards and charts; order persisted in `localStorage`
- **Multi-host** — auto-cycles hosts or pin to a specific machine
- **Dark/light theme** toggle
- **Multi-arch Docker image** — `linux/amd64` + `linux/arm64` (Raspberry Pi)

The dashboard loads Chart.js and its date adapter from the jsDelivr CDN, so the *browser* needs internet access (the server does not).
