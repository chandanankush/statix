# Statix Product Roadmap

Inspired by a feature gap analysis. Items are ordered by **delivery priority** — low-effort/high-value first, scaling up to larger architectural work. No implementation decisions are made here; this is a product-level list of _what_ to build, not _how_.

---

## Baseline — What Statix Has Today

Before listing gaps it is important to be precise about what is already working, so the roadmap does not duplicate shipped work.

| Area | Current capability |
|---|---|
| CPU | Aggregate CPU %, frequency, core count, CPU temperature (Linux + macOS Intel) |
| Memory | RAM used / total; swap collected by agent but **not stored as time-series** |
| Disk | Root-partition usage only; aggregate disk I/O (read + write bytes, single counter) |
| Network | All active interfaces — IP, speed, link type, and I/O bytes per interface |
| Containers | Docker container list, run state, image update-available badge |
| System info | Uptime, CPU model, OS version, pending OS/package updates |
| Alerting | Webhook POST when CPU % or RAM % crosses a global threshold; configurable cooldown |
| Auth | Optional single shared bearer token (`STATIX_API_KEY`); no user accounts |
| Dashboard | Chart.js; **dark/light theme already shipped**; drag-reorder + hide cards; 1 h / 24 h / 7 d views |
| Retention | `STATIX_RETENTION_DAYS` env var, **default 30 days already stored**; UI only queries up to 7 d |
| Multi-host | Cycle or pin to a specific host |
| Deployment | Docker (amd64 + arm64), one-liner Bash installer, Docker Compose |

Two items that appeared in an earlier priority suggestion are **not gaps**:
- **Dark mode** — already shipped.
- **Configurable retention > 7 days** — server already retains 30 days by default. The real gap is the dashboard UI selector (see P1-4 below).

---

## Phase 1 — Low Effort, High Value

> Quick wins that touch only one layer (agent or dashboard) and require no new dependencies or schema redesign. Each should ship independently in a single PR.

---

### ✅ P1-1 · Swap Memory as a Time-Series Chart — **Shipped**

**Gap:** `psutil.swap_memory()` is already called and included in the host-details snapshot, but the values are never written to the `metrics` table. Swap trending is therefore invisible — you can only see the current snapshot.

**Why it matters:** Swap pressure is the first sign of memory exhaustion on constrained hosts (Raspberry Pi, low-RAM VMs). Without historical data you cannot tell if a spike is chronic or one-off.

**What competition does:** Charts swap alongside RAM as a second line in the memory panel.

**What was built:**
- Forwarder: extracts `swap.percent` from the `/system` payload and forwards it as `swap_percent`.
- Server: `swap_percent` column added to the `metrics` table via `_ensure_column` (zero-downtime migration for existing databases). Stored on every ingest, returned in `/data` response.
- Dashboard: Memory chart renamed from "RAM Usage (%)" to "Memory (%)". Swap % rendered as a second cyan (`#06b6d4`) line alongside the existing blue RAM % line.
- Backward compatible: agents that do not yet send `swap_percent` default to `0.0` on the server side.

---

### ✅ P1-2 · System Load Average — **Shipped**

**Gap:** Load average (1-min, 5-min, 15-min) is a standard Unix health signal and is never collected or displayed.

**Why it matters:** Load average catches situations where CPU % looks fine but the system is actually saturated with I/O-bound processes queued. It is the canonical first metric checked during an incident.

**What competition does:** Collects and charts load average as a companion to CPU %.

**What was built:**
- Agent: `_get_load_average()` calls `os.getloadavg()` (POSIX-only; returns `None` gracefully on Windows via `AttributeError`). Added as `load_avg` field in the `/system` response.
- Forwarder: extracts `load1`, `load5`, `load15` from `load_avg` and includes them in the POST payload (`None` when unavailable).
- Server: three nullable columns (`load1`, `load5`, `load15 REAL`) added via `_ensure_column`. Stored as `NULL` for agents that don't support it; returned in `/data` response.
- Dashboard: new "Load Average" chart with three lines — 1m (amber), 5m (orange), 15m (slate) — on a free-scale y-axis. CPU info card gains a "Load Avg" stat row (1m / 5m / 15m) that hides automatically on Windows/unsupported hosts. Chart registered in `CHART_WIDGETS` for the drag/hide toggle panel.

