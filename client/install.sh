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

# ── root guard ───────────────────────────────────────────────────────────────
# The installer writes into $HOME — running as root installs to /root, not the
# target user's home. Using 'sudo bash <(curl ...)' also breaks process
# substitution on many Linux systems (/dev/fd not available).
# Use the pipe form instead: curl -fsSL ... | bash -s -- [options]
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    echo -e "\033[0;31m[✗]\033[0m Do not run this installer as root or with sudo."
    echo    "    It installs into your user home directory and manages user services."
    echo    "    Run as your normal user:"
    echo    "      bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh)"
    echo    "    Or, if <(...) fails on your system:"
    echo    "      curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/install.sh | bash"
    exit 1
fi

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

# ── port helper ───────────────────────────────────────────────────────────────
# _free_port <port>  — kills any process holding <port>/tcp so our service can bind.
# Uses lsof (macOS + Linux), falling back to fuser (Linux only).  Safe to call
# even if nothing is running on the port.
_free_port() {
    local port="$1"
    local pids=""

    # Prefer fuser on Linux (always present); fall back to lsof (macOS / some Linux)
    if command -v fuser &>/dev/null; then
        pids=$(fuser "${port}/tcp" 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' || true)
    elif command -v lsof &>/dev/null; then
        pids=$(lsof -t -i TCP:"$port" -s TCP:LISTEN 2>/dev/null || true)
    fi

    if [[ -n "$pids" ]]; then
        warn "Port $port is in use (PID(s): $(echo "$pids" | tr '\n' ' ')). Stopping conflicting process(es) …"
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        # Give the OS a moment to release the socket
        local waited=0
        while [[ $waited -lt 5 ]]; do
            sleep 1
            waited=$((waited + 1))
            local still=""
            if command -v fuser &>/dev/null; then
                still=$(fuser "${port}/tcp" 2>/dev/null || true)
            elif command -v lsof &>/dev/null; then
                still=$(lsof -t -i TCP:"$port" -s TCP:LISTEN 2>/dev/null || true)
            fi
            [[ -z "$still" ]] && break
        done
        success "Port $port is now free"
    fi
}

# ── parse CLI args ────────────────────────────────────────────────────────────
SERVER_URL=""
INTERVAL=""
CLI_SERVER_URL=""   # set only when --server-url is passed; skips the prompt
CLI_INTERVAL=""     # set only when --interval is passed; skips the prompt
while [[ $# -gt 0 ]]; do
    case "$1" in
        --server-url) CLI_SERVER_URL="$2"; SERVER_URL="$2"; shift 2 ;;
        --interval)   CLI_INTERVAL="$2";   INTERVAL="$2";   shift 2 ;;
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

# ── detect existing install & read saved config ─────────────────────────────
VENV_DIR="$HOME/.local/share/statix/venv"
IS_UPGRADE=false
if [[ -x "$VENV_DIR/bin/system-stats-service" ]]; then
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
            local raw_url; raw_url=$(grep 'MONITORING_SERVER_METRICS_URL=' "$unit" | cut -d= -f3-)
            local raw_int; raw_int=$(grep 'SYSTEM_STATS_FORWARD_INTERVAL='    "$unit" | cut -d= -f3-)
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

_default_url="${SERVER_URL:-http://192.168.0.209:5050}"
_default_int="${INTERVAL:-30}"

# Always ask for the server URL so upgrades can easily change it.
# Only skip the prompt when --server-url was passed explicitly on the CLI.
if [[ -n "$CLI_SERVER_URL" ]]; then
    info "Using server URL from --server-url: $SERVER_URL"
else
    read -rp "  Monitoring server URL [${_default_url}]: " SERVER_URL
    SERVER_URL="${SERVER_URL:-${_default_url}}"
fi

if [[ -n "$CLI_INTERVAL" ]]; then
    info "Using interval from --interval: ${INTERVAL}s"
else
    read -rp "  Forwarding interval in seconds [${_default_int}]: " INTERVAL
    INTERVAL="${INTERVAL:-${_default_int}}"
fi

# strip trailing slash from server URL
SERVER_URL="${SERVER_URL%/}"
METRICS_URL="${SERVER_URL}/metrics"

info "Server metrics endpoint : $METRICS_URL"
info "Forward interval        : ${INTERVAL}s"

# ── install into a dedicated venv (avoids PEP 668 / externally-managed-env) ─
if [[ "$IS_UPGRADE" == true ]]; then
    header "Upgrading system-stats-service from GitHub …"
else
    header "Installing system-stats-service from GitHub …"
fi
info "Source: https://github.com/${GITHUB_REPO} (branch: ${GITHUB_BRANCH})"
info "Venv  : $VENV_DIR"

# git is required for pip install from VCS
if ! command -v git &>/dev/null; then
    if [[ "$PLATFORM" == "linux" ]]; then
        warn "git not found. Installing …"
        sudo apt-get install -y git
    else
        die "git is required. Install Xcode Command Line Tools: xcode-select --install"
    fi
fi

# ensure python3-venv module is present (Raspberry Pi OS Lite may omit it)
if ! "$PYTHON" -m venv --help &>/dev/null 2>&1; then
    if [[ "$PLATFORM" == "linux" ]]; then
        warn "python3-venv not found. Installing …"
        sudo apt-get install -y python3-venv
    else
        die "Python venv module is missing. Reinstall Python from https://www.python.org/"
    fi
fi

# Create the parent directory — if this fails, the home directory or ~/.local
# is likely owned by root from a previous 'sudo' run. Diagnose and advise.
if ! mkdir -p "$(dirname "$VENV_DIR")" 2>/dev/null; then
    if [[ ! -w "$HOME" ]]; then
        die "Your home directory $HOME is not writable by $(whoami).
    Fix it by running:
      sudo chown $(whoami):$(whoami) \"$HOME\"
    Then re-run this installer."
    else
        die "Cannot create $(dirname "$VENV_DIR") — directory may be owned by root.
    Fix it by running:
      sudo chown -R $(whoami):$(whoami) \"$HOME/.local\"
    Then re-run this installer."
    fi
fi
# create venv only on fresh install; on upgrade reuse the existing one
if [[ ! -d "$VENV_DIR" ]]; then
    "$PYTHON" -m venv "$VENV_DIR"
fi

if [[ "$IS_UPGRADE" == true ]]; then
    # Upgrade: force-reinstall our package only; deps are already present in the venv
    "$VENV_DIR/bin/pip" install --quiet --force-reinstall --no-deps "$PACKAGE_URL"
    success "Package upgraded"
else
    # Fresh install: install package and all dependencies
    "$VENV_DIR/bin/pip" install --quiet "$PACKAGE_URL"
    success "Package installed"
fi

# ── write installed git SHA as client version ─────────────────────────────────
# This file is read by metrics.py at runtime so the dashboard can detect stale clients.
# Try git ls-remote first; fall back to GitHub API via curl (works even without git).
_INSTALLED_SHA=$(git ls-remote "https://github.com/${GITHUB_REPO}.git" "refs/heads/${GITHUB_BRANCH}" 2>/dev/null | cut -c1-7 || true)
if [[ -z "$_INSTALLED_SHA" ]] && command -v curl &>/dev/null; then
    _INSTALLED_SHA=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/commits/${GITHUB_BRANCH}" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'][:7])" 2>/dev/null || true)
fi
if [[ -n "$_INSTALLED_SHA" ]]; then
    echo "$_INSTALLED_SHA" > "$(dirname "$VENV_DIR")/client_version"
    info "Client version  : $_INSTALLED_SHA"
else
    warn "Could not determine installed git SHA (network issue?). Version tracking may show a mismatch warning."
fi

# ── set binary paths (always inside the venv) ────────────────────────────────
SVC_BIN="$VENV_DIR/bin/system-stats-service"
FWD_BIN="$VENV_DIR/bin/system-stats-forwarder"
[[ -x "$SVC_BIN" ]] || die "system-stats-service binary not found in venv after install."
[[ -x "$FWD_BIN" ]] || die "system-stats-forwarder binary not found in venv after install."
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

    # Kill anything still holding port 5001 (e.g. a zombie process from a previous install)
    _free_port 5001

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

    # Kill anything still holding port 5001 before starting our service
    _free_port 5001

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
