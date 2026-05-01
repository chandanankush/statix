#!/usr/bin/env bash
# Statix Client Installer — macOS & Raspberry Pi / Linux
#
# One-line install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh \
#     | bash -s -- --server-url http://YOUR_SERVER:5050 --interval 30
#
set -euo pipefail

GITHUB_REPO="chandanankush/statix"
GITHUB_BRANCH="main"
PACKAGE_URL="git+https://github.com/${GITHUB_REPO}.git@${GITHUB_BRANCH}#subdirectory=client"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[•]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ── parse CLI args ────────────────────────────────────────────────────────────
SERVER_URL=""
INTERVAL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --server-url) SERVER_URL="$2"; shift 2 ;;
        --interval)   INTERVAL="$2";   shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── detect OS ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *) die "Unsupported OS: $OS. This installer supports macOS and Linux (Raspberry Pi)." ;;
esac
success "Detected platform: $PLATFORM"

# ── check Python 3.9+ ─────────────────────────────────────────────────────────
header "Checking Python …"
PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" &>/dev/null; then
        ver=$("$candidate" -c 'import sys; print(sys.version_info[:2])' 2>/dev/null || true)
        major=$("$candidate" -c 'import sys; print(sys.version_info[0])' 2>/dev/null || true)
        minor=$("$candidate" -c 'import sys; print(sys.version_info[1])' 2>/dev/null || true)
        if [[ "$major" -ge 3 && "$minor" -ge 9 ]]; then
            PYTHON="$candidate"
            break
        fi
    fi
done

if [[ -z "$PYTHON" ]]; then
    if [[ "$PLATFORM" == "linux" ]]; then
        warn "Python 3.9+ not found. Installing via apt …"
        sudo apt-get update -qq
        sudo apt-get install -y python3 python3-pip python3-venv
        PYTHON="python3"
    else
        die "Python 3.9+ is required. Install it from https://www.python.org/downloads/macos/ or via Homebrew: brew install python"
    fi
fi
success "Using $($PYTHON --version)"

# ── install pip if missing (Raspberry Pi OS Lite) ────────────────────────────
if ! "$PYTHON" -m pip --version &>/dev/null 2>&1; then
    warn "pip not found. Installing …"
    if [[ "$PLATFORM" == "linux" ]]; then
        sudo apt-get install -y python3-pip
    else
        die "pip is missing. Run: curl https://bootstrap.pypa.io/get-pip.py | python3"
    fi
fi

# ── detect existing install & read saved config ──────────────────────────────
IS_UPGRADE=false
if "$PYTHON" -m pip show system-stats-service &>/dev/null 2>&1; then
    IS_UPGRADE=true
    warn "Existing installation detected — will upgrade."
fi

# Read saved config from existing service files so re-runs keep the same settings
_read_existing_config() {
    if [[ "$PLATFORM" == "macos" ]]; then
        local plist="$HOME/Library/LaunchAgents/com.local.systemstats.forwarder.plist"
        if [[ -f "$plist" ]]; then
            local raw_url; raw_url=$(grep -A1 'MONITORING_SERVER_METRICS_URL' "$plist" | grep '<string>' | sed 's|.*<string>\(.*\)</string>.*|\1|')
            local raw_int; raw_int=$(grep -A1 'SYSTEM_STATS_FORWARD_INTERVAL' "$plist"    | grep '<string>' | sed 's|.*<string>\(.*\)</string>.*|\1|')
            # strip trailing /metrics to recover the base server URL
            [[ -n "$raw_url" ]] && echo "url=${raw_url%/metrics}"
            [[ -n "$raw_int" ]] && echo "interval=${raw_int}"
        fi
    else
        local unit="$HOME/.config/systemd/user/system-stats-forwarder.service"
        if [[ -f "$unit" ]]; then
            local raw_url; raw_url=$(grep 'MONITORING_SERVER_METRICS_URL=' "$unit" | cut -d= -f2-)
            local raw_int; raw_int=$(grep 'SYSTEM_STATS_FORWARD_INTERVAL='    "$unit" | cut -d= -f2-)
            [[ -n "$raw_url" ]] && echo "url=${raw_url%/metrics}"
            [[ -n "$raw_int" ]] && echo "interval=${raw_int}"
        fi
    fi
}