---

### P1-3 · Per-Core CPU Breakdown ✅ Shipped

**Gap:** Only aggregate CPU % is shown. On multi-core hosts (Mac Mini with 10 cores, 4-core Raspberry Pi) there is no way to see which cores are saturated.

**Why it matters:** A single runaway process pins one core but barely moves the aggregate. Per-core view is the first step in diagnosing that class of problem.

**What competition does:** Per-core view in a task-manager-style panel alongside the aggregate chart.

**What was built:**
- Agent (`metrics.py`): switched to `psutil.cpu_percent(percpu=True, interval=0.1)`, computes aggregate as mean, adds `cpu.cores_percent` list to `/system` response.
- Forwarder (`forwarder.py`): forwards `cpu_cores` list alongside the existing aggregate.
- Server (`server.py`): adds `cpu_cores_json TEXT` column via `_ensure_column` (zero-downtime migration), stores as JSON, returns parsed in `/data`.
- Dashboard: new **Per-Core CPU (%)** horizontal bar chart (`chart-cpu-cores`) — color-coded cyan (<50 %), amber (50–80 %), red (≥80 %). Registered in `CHART_WIDGETS` drag/hide panel. Shows the latest poll's snapshot so it always reflects current core distribution.

---

### P1-4 · 30-Day Timeframe Selector in Dashboard

**Gap:** The server already stores up to 30 days of data (`STATIX_RETENTION_DAYS` default), but the dashboard only exposes 1 h / 24 h / 7 d selectors. The extra three weeks of data are unreachable.

**Why it matters:** One-week views miss weekly traffic patterns and make it hard to distinguish a new recurring problem from a one-time event.

**What competition does:** Offers 1 h / 24 h / 7 d / 30 d selectors; queries pre-aggregated data for older ranges.

**Scope of change:**
- Server: add `"30d"` to `TIMEFRAME_PRESETS` and `TIMEFRAME_LABELS`.
- Dashboard: add the 30 d button to the time-range picker.
- Note: 30 days of raw rows (≈86 000 at 30-second polls) will render slowly without downsampling. This is acceptable as a first pass; server-side aggregation is a separate Phase 3 item (P3-5).

---

### P1-5 · All System Temperature Sensors

**Gap:** The agent already calls `psutil.sensors_temperatures()` but discards everything except the single CPU sensor. GPU, NVMe, SSD, and motherboard temperatures are silently dropped.

**Why it matters:** An overheating NVMe or GPU triggers throttling and silent data corruption long before it causes a crash. Seeing all sensors requires zero new dependencies.

**What competition does:** Surfaces all detected temperature sensors; supports allowlist/blocklist patterns.

**Scope of change:**
- Agent: return the full `sensors_temperatures()` dict instead of only the CPU entry. Each entry is `{sensor_name: [{label, current_c, high_c, critical_c}]}`.
- Dashboard: a "Temperatures" card listing every sensor by name with color coding (green / amber / red based on `high_c` and `critical_c` thresholds if available); hidden entirely when no sensors are detected.
- Optional: `STATIX_SENSOR_INCLUDE` / `STATIX_SENSOR_EXCLUDE` env vars for glob filtering.

---

## Phase 2 — Medium Effort, High Value

> Each item requires changes across two or three layers (agent + server, or server + dashboard) but does not require a new architectural component. Expect one to three days per item.

---

### P2-1 · Expanded Threshold Alerts and Multi-Channel Notifications

**Gap:** Alerts fire only for CPU % and RAM %, only to a single webhook URL, and thresholds are global env vars shared by all hosts.

**Why it matters:** Disk-full is the most common production incident and is currently silent. A Slack or Telegram message is far more useful than a raw JSON POST that requires another system to relay it.

**What competition does:** Alerts on CPU, RAM, disk, temperature, load average, and bandwidth. Delivers to 23+ channels via Shoutrrr URL convention.

