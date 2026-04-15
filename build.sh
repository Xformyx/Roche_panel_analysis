#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    echo ""
    echo "Roche_nxt Docker Build Script"
    echo "=============================="
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  all          Build analysis + web images (default)"
    echo "  analysis     Build analysis image only"
    echo "  web          Build web UI image only"
    echo "  save         Save images as tar.gz for offline deployment"
    echo "  load         Load saved images from tar.gz"
    echo "  status       Show current image status"
    echo "  clean        Remove all roche_nxt images"
    echo ""
    echo "Options:"
    echo "  --no-cache   Build without Docker cache"
    echo "  --help       Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build all images"
    echo "  $0 analysis           # Build analysis image only"
    echo "  $0 all --no-cache     # Full rebuild without cache"
    echo "  $0 save               # Save images for offline deployment"
    echo "  $0 load               # Load images on offline server"
    echo ""
}

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

ANALYSIS_IMAGE="roche_nxt_analysis:latest"
WEB_IMAGE="roche_nxt_web:latest"
CACHE_FLAG=""

# Parse --no-cache from any position
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --no-cache) CACHE_FLAG="--no-cache" ;;
        --help|-h)  usage; exit 0 ;;
        *)          ARGS+=("$arg") ;;
    esac
done
COMMAND="${ARGS[0]:-all}"

# ── Build functions ──────────────────────────────────────

