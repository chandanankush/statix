#!/usr/bin/env bash
# Statix Server Installer
#
# One-line install (requires Docker):
#   bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh)
#
# With options:
#   curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/install.sh \
#     | bash -s -- --port 5050 --data-dir /opt/statix/data
#
set -euo pipefail

IMAGE="chandanankush/statix:latest"
CONTAINER="statix"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${BLUE}[•]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
die()     { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}$*${NC}"; }

# ── parse CLI args ─────────────────────────────────────────────────────────────
PORT=""
DATA_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)     PORT="$2";     shift 2 ;;
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── check Docker ───────────────────────────────────────────────────────────────
header "Checking Docker …"
command -v docker &>/dev/null || die "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
docker info &>/dev/null        || die "Docker daemon is not running. Start Docker and try again."
success "Docker is available"

# ── detect upgrade ─────────────────────────────────────────────────────────────
IS_UPGRADE=false
if docker inspect "$CONTAINER" &>/dev/null 2>&1; then
    IS_UPGRADE=true
    warn "Existing statix container found — will upgrade."

    # Read existing config so re-runs keep settings
    if [[ -z "$PORT" ]]; then
        PORT=$(docker inspect --format '{{range $p,$conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' "$CONTAINER" 2>/dev/null || true)
    fi
    if [[ -z "$DATA_DIR" ]]; then
        DATA_DIR=$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null || true)
    fi
fi

# ── prompt for config ──────────────────────────────────────────────────────────
header "Configuration"

_default_port="${PORT:-5050}"
_default_data="${DATA_DIR:-$HOME/.local/share/statix/data}"

if [[ -z "$PORT" ]]; then
    read -rp "  Dashboard port [${_default_port}]: " PORT
    PORT="${PORT:-${_default_port}}"
else
    info "Keeping existing port : $PORT  (pass --port to change)"
fi

if [[ -z "$DATA_DIR" ]]; then
    read -rp "  Data directory [${_default_data}]: " DATA_DIR
    DATA_DIR="${DATA_DIR:-${_default_data}}"
else
    info "Keeping existing data dir : $DATA_DIR  (pass --data-dir to change)"
fi

mkdir -p "$DATA_DIR"
info "Dashboard port : $PORT"
info "Data directory : $DATA_DIR"

# ── pull latest image ──────────────────────────────────────────────────────────
header "Pulling $IMAGE …"
if docker pull "$IMAGE" 2>/dev/null; then
    success "Image pulled from Docker Hub"
elif docker image inspect "$IMAGE" &>/dev/null 2>&1; then
    warn "Could not reach Docker Hub — using locally cached image."
else
    die "Image not available. Either Docker Hub is unreachable and no local cache exists,
     or the image has not been published yet.
     Build it locally with: docker build -t chandanankush/statix server/"
fi

# ── stop and remove existing container ────────────────────────────────────────
if docker inspect "$CONTAINER" &>/dev/null 2>&1; then
    info "Stopping existing container …"
    docker stop "$CONTAINER" &>/dev/null || true
    docker rm   "$CONTAINER" &>/dev/null || true
fi

# ── run the container ──────────────────────────────────────────────────────────
header "Starting statix …"
docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    -p "${PORT}:5000" \
    -v "${DATA_DIR}:/app/data" \
    -e DATABASE_PATH=/app/data/metrics.db \
    "$IMAGE"

success "statix is running"

# ── verify ─────────────────────────────────────────────────────────────────────
info "Waiting for health check …"
for i in {1..15}; do
    if curl -fsSL "http://127.0.0.1:${PORT}/health" &>/dev/null; then
        success "Health check passed"
        break
    fi
    sleep 1
    [[ $i -eq 15 ]] && warn "Health check timed out — container may still be starting."
done

# ── done ───────────────────────────────────────────────────────────────────────
if [[ "$IS_UPGRADE" == true ]]; then
    header "Upgrade complete!"
else
    header "Installation complete!"
fi
echo -e "  Dashboard → ${GREEN}http://127.0.0.1:${PORT}/dashboard${NC}"
echo
echo -e "  Useful commands:"
echo -e "    docker logs -f ${CONTAINER}"
echo -e "    docker stop ${CONTAINER}"
echo -e "    docker start ${CONTAINER}"
echo
echo -e "  To uninstall:"
echo -e "  ${YELLOW}bash <(curl -fsSL https://raw.githubusercontent.com/chandanankush/statix/main/server/uninstall.sh)${NC}"