**Scope of change:**
- **New alert metrics:** disk usage %, CPU temperature (°C), load average (1-min), and network bandwidth (bytes/s) — each with its own env-var threshold.
- **New notification channels:** add Slack (incoming webhook), Telegram (bot token + chat ID), Discord (webhook URL), and SMTP email — alongside the existing generic webhook. Internally define a `_notify(message)` function that fans out to every configured channel.
- **Quiet hours:** `STATIX_ALERT_QUIET_START` / `STATIX_ALERT_QUIET_END` (HH:MM 24-hour format); alerts during this window are silently discarded.
- **Host-offline alert:** a background thread checks last-seen timestamps; if a host goes silent for longer than `STATIX_OFFLINE_THRESHOLD_SECONDS` (default 300), an alert fires. A recovery notification fires when the host next reports in.

---

### P2-2 · Per-Container Resource Metrics

**Gap:** The agent calls `docker ps` and checks for image updates, but never queries container CPU %, memory, or network I/O. You cannot tell which container is eating your RAM.

**Why it matters:** On a homelab server running 10+ containers the aggregate memory chart tells you nothing about which service is responsible for a spike.

**What competition does:** Polls `docker stats` per container and stores time-series data for each; renders a collapsible per-container panel.

**Scope of change:**
- Agent: call `docker stats --no-stream --format json` for all running containers; return a list of `{name, cpu_pct, mem_used_bytes, mem_limit_bytes, net_rx_bytes, net_tx_bytes}`.
- Agent: respect `STATIX_EXCLUDE_CONTAINERS` env var (comma-separated glob patterns) to omit infra/noise containers.
- Server: new `container_metrics` table keyed by `(hostname, container_name, timestamp)`.
- Dashboard: collapsible container panel per host with current-value bars and optionally mini time-series sparklines.

---

### P2-3 · S.M.A.R.T. Disk Health

**Gap:** Physical disk failure attributes (reallocated sectors, pending sectors, spin-up failure count) are completely invisible. A drive can deteriorate for weeks with no signal in statix.

**Why it matters:** S.M.A.R.T. data provides the only warning window between a healthy drive and data loss. On a NAS or server that runs 24/7 this is the highest-value operational metric that is currently missing.

**What competition does:** Calls `smartctl` (smartmontools) per physical device; surfaces eMMC wear level and mdraid health as separate indicators.

**Scope of change:**
- Agent: if `smartctl` is on PATH, call `smartctl -j -a /dev/<device>` for each physical block device; parse JSON output.
- Report: overall health assessment, reallocated sector count, pending sector count, power-on hours, and drive temperature per device.
- Dashboard: a disk-health card with an OK / Warning / Critical badge per drive. Warning fires when any critical attribute is non-zero.
- Alert: integrates with the alerting system (P2-1) — fires when any drive transitions from OK to Warning/Critical.
- Graceful degradation: if `smartmontools` is not installed, the card is hidden and no error is raised.

---

### P2-4 · Per-Host Alert Configuration

**Gap:** Alert thresholds are global server env vars. You cannot set a different CPU threshold for a high-load build server versus a nearly-idle Raspberry Pi.

**Why it matters:** One-size-fits-all thresholds produce either too many false positives on busy machines or too few alerts on quiet ones.

**What competition does:** Every system has its own alert configuration stored per-host in the database.

**Scope of change:**
- Server: add a `host_alerts` JSON column to the `host_details` table to store per-host threshold overrides for each alert metric.
- API: `PUT /hosts/<hostname>/alerts` to set overrides; `GET /hosts/<hostname>/alerts` to read them.
- Server alert evaluation: read per-host config at evaluation time, fall back to global env-var defaults if not set.
- Dashboard: an "Alert settings" panel per host with input fields for each threshold; saves via the new endpoint.

---

## Phase 3 — Larger Effort, Optional

> These items require new architectural components, significant schema changes, or cross-cutting concerns that touch every layer. Plan for a week or more per item with dedicated design discussion before starting.

---

### P3-1 · Multi-User Accounts

**Gap:** There is one shared API key and one dashboard view for everyone. A household or small team cannot have separate logins with different visible hosts or personal preferences.

**Why it matters:** Without user accounts, per-user settings (alert configs, widget order, host ownership) have no place to live. Multi-user is also a prerequisite for OAuth2 login (P3-2) and token-based agent pairing (P3-3).

**What competition does:** Supports multiple user accounts with admin and viewer roles; systems are owned by a user and can be shared with others; admins see everything.