build_analysis() {
    echo ""
    echo "============================================"
    log_info "Building analysis image: ${ANALYSIS_IMAGE}"
    echo "============================================"
    echo ""

    if [ ! -f containers/Dockerfile.all ]; then
        log_error "containers/Dockerfile.all not found!"
        exit 1
    fi

    local start_time=$SECONDS

    docker build \
        ${CACHE_FLAG} \
        -t ${ANALYSIS_IMAGE} \
        -f containers/Dockerfile.all \
        .

    local elapsed=$(( SECONDS - start_time ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    if docker image inspect ${ANALYSIS_IMAGE} &>/dev/null; then
        local size=$(docker image inspect ${ANALYSIS_IMAGE} --format='{{.Size}}' | awk '{printf "%.1f GB", $1/1024/1024/1024}')
        echo ""
        log_ok "Analysis image built: ${ANALYSIS_IMAGE} (${size})"
        log_ok "Build time: ${mins}m ${secs}s"
    else
        log_error "Failed to build analysis image!"
        exit 1
    fi
}

build_web() {
    echo ""
    echo "============================================"
    log_info "Building web UI image: ${WEB_IMAGE}"
    echo "============================================"
    echo ""

    if [ ! -f web_ui/Dockerfile ]; then
        log_error "web_ui/Dockerfile not found!"
        exit 1
    fi

    local start_time=$SECONDS

    docker build \
        ${CACHE_FLAG} \
        -t ${WEB_IMAGE} \
        -f web_ui/Dockerfile \
        web_ui/

    local elapsed=$(( SECONDS - start_time ))

    if docker image inspect ${WEB_IMAGE} &>/dev/null; then
        local size=$(docker image inspect ${WEB_IMAGE} --format='{{.Size}}' | awk '{printf "%.0f MB", $1/1024/1024}')
        echo ""
        log_ok "Web UI image built: ${WEB_IMAGE} (${size})"
        log_ok "Build time: ${elapsed}s"
    else
        log_error "Failed to build web image!"
        exit 1
    fi
}

save_images() {
    echo ""
    echo "============================================"
    log_info "Saving Docker images for offline deployment"
    echo "============================================"
    echo ""

    mkdir -p deploy/images

    if docker image inspect ${ANALYSIS_IMAGE} &>/dev/null; then
        log_info "Saving ${ANALYSIS_IMAGE}..."
        docker save ${ANALYSIS_IMAGE} | gzip > deploy/images/roche_nxt_analysis.tar.gz
        local size=$(ls -lh deploy/images/roche_nxt_analysis.tar.gz | awk '{print $5}')
        log_ok "  -> deploy/images/roche_nxt_analysis.tar.gz (${size})"
    else
        log_warn "Analysis image not found. Build it first: $0 analysis"
    fi

    if docker image inspect ${WEB_IMAGE} &>/dev/null; then
        log_info "Saving ${WEB_IMAGE}..."
        docker save ${WEB_IMAGE} | gzip > deploy/images/roche_nxt_web.tar.gz
        local size=$(ls -lh deploy/images/roche_nxt_web.tar.gz | awk '{print $5}')
        log_ok "  -> deploy/images/roche_nxt_web.tar.gz (${size})"
    else
        log_warn "Web image not found. Build it first: $0 web"
    fi

    echo ""
    log_info "Saved images:"
    ls -lh deploy/images/ 2>/dev/null || echo "  (none)"
    echo ""
    log_info "To deploy on an offline server:"
    echo "  1. Copy Roche_nxt/ directory to target server"
    echo "  2. Copy roche_data/ directory (reference data)"
    echo "  3. Run: bash build.sh load"
    echo "  4. Run: bash deploy/install.sh"
}

load_images() {
    echo ""
    echo "============================================"
    log_info "Loading Docker images from saved files"
    echo "============================================"
    echo ""

    if [ -f deploy/images/roche_nxt_analysis.tar.gz ]; then
        log_info "Loading analysis image..."
        docker load < deploy/images/roche_nxt_analysis.tar.gz
        log_ok "Analysis image loaded."
    else
        log_warn "deploy/images/roche_nxt_analysis.tar.gz not found!"
    fi

    if [ -f deploy/images/roche_nxt_web.tar.gz ]; then
        log_info "Loading web UI image..."
        docker load < deploy/images/roche_nxt_web.tar.gz
        log_ok "Web UI image loaded."
    else
        log_warn "deploy/images/roche_nxt_web.tar.gz not found!"
    fi

    echo ""
    show_status
}

show_status() {
    echo ""
    echo "============================================"
    log_info "Docker Image Status"
    echo "============================================"
    echo ""

    echo "  Images:"
    if docker image inspect ${ANALYSIS_IMAGE} &>/dev/null; then
        local a_size=$(docker image inspect ${ANALYSIS_IMAGE} --format='{{.Size}}' | awk '{printf "%.1f GB", $1/1024/1024/1024}')
        local a_created=$(docker image inspect ${ANALYSIS_IMAGE} --format='{{.Created}}' | cut -d'T' -f1)
        log_ok "  ${ANALYSIS_IMAGE}  (${a_size}, built ${a_created})"
    else
        log_warn "  ${ANALYSIS_IMAGE}  (not built)"
    fi

    if docker image inspect ${WEB_IMAGE} &>/dev/null; then
        local w_size=$(docker image inspect ${WEB_IMAGE} --format='{{.Size}}' | awk '{printf "%.0f MB", $1/1024/1024}')
        local w_created=$(docker image inspect ${WEB_IMAGE} --format='{{.Created}}' | cut -d'T' -f1)
        log_ok "  ${WEB_IMAGE}       (${w_size}, built ${w_created})"
    else
        log_warn "  ${WEB_IMAGE}       (not built)"
    fi

    echo ""
    echo "  Saved images:"
    if [ -d deploy/images ]; then
        ls -lh deploy/images/*.tar.gz 2>/dev/null | awk '{print "    " $NF " (" $5 ")"}' || echo "    (none)"
    else
        echo "    (none)"
    fi

    echo ""
    echo "  Containers:"
    docker ps -a --filter "name=roche_nxt" --format "    {{.Names}}  {{.Status}}" 2>/dev/null || echo "    (none)"
    echo ""
}

clean_images() {
    echo ""
    log_info "Removing roche_nxt Docker images..."

    docker-compose down 2>/dev/null || true
    docker rmi ${ANALYSIS_IMAGE} 2>/dev/null && log_ok "Removed ${ANALYSIS_IMAGE}" || log_warn "${ANALYSIS_IMAGE} not found"
    docker rmi ${WEB_IMAGE} 2>/dev/null && log_ok "Removed ${WEB_IMAGE}" || log_warn "${WEB_IMAGE} not found"

    echo ""
    log_ok "Clean complete."
}

# ── Main ─────────────────────────────────────────────────

case "$COMMAND" in
    all)
        build_analysis
        build_web
        echo ""
        echo "============================================"
        log_ok "All images built successfully!"
        echo "============================================"
        echo ""
        echo "Next steps:"
        echo "  make up                  # Start Web UI (http://localhost:8080)"
        echo "  bash build.sh save       # Save for offline deployment"
        echo "  nextflow run main.nf ... # Run pipeline directly"
        echo ""
        ;;
    analysis)
        build_analysis
        ;;
    web)
        build_web
        ;;
    save)
        save_images
        ;;
    load)
        load_images
        ;;
    status)
        show_status
        ;;
    clean)
        clean_images
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