if [[ -z "$SERVER_URL" || -z "$INTERVAL" ]]; then
    while IFS='=' read -r key val; do
        case "$key" in
            url)      [[ -z "$SERVER_URL" ]] && SERVER_URL="$val" ;;
            interval) [[ -z "$INTERVAL"   ]] && INTERVAL="$val"   ;;
        esac
    done < <(_read_existing_config)
fi

# ── prompt for configuration ──────────────────────────────────────────────────
header "Configuration"

_default_url="${SERVER_URL:-http://127.0.0.1:5050}"
_default_int="${INTERVAL:-30}"

if [[ -z "$SERVER_URL" ]]; then
    read -rp "  Monitoring server URL [${_default_url}]: " SERVER_URL
    SERVER_URL="${SERVER_URL:-${_default_url}}"
else
    info "Keeping existing server URL : $SERVER_URL  (pass --server-url to change)"
fi

if [[ -z "$INTERVAL" ]]; then
    read -rp "  Forwarding interval in seconds [${_default_int}]: " INTERVAL
    INTERVAL="${INTERVAL:-${_default_int}}"
else
    info "Keeping existing interval    : ${INTERVAL}s  (pass --interval to change)"
fi

# strip trailing slash from server URL
SERVER_URL="${SERVER_URL%/}"
METRICS_URL="${SERVER_URL}/metrics"

info "Server metrics endpoint : $METRICS_URL"
info "Forward interval        : ${INTERVAL}s"

# ── install the Python package from GitHub ───────────────────────────────────
if [[ "$IS_UPGRADE" == true ]]; then
    header "Upgrading system-stats-service from GitHub …"
else
    header "Installing system-stats-service from GitHub …"
fi
info "Source: https://github.com/${GITHUB_REPO} (branch: ${GITHUB_BRANCH})"

# git is required for pip install from VCS
if ! command -v git &>/dev/null; then
    if [[ "$PLATFORM" == "linux" ]]; then
        warn "git not found. Installing …"
        sudo apt-get install -y git
    else
        die "git is required. Install Xcode Command Line Tools: xcode-select --install"
    fi
fi

"$PYTHON" -m pip install --user --quiet --upgrade "$PACKAGE_URL"
if [[ "$IS_UPGRADE" == true ]]; then
    success "Package upgraded"
else
    success "Package installed"
fi

# ── locate installed scripts ──────────────────────────────────────────────────
# pip --user puts scripts in ~/.local/bin (Linux) or ~/Library/Python/X.Y/bin (macOS)
find_script() {
    local name="$1"
    # Try PATH first (covers cases where user already has the right bin dir in PATH)
    if command -v "$name" &>/dev/null; then
        command -v "$name"
        return
    fi
    # Common user-scheme locations
    local candidates=(
        "$HOME/.local/bin/$name"
        "$("$PYTHON" -c 'import sysconfig; print(sysconfig.get_path("scripts", "posix_user"))')/$name"
        "$("$PYTHON" -m site --user-base)/bin/$name"
    )
    for p in "${candidates[@]}"; do
        [[ -x "$p" ]] && { echo "$p"; return; }
    done
    die "Could not locate '$name' after install. Make sure $("$PYTHON" -m site --user-base)/bin is in your PATH."
}

SVC_BIN="$(find_script system-stats-service)"
FWD_BIN="$(find_script system-stats-forwarder)"
success "Service binary  : $SVC_BIN"
success "Forwarder binary: $FWD_BIN"

# ── macOS setup (launchd) ─────────────────────────────────────────────────────
setup_macos() {
    local launch_agents="$HOME/Library/LaunchAgents"
    local log_dir="$HOME/Library/Logs"
    mkdir -p "$launch_agents" "$log_dir"

    # --- service plist ---
    cat > "$launch_agents/com.local.systemstats.service.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.local.systemstats.service</string>
    <key>ProgramArguments</key>
    <array>
      <string>${SVC_BIN}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>SYSTEM_STATS_HOST</key>
      <string>127.0.0.1</string>
      <key>SYSTEM_STATS_PORT</key>
      <string>5001</string>
      <key>SYSTEM_STATS_LOG_LEVEL</key>
      <string>info</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_dir}/system-stats-service.log</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/system-stats-service.log</string>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
  </dict>