**Scope of change:**
- New `users` table: `id`, `email`, `password_hash` (bcrypt), `role` (admin / viewer), `created_at`.
- Session or JWT-based login flow; login page served by Flask.
- `host_details` gains `owner_user_id`; viewers see only their own hosts, admins see all.
- First-run setup wizard creates the initial admin account (triggered when `users` table is empty).
- All existing API key logic is preserved as a legacy mode for single-user deployments.

---

### P3-2 · OAuth2 / OIDC Login

**Gap:** Managing a local password for a personal tool is friction most homelab users skip, leading to running the server unauthenticated. Most already have a GitHub or Google account, or a self-hosted IdP.

**Why it matters:** A real login flow without a password to manage dramatically lowers the barrier to enabling auth.

**What competition does:** Supports GitHub, Google, Discord, Microsoft, and any standard OIDC provider.

**Scope of change (requires P3-1 first):**
- OAuth2 authorization-code flow implemented in Flask using `requests-oauthlib` or similar.
- At minimum: GitHub and Google as built-in providers, configurable via env vars (client ID, client secret, redirect URI).
- Any standard OIDC provider supported via `STATIX_OIDC_ISSUER` + client credentials.
- `STATIX_ALLOW_USER_CREATION=true/false` controls whether new users are auto-provisioned on first OAuth login or must be pre-created by an admin.

---

### P3-3 · Token-Based Agent Pairing

**Gap:** Adding a new host requires pre-configuring the same API key on both server and agent, out of band. There is no registration handshake — anyone with the key can POST metrics.

**Why it matters:** Once multi-user exists, a shared API key is no longer meaningful. Each host should be owned by a specific user and provisioned with a per-host secret.

**What competition does:** Hub displays a pairing token; agent presents it on first connection and is registered automatically; subsequent requests use a per-host secret.

**Scope of change (requires P3-1 first):**
- Server: `/pairing-tokens` endpoint generates a short-lived token displayed in the dashboard.
- Agent: presents token in first `POST /metrics`; server validates, registers the host under the token owner's user account, and returns a per-host secret.
- Subsequent agent requests use the per-host secret instead of the universal token.
- Old shared API key mode remains as a fallback for single-user / no-auth deployments.

---

### P3-4 · i18n Foundation

**Gap:** All UI strings are hard-coded in English inside `dashboard.html`. There is no mechanism to add or switch languages.

**Why it matters:** statix is used internationally. A locale foundation that ships English by default lets community contributors add translations without touching application code.

**What competition does:** Ships English, French, Polish, Italian, Spanish, and German out of the box.

**Scope of change:**
- Extract every user-facing string from `dashboard.html` into a JS locale dictionary (e.g., `window.STATIX_LOCALE = {...}`).
- Server injects the active locale dict based on `STATIX_LOCALE` env var or `Accept-Language` header.
- English is the default and reference locale.
- Adding a new language = adding one JSON file; no Python or template changes required.

---

### P3-5 · Server-Side Data Downsampling

**Gap:** Every poll cycle writes one raw row. At a 30-second interval, 30 days of data per host = ~86 000 rows. The 30-day chart selector (P1-4) will be slow to query and slow to render at this volume.

**Why it matters:** Without downsampling, retention beyond a week is expensive. This is the enabler for long-term trend analysis.

**What competition does:** Aggregates raw rows into hourly averages for data older than 24 hours, keeping query time flat regardless of retention window.

**Scope of change:**
- Background thread (nightly): replace N per-minute rows older than a configurable threshold with 1 averaged row per hour (or configurable bucket size). Lossy by design.
- A `resolution` column or separate aggregated table tracks which rows are raw vs averaged.
- `/data` endpoint transparently returns pre-averaged rows when the requested timeframe exceeds the raw-resolution window.

---

### P3-6 · S3-Compatible Backup and Restore

**Gap:** The SQLite database lives in a Docker named volume with no automated off-host backup. A disk failure or accidental `docker volume rm` loses all history permanently.

**Why it matters:** Operational data accumulated over months has real value. A single-command restore path is the difference between a five-minute recovery and starting from scratch.

**What competition does:** Automatic scheduled backup to any S3-compatible storage (Backblaze B2, MinIO, AWS S3).

