#!/usr/bin/env bash
#
# Roche_nxt — Fetch Docker offline install packages from the internet.
#
# Runs on the packager's online machine (this script needs Docker installed
# locally; it spins up a transient container for the *target* OS and uses
# that container's package manager to download the official Docker packages
# along with all transitive dependencies). The result is a directory of
# .deb / .rpm files that can be staged on the USB bundle.
#
# Supported targets (must match install_docker.sh layout):
#   ubuntu-22.04   (jammy)
#   ubuntu-24.04   (noble)
#   debian-12      (bookworm)
#   rhel-8         (rocky:8 image)
#   rhel-9         (rocky:9 image)
#
# Usage
#   bash deploy/scripts/fetch_docker_packages.sh <distro> <out-dir>
#
# Example
#   bash deploy/scripts/fetch_docker_packages.sh ubuntu-22.04 ~/docker-debs/ubuntu-22.04
#

set -Eeuo pipefail

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
    C_CYN=$'\033[0;36m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_RST=""
fi
log()  { echo "${C_CYN}[fetch-docker]${C_RST} $*"; }
ok()   { echo "  ${C_GRN}✓${C_RST} $*"; }
warn() { echo "  ${C_YEL}!${C_RST} $*"; }
die()  { echo "  ${C_RED}✗ $*${C_RST}" >&2; exit 1; }

DISTRO="${1:-}"
OUT_DIR="${2:-}"

[[ -n "$DISTRO" && -n "$OUT_DIR" ]] || die "Usage: $0 <distro> <out-dir>"
command -v docker >/dev/null 2>&1 || die "Docker is required on this packaging machine."

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

case "$DISTRO" in
    ubuntu-22.04) IMAGE="ubuntu:22.04";  CODENAME="jammy";    FAMILY="apt-ubuntu" ;;
    ubuntu-24.04) IMAGE="ubuntu:24.04";  CODENAME="noble";    FAMILY="apt-ubuntu" ;;
    debian-12)    IMAGE="debian:12";     CODENAME="bookworm"; FAMILY="apt-debian" ;;
    rhel-8)       IMAGE="rockylinux:8";  CODENAME="";         FAMILY="dnf-rhel";    RHEL_VER="8" ;;
    rhel-9)       IMAGE="rockylinux:9";  CODENAME="";         FAMILY="dnf-rhel";    RHEL_VER="9" ;;
    *) die "Unsupported distro: $DISTRO (valid: ubuntu-22.04|ubuntu-24.04|debian-12|rhel-8|rhel-9)" ;;
esac

log "Target distro : $DISTRO"
log "Helper image  : $IMAGE"
log "Output dir    : $OUT_DIR"
echo ""

# ---------------------------------------------------------------------------
# APT family (Ubuntu / Debian) — uses `apt-get download` to grab .deb files
# ---------------------------------------------------------------------------
if [[ "$FAMILY" == apt-ubuntu || "$FAMILY" == apt-debian ]]; then
    if [[ "$FAMILY" == apt-ubuntu ]]; then
        REPO_URL="https://download.docker.com/linux/ubuntu"
    else
        REPO_URL="https://download.docker.com/linux/debian"
    fi

    log "Downloading Docker .deb packages (this needs internet)..."
    docker run --rm \
        -v "${OUT_DIR}:/out" \
        -e DEBIAN_FRONTEND=noninteractive \
        "$IMAGE" bash -c "
            set -e
            apt-get update -qq
            apt-get install -y -qq curl ca-certificates gnupg apt-transport-https >/dev/null
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL ${REPO_URL}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo 'deb [arch='\$(dpkg --print-architecture)' signed-by=/etc/apt/keyrings/docker.gpg] ${REPO_URL} ${CODENAME} stable' \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq

            cd /out
            # Resolve the full dependency closure for the Docker packages and
            # download every .deb so the air-gapped target can install offline.
            apt-get install --download-only --reinstall --no-install-recommends -y \
                docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null

            # The downloaded .debs land in /var/cache/apt/archives — copy them out.
            cp -v /var/cache/apt/archives/*.deb /out/
        " >/dev/null

    DEB_COUNT=$(find "$OUT_DIR" -maxdepth 1 -name '*.deb' | wc -l)
    [[ $DEB_COUNT -gt 0 ]] || die "No .deb files were downloaded — check internet access on this machine."
    ok "Downloaded ${DEB_COUNT} .deb files to ${OUT_DIR}"

# ---------------------------------------------------------------------------
# DNF family (RHEL/Rocky) — uses `dnf download --resolve` for full dep closure
# ---------------------------------------------------------------------------
elif [[ "$FAMILY" == dnf-rhel ]]; then
    log "Downloading Docker .rpm packages (this needs internet)..."
    docker run --rm \
        -v "${OUT_DIR}:/out" \
        "$IMAGE" bash -c "
            set -e
            dnf -y install dnf-plugins-core >/dev/null
            dnf -y config-manager --add-repo \
                https://download.docker.com/linux/rhel/docker-ce.repo >/dev/null
            cd /out
            # --resolve grabs every transitive dependency too.
            dnf -y download --resolve \
                docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin >/dev/null
        " >/dev/null

    RPM_COUNT=$(find "$OUT_DIR" -maxdepth 1 -name '*.rpm' | wc -l)
    [[ $RPM_COUNT -gt 0 ]] || die "No .rpm files were downloaded — check internet access on this machine."
    ok "Downloaded ${RPM_COUNT} .rpm files to ${OUT_DIR}"
fi

echo ""
log "Done. Pass --docker-debs-dir ${OUT_DIR} to deploy/build_usb_bundle.sh"
log "(or use 'make usb-bundle DOCKER_FOR=${DISTRO}' to do both in one shot)"