</plist>
PLIST

    # --- forwarder plist ---
    cat > "$launch_agents/com.local.systemstats.forwarder.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.local.systemstats.forwarder</string>
    <key>ProgramArguments</key>
    <array>
      <string>${FWD_BIN}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
      <key>SYSTEM_STATS_URL</key>
      <string>http://127.0.0.1:5001/system</string>
      <key>MONITORING_SERVER_METRICS_URL</key>
      <string>${METRICS_URL}</string>
      <key>SYSTEM_STATS_FORWARD_INTERVAL</key>
      <string>${INTERVAL}</string>
      <key>SYSTEM_STATS_FORWARD_LOG_LEVEL</key>
      <string>INFO</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${log_dir}/system-stats-forwarder.log</string>
    <key>StandardErrorPath</key>
    <string>${log_dir}/system-stats-forwarder.log</string>
    <key>WorkingDirectory</key>
    <string>${HOME}</string>
  </dict>
</plist>
PLIST

    # Always unload first (no-op if not running) then reload with fresh plist
    launchctl unload "$launch_agents/com.local.systemstats.service.plist"  2>/dev/null || true
    launchctl unload "$launch_agents/com.local.systemstats.forwarder.plist" 2>/dev/null || true

    launchctl load -w "$launch_agents/com.local.systemstats.service.plist"
    launchctl load -w "$launch_agents/com.local.systemstats.forwarder.plist"

    if [[ "$IS_UPGRADE" == true ]]; then
        success "launchd agents reloaded with updated binaries"
    else
        success "launchd agents loaded and set to run at login"
    fi
    info "Logs → $log_dir/system-stats-service.log"
    info "Logs → $log_dir/system-stats-forwarder.log"

    info "Check status with:"
    echo "    launchctl list | grep systemstats"
}

# ── Linux / Raspberry Pi setup (systemd --user) ───────────────────────────────
setup_linux() {
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"

    # --- service unit ---
    cat > "$unit_dir/system-stats-service.service" <<UNIT
[Unit]
Description=System Stats API Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=SYSTEM_STATS_HOST=0.0.0.0
Environment=SYSTEM_STATS_PORT=5001
Environment=SYSTEM_STATS_LOG_LEVEL=info
ExecStart=${SVC_BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT

    # --- forwarder unit ---
    cat > "$unit_dir/system-stats-forwarder.service" <<UNIT
[Unit]
Description=System Stats Forwarder
After=network-online.target system-stats-service.service
Wants=network-online.target
Requires=system-stats-service.service

[Service]
Type=simple
Environment=SYSTEM_STATS_URL=http://127.0.0.1:5001/system
Environment=MONITORING_SERVER_METRICS_URL=${METRICS_URL}
Environment=SYSTEM_STATS_FORWARD_INTERVAL=${INTERVAL}
Environment=SYSTEM_STATS_FORWARD_LOG_LEVEL=INFO
ExecStart=${FWD_BIN}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT

    systemctl --user daemon-reload
    # enable (idempotent) then restart so updates take effect immediately
    systemctl --user enable system-stats-service.service
    systemctl --user enable system-stats-forwarder.service
    systemctl --user restart system-stats-service.service
    systemctl --user restart system-stats-forwarder.service

    # Enable linger so services survive logout / boot without interactive session
    if command -v loginctl &>/dev/null; then
        loginctl enable-linger "$(whoami)" 2>/dev/null || warn "Could not enable linger (run: sudo loginctl enable-linger $(whoami))"
    fi

    if [[ "$IS_UPGRADE" == true ]]; then
        success "systemd user services restarted with updated binaries"
    else
        success "systemd user services enabled and started"
    fi
    info "Check status with:"
    echo "    systemctl --user status system-stats-service"
    echo "    systemctl --user status system-stats-forwarder"
    info "Follow logs with:"
    echo "    journalctl --user -u system-stats-service -f"
    echo "    journalctl --user -u system-stats-forwarder -f"
}

# ── run platform setup ────────────────────────────────────────────────────────
header "Setting up services …"
if [[ "$PLATFORM" == "macos" ]]; then
    setup_macos
else
    setup_linux
fi

# ── done ──────────────────────────────────────────────────────────────────────
if [[ "$IS_UPGRADE" == true ]]; then
    header "Upgrade complete!"
else
    header "Installation complete!"
fi
echo -e "  Service API  → ${GREEN}http://127.0.0.1:5001/system${NC}"
echo -e "  Metrics sent → ${GREEN}${METRICS_URL}${NC}"
echo
echo -e "  To uninstall, run:"
  echo -e "  ${YELLOW}bash <(curl -fsSL https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}/client/uninstall.sh)${NC}"