**Scope of change:**
- Server reads `STATIX_BACKUP_S3_ENDPOINT`, `STATIX_BACKUP_S3_BUCKET`, `STATIX_BACKUP_S3_KEY_ID`, and `STATIX_BACKUP_S3_SECRET` from env.
- Backup runs on a configurable schedule (`STATIX_BACKUP_CRON`, default `0 2 * * *`).
- Uses SQLite's online backup API to copy the live database without locking.
- A companion `statix-restore <backup-key>` CLI command downloads and replaces the local database.

---

## Beyond the Priority List — Additional Gaps

The following items also appear in competition but were not in the original priority list. They are lower urgency but fully documented so nothing is forgotten.

---

### P+-1 · Battery Status

**Gap:** Laptops and certain SBCs (Raspberry Pi with UPS HAT) have a battery; its charge level and charging state are completely invisible.

**Why it matters:** An unmonitored battery that degrades silently can mean a surprise outage when mains power drops. The indicator should simply be hidden on hosts where no battery is detected.

**What competition does:** Reports battery charge % and AC/charging state alongside system info.

**Scope of change:**
- Agent: call `psutil.sensors_battery()` and include `charge_pct` and `plugged_in` boolean in the payload.
- Dashboard: a battery indicator widget on applicable hosts; hidden entirely when `sensors_battery()` returns `None`.

---

### P+-2 · Multiple Disk Partitions

**Gap:** Only the root (`/`) filesystem is monitored. Hosts with secondary drives, external USB disks, NAS mounts, or SD card splits are blind to non-root capacity.

**Why it matters:** On a NAS or media server the data drives are not `/`. Disk-full on a secondary mount causes silent failures in applications, not a clean crash.

**What competition does:** Monitors all user-relevant mount points with include/exclude filter support.

**Scope of change:**
- Agent: enumerate all physical / non-virtual mount points via `psutil.disk_partitions(all=False)`.
- Each partition reported as a named entry: `{mount, device, fstype, used_bytes, total_bytes}`.
- Optional: `STATIX_DISK_INCLUDE` / `STATIX_DISK_EXCLUDE` env vars (comma-separated glob patterns on mount path).
- Dashboard: replace the single root disk card with a per-partition breakdown card.
- Server: store the partition list as a JSON column; disk alert (P2-1) evaluates each partition independently.

---

### P+-3 · Disk I/O Per Device

**Gap:** `psutil.disk_io_counters()` is called without `perdisk=True`, returning a single aggregate read/write counter. On hosts with multiple drives you cannot isolate which device is the bottleneck.

**Why it matters:** A failing or slow HDD dragging down I/O is masked by SSDs in the aggregate. Per-device breakdown is essential for any multi-drive setup.

**What competition does:** Tracks per-device I/O rates and attributes them to their respective panels.

**Scope of change:**
- Agent: call `disk_io_counters(perdisk=True)` and return a dict keyed by device name.
- Forwarder: compute per-device throughput deltas between polls (same logic as current aggregate).
- Server: store per-device I/O as a JSON column alongside the existing aggregate.
- Dashboard: a device selector dropdown or stacked I/O chart showing per-device read/write rates.

---

### P+-4 · GPU Monitoring

**Gap:** GPU utilization and VRAM usage are not tracked at all. Homelab AI workloads (Ollama, Stable Diffusion, Plex transcoding) make GPU the most important resource on many machines.

**Why it matters:** Without GPU metrics you are flying blind on the most expensive and most contended resource for modern homelab workloads.

**What competition does:** Supports NVIDIA (nvml + nvidia-smi), AMD (ROCm / amd_sysfs), Intel, and Apple Silicon via macmon.

**Scope of change:**
- Agent: attempt GPU collection via whichever backend is available on the host — `nvidia-smi --query-gpu`, `rocm-smi`, macOS `macmon`, or Intel sysfs.
- Report per GPU: `utilization_pct`, `vram_used_bytes`, `vram_total_bytes`, `temperature_c`, `name`.
- Dashboard: a GPU card that hides gracefully when no GPU is detected; renders utilization % and VRAM bar.
- Integrates with the temperature alerts in P2-1 if `temperature_c` is available.

---

### P+-5 · Systemd Service Health

**Gap:** There is no way to track whether key background services (databases, VPN, custom daemons) are running. A crashed service is invisible until a user notices something is broken.

