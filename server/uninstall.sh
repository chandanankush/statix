#!/usr/bin/env bash
# Statix Server Uninstaller
#
# One-line uninstall:
#   bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/uninstall.sh)
#
set -euo pipefail

CONTAINER="statix"
IMAGE="chandanankush/statix"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[•]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

command -v docker &>/dev/null || die "Docker is not installed."

header "Uninstalling statix …"

if docker inspect "$CONTAINER" &>/dev/null 2>&1; then
    info "Stopping container …"
    docker stop "$CONTAINER" &>/dev/null || true
    docker rm   "$CONTAINER"
    success "Container removed"
else
    warn "Container '$CONTAINER' not found (already removed?)"
fi

read -rp "  Remove the Docker image too? [y/N]: " remove_image
if [[ "$(echo "$remove_image" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    docker rmi "$IMAGE:latest" 2>/dev/null && success "Image removed" || warn "Image not found locally"
fi

read -rp "  Remove data directory? This deletes all stored metrics. [y/N]: " remove_data
if [[ "$(echo "$remove_data" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
    data_dir="$HOME/.local/share/statix/data"
    if [[ -d "$data_dir" ]]; then
        rm -rf "$data_dir"
        success "Data directory removed ($data_dir)"
    else
        warn "Default data directory not found. If you used a custom path, remove it manually."
    fi
fi

success "Uninstall complete."
