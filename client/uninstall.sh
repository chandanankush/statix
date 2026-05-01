#!/usr/bin/env bash
# Statix Client Uninstaller — macOS & Raspberry Pi / Linux
#
# One-line uninstall:
#   bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/client/uninstall.sh)
#
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[•]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

OS="$(uname -s)"
case "$OS" in
    Darwin) PLATFORM="macos" ;;
    Linux)  PLATFORM="linux" ;;
    *) die "Unsupported OS: $OS" ;;
esac

header "Uninstalling Statix client services …"

if [[ "$PLATFORM" == "macos" ]]; then
    launch_agents="$HOME/Library/LaunchAgents"
    for plist in \
        "$launch_agents/com.local.systemstats.service.plist" \
        "$launch_agents/com.local.systemstats.forwarder.plist"; do
        if [[ -f "$plist" ]]; then
            launchctl unload "$plist" 2>/dev/null || true
            rm -f "$plist"
            success "Removed $(basename "$plist")"
        fi
    done
else
    unit_dir="$HOME/.config/systemd/user"
    for unit in system-stats-service system-stats-forwarder; do
        systemctl --user disable --now "$unit.service" 2>/dev/null || true
        rm -f "$unit_dir/$unit.service"
        success "Removed $unit.service"
    done
    systemctl --user daemon-reload
fi

header "Removing Python package …"
if python3 -m pip show system-stats-service &>/dev/null 2>&1; then
    python3 -m pip uninstall -y system-stats-service
    success "Package removed"
else
    warn "Package not found in pip (already removed?)"
fi

success "Uninstall complete."