**Why it matters:** Service liveness is the most actionable operational signal. Knowing `postgresql` has stopped is more useful than seeing CPU drop to 0%.

**What competition does:** Tracks a user-configurable list of systemd unit states and surfaces them as status indicators.

**Scope of change:**
- Agent: reads `STATIX_SERVICES` env var (comma-separated unit names, e.g. `postgresql,nginx,wireguard`).
- For each name, calls `systemctl is-active <name>` and records the state string (`active`, `inactive`, `failed`, etc.).
- Payload includes `{name, state}` list; gracefully skipped on non-systemd hosts (macOS, Windows).
- Dashboard: a "Services" card with green/amber/red status indicators per service; hidden when list is empty.
- Alert integration (P2-1): fires when any tracked service transitions to `failed` or `inactive`.

---

### P+-6 · Podman Support

**Gap:** The agent searches for the Docker binary only. Podman is a common rootless Docker alternative on Fedora, RHEL, and some Raspberry Pi OS configurations; those hosts report no container data at all.

**Why it matters:** Rootless Podman is the preferred runtime on SELinux-enforcing systems and is increasingly common in homelab setups. Zero configuration should be required for it to just work.

**What competition does:** Detects the Podman socket interchangeably with Docker; no user configuration needed.

**Scope of change:**
- Agent: if Docker binary/socket is not found, fall back to the Podman binary (`podman`) or its socket at `/run/user/<uid>/podman/podman.sock`.
- The same container list, stats, and update-check logic applies — Podman's CLI is Docker-compatible.
- No user configuration required; auto-detected at startup.

---

### P+-7 · Comparative Multi-Host Overview Grid

**Gap:** Comparing the state of multiple hosts requires cycling through them one at a time. There is no at-a-glance view showing all hosts simultaneously.

**Why it matters:** The first thing anyone does when something feels slow is check all machines at once. A status grid is the entry point that makes multi-host monitoring feel like a product rather than a tool.

**What competition does:** Hub landing page shows all systems as cards with live CPU %, RAM %, disk %, and online status; clicking drills into the detail view.

**Scope of change:**
- Dashboard: a new "Overview" page (or the default landing view) showing one card per host.
- Each card displays: hostname, online/offline status, current CPU %, RAM %, disk % (root), and last-seen timestamp.
- Card data pulled from the existing `/hosts` + `/details` endpoints; no new API needed.
- Clicking a card navigates to the existing per-host chart view.

---

### P+-8 · Host Groups / Tags

**Gap:** Hosts appear in a flat list. As the number of monitored machines grows beyond five or six, the list becomes hard to navigate. Users want to separate "home servers" from "VPS" or "Raspberry Pis".

**Why it matters:** Organisation is not a nice-to-have once you have more than a handful of hosts; without it, the dashboard does not scale.

**What competition does:** Hosts are grouped implicitly by user ownership; explicit tagging is community-requested.

**Scope of change:**
- `host_details`: add optional `group` text column (default: empty / ungrouped).
- Dashboard: group host cards under collapsible section headers in both the overview grid (P+-7) and the host selector.
- API: `PUT /hosts/<hostname>/group` to set or clear a group tag.
- No group = appears in an "Ungrouped" section or at the top level.

---

### P+-9 · Homebrew Formula

**Gap:** macOS and Linux Homebrew users have no native package manager install path. The current one-liner runs a Bash script that must be re-run manually to upgrade.

**Why it matters:** `brew install` + `brew upgrade` is the gold standard for Mac admins. Homebrew handles versioning, PATH, and service management automatically.

**What competition does:** Publishes a Homebrew tap; install and auto-update handled by `brew upgrade`.

**Scope of change:**
- Create a `homebrew-statix` tap repository under the GitHub org.
- Formula downloads the correct pre-built agent binary for the platform (`darwin-arm64`, `darwin-amd64`, `linux-arm64`, `linux-amd64`).
- Formula `service` block registers the agent as a launchd (macOS) or systemd (Linux) service — same behaviour as the current `install.sh`.
- CI: publish versioned binaries to GitHub Releases on each tag so the formula has stable download URLs.

---

### P+-10 · Windows Agent

**Gap:** The agent is POSIX-only. It uses `systemctl`, shell subprocesses, `osx-cpu-temp`, and POSIX path conventions throughout. Windows hosts are entirely unmonitored.

