#!/usr/bin/env bash
#
# Roche_nxt — Offline Docker installer
#
# Detects the host OS and installs Docker Engine + Compose plugin from
# packages pre-staged on the USB bundle. No internet access is needed.
#
# Supported layouts under <bundle-root>/docker/:
#   ubuntu-22.04/*.deb
#   ubuntu-24.04/*.deb
#   rhel-8/*.rpm
#   rhel-9/*.rpm
#
# Typical .deb set (Ubuntu):
#   containerd.io_<ver>.deb
#   docker-ce_<ver>.deb
#   docker-ce-cli_<ver>.deb
#   docker-buildx-plugin_<ver>.deb
#   docker-compose-plugin_<ver>.deb
#
# Run as root. Invoked automatically from offline_install.sh.
#

set -Eeuo pipefail

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
    C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_BLD=""; C_RST=""
fi

log()  { echo "${C_CYN}[docker]${C_RST} $*"; }
ok()   { echo "  ${C_GRN}✓${C_RST} $*"; }
warn() { echo "  ${C_YEL}!${C_RST} $*"; }
die()  { echo "  ${C_RED}✗ $*${C_RST}" >&2; exit 1; }

BUNDLE_ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle-root) BUNDLE_ROOT="$(cd "$2" && pwd)"; shift 2 ;;
        -h|--help)
            echo "Usage: sudo bash $(basename "$0") --bundle-root <USB-path>"
            exit 0 ;;
        *) die "Unknown arg: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "Must run as root."
[[ -n "$BUNDLE_ROOT" && -d "$BUNDLE_ROOT/docker" ]] \
    || die "Specify --bundle-root; docker/ directory must exist under it."

# ---------------------------------------------------------------------------
# Detect OS
# ---------------------------------------------------------------------------
[[ -f /etc/os-release ]] || die "/etc/os-release missing."
# shellcheck disable=SC1091
. /etc/os-release

OS_ID="${ID:-unknown}"
OS_VER="${VERSION_ID:-unknown}"

case "${OS_ID}_${OS_VER}" in
    ubuntu_22.04) DIST_DIR="ubuntu-22.04"; PKG_MGR="apt" ;;
    ubuntu_24.04) DIST_DIR="ubuntu-24.04"; PKG_MGR="apt" ;;
    ubuntu_*)     DIST_DIR="ubuntu-${OS_VER}"; PKG_MGR="apt"
                  warn "Ubuntu ${OS_VER} not officially tested here; trying ${DIST_DIR}/" ;;
    debian_12)    DIST_DIR="debian-12"; PKG_MGR="apt" ;;
    rhel_8|centos_8|rocky_8|almalinux_8) DIST_DIR="rhel-8"; PKG_MGR="rpm" ;;
    rhel_9|centos_9|rocky_9|almalinux_9) DIST_DIR="rhel-9"; PKG_MGR="rpm" ;;
    *)            die "Unsupported OS: ${PRETTY_NAME:-$OS_ID $OS_VER}" ;;
esac

PKG_DIR="${BUNDLE_ROOT}/docker/${DIST_DIR}"
[[ -d "$PKG_DIR" ]] || die "No packages at ${PKG_DIR} for this OS. Re-build the USB bundle with --docker-for ${DIST_DIR}."

log "Detected: ${PRETTY_NAME:-$OS_ID $OS_VER} — using ${DIST_DIR}/"

# ---------------------------------------------------------------------------
# Stop any existing docker.service (clean reinstall)
# ---------------------------------------------------------------------------
if systemctl list-units --type=service 2>/dev/null | grep -q docker.service; then
    systemctl stop docker.service 2>/dev/null || true
    systemctl stop docker.socket  2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
if [[ "$PKG_MGR" == "apt" ]]; then
    shopt -s nullglob
    DEBS=("$PKG_DIR"/*.deb)
    shopt -u nullglob
    [[ ${#DEBS[@]} -gt 0 ]] || die "No .deb files found in ${PKG_DIR}."

    log "Installing ${#DEBS[@]} .deb packages..."
    # Try dpkg first; if it fails on deps, fall back to apt (which may pull
    # from local cache on an air-gapped host; otherwise errors clearly).
    if ! dpkg -i "${DEBS[@]}" 2>/tmp/docker_dpkg.log; then
        warn "dpkg reported missing dependencies — trying apt-get to fix."
        apt-get install -y -f --no-download 2>/dev/null \
            || die "Dependency resolution failed. Check /tmp/docker_dpkg.log. You may need to stage additional .deb files in ${PKG_DIR}."
    fi
    ok "Packages installed"

elif [[ "$PKG_MGR" == "rpm" ]]; then
    shopt -s nullglob
    RPMS=("$PKG_DIR"/*.rpm)
    shopt -u nullglob
    [[ ${#RPMS[@]} -gt 0 ]] || die "No .rpm files found in ${PKG_DIR}."

    log "Installing ${#RPMS[@]} .rpm packages..."
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y --disablerepo="*" "${RPMS[@]}" || die "rpm install failed."
    else
        rpm -Uvh --force --nodeps "${RPMS[@]}" || die "rpm install failed."
    fi
    ok "Packages installed"
fi

# ---------------------------------------------------------------------------
# Enable & start
# ---------------------------------------------------------------------------
systemctl enable docker.service >/dev/null 2>&1 || true
systemctl start  docker.service

# Brief wait for socket
for i in {1..10}; do
    if docker info >/dev/null 2>&1; then
        ok "Docker daemon is up"
        break
    fi
    sleep 1
    [[ $i -eq 10 ]] && die "Docker failed to start. Check: journalctl -u docker --no-pager | tail -50"
done

DOCKER_VER="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?')"
COMPOSE_VER="$(docker compose version --short 2>/dev/null || echo 'missing')"

ok "Docker:  ${DOCKER_VER}"
ok "Compose: ${COMPOSE_VER}"

if [[ "$COMPOSE_VER" == "missing" ]]; then
    die "docker-compose-plugin was not installed. Add it to ${PKG_DIR}/ and retry."
fi

log "Docker is ready."