**Why it matters:** Windows machines (gaming PCs doubling as homelab nodes, Windows Server VMs) are a common part of mixed homelabs and are currently excluded from statix.

**What competition does:** Supports Windows via WinGet/Scoop packages; installs as a Windows service via NSSM.

**Scope of change:**
- Audit every OS-specific call in `metrics.py` and add `platform.system() == "Windows"` branches or Windows equivalents (`wmi`, `winreg`, PowerShell subprocess).
- Replace `systemctl is-active` (service health) with `sc query` or `Get-Service`.
- Replace `osx-cpu-temp` with WMI temperature queries.
- Provide a PowerShell install script that registers the agent as a Windows service.
- Add `windows-latest` to the GitHub Actions CI matrix for agent tests.

---

### P+-11 · Reverse Proxy Subpath Deployment

**Gap:** Running statix at `/statix/` instead of the domain root (e.g., behind an Nginx `location /statix` block) breaks all static asset references, API calls, and redirect URLs.

**Why it matters:** Many homelab reverse proxy setups host multiple services under a single domain using path prefixes. Statix is unusable in that configuration today.

**What competition does:** Supports subpath deployment via a `BASE_PATH` environment variable.

**Scope of change:**
- Server: read `STATIX_BASE_PATH` (e.g., `/statix`) and prefix all generated hrefs, API paths, and redirect targets.
- Dashboard template: use a `{{ base_path }}` Jinja variable for all asset `src`/`href` attributes.
- `install.sh` and `server/README.md`: document the env var with an example Nginx and Caddy config snippet.

---

## Priority Summary

| ID | Feature | Phase | Effort |
|---|---|---|---|
| ✅ P1-1 | Swap usage as time-series chart | Phase 1 — Low effort / High value | Low |
| ✅ P1-2 | System load average | Phase 1 — Low effort / High value | Low |
| P1-3 ✅ | Per-core CPU breakdown | Phase 1 — Low effort / High value | Low |
| P1-4 | 30-day timeframe selector in dashboard | Phase 1 — Low effort / High value | Low |
| P1-5 | All system temperature sensors | Phase 1 — Low effort / High value | Low |
| P2-1 | Expanded alerts + multi-channel notifications | Phase 2 — Medium effort / High value | Medium |
| P2-2 | Per-container resource metrics | Phase 2 — Medium effort / High value | Medium |
| P2-3 | S.M.A.R.T. disk health | Phase 2 — Medium effort / High value | Medium |
| P2-4 | Per-host alert configuration | Phase 2 — Medium effort / High value | Medium |
| P3-1 | Multi-user accounts | Phase 3 — Larger effort / Optional | High |
| P3-2 | OAuth2 / OIDC login | Phase 3 — Larger effort / Optional | High |
| P3-3 | Token-based agent pairing | Phase 3 — Larger effort / Optional | High |
| P3-4 | i18n foundation | Phase 3 — Larger effort / Optional | High |
| P3-5 | Server-side data downsampling | Phase 3 — Larger effort / Optional | High |
| P3-6 | S3-compatible backup and restore | Phase 3 — Larger effort / Optional | High |
| P+-1 | Battery status | Beyond priority list | Low |
| P+-2 | Multiple disk partitions | Beyond priority list | Medium |
| P+-3 | Disk I/O per device | Beyond priority list | Medium |
| P+-4 | GPU monitoring | Beyond priority list | Medium |
| P+-5 | Systemd service health | Beyond priority list | Medium |
| P+-6 | Podman support | Beyond priority list | Low |
| P+-7 | Comparative multi-host overview grid | Beyond priority list | Medium |
| P+-8 | Host groups / tags | Beyond priority list | Medium |
| P+-9 | Homebrew formula | Beyond priority list | Medium |
| P+-10 | Windows agent | Beyond priority list | High |
| P+-11 | Reverse proxy subpath deployment | Beyond priority list | Low |

**Effort key:** Low = a few hours, single PR. Medium = one to three days, multi-layer change. High = a week or more, requires design discussion before starting.

---

*This roadmap is a living document. Items may be reprioritized, split, or dropped as implementation begins. No item commits to a specific implementation approach — that belongs in a per-feature design note or PR description.*
