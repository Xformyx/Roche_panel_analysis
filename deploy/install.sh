#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_DIR="${SCRIPT_DIR}/images"
ENV_FILE="${PROJECT_DIR}/.env"

echo "============================================"
echo "Roche Panel Analysis - Installation"
echo "============================================"
echo ""

# Check Docker
if ! command -v docker &>/dev/null; then
    echo "ERROR: Docker is not installed."
    echo "  sudo apt-get install docker-ce docker-ce-cli containerd.io"
    exit 1
fi

if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    echo "ERROR: Docker Compose is not installed."
    exit 1
fi

# 1. Load Docker images
echo "[1/6] Loading Docker images..."
if [ -f "$IMAGE_DIR/roche_nxt_analysis.tar.gz" ]; then
    echo "  Loading roche_nxt_analysis..."
    docker load < "$IMAGE_DIR/roche_nxt_analysis.tar.gz"
else
    echo "  WARNING: $IMAGE_DIR/roche_nxt_analysis.tar.gz not found!"
fi

if [ -f "$IMAGE_DIR/roche_nxt_web.tar.gz" ]; then
    echo "  Loading roche_nxt_web..."
    docker load < "$IMAGE_DIR/roche_nxt_web.tar.gz"
else
    echo "  WARNING: $IMAGE_DIR/roche_nxt_web.tar.gz not found!"
fi

# 2. Install Nextflow (offline - copy from bundle or download)
echo ""
echo "[2/6] Setting up Nextflow..."
NF_BIN="${PROJECT_DIR}/bin/nextflow"
if [ -f "$NF_BIN" ]; then
    echo "  Nextflow binary found at $NF_BIN"
    chmod +x "$NF_BIN"
else
    echo "  Nextflow not found at $NF_BIN"
    echo "  For offline installation, place the nextflow binary in ${PROJECT_DIR}/bin/"
    echo "  For online installation: curl -s https://get.nextflow.io | bash && mv nextflow ${PROJECT_DIR}/bin/"
fi

# 3. Configure environment
echo ""
echo "[3/6] Configuring environment..."
HOST_DIR="$PROJECT_DIR"
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
DOCKER_GID=$(getent group docker 2>/dev/null | cut -d: -f3 || echo "113")

if [ -f "$ENV_FILE" ]; then
    echo "  .env file exists, updating..."
    sed -i "s|^HOST_DIR=.*|HOST_DIR=${HOST_DIR}|" "$ENV_FILE"
    sed -i "s|^UID=.*|UID=${CURRENT_UID}|" "$ENV_FILE"
    sed -i "s|^GID=.*|GID=${CURRENT_GID}|" "$ENV_FILE"
else
    echo "  Creating .env file from template..."
    if [ -f "${PROJECT_DIR}/.env.example" ]; then
        cp "${PROJECT_DIR}/.env.example" "$ENV_FILE"
        sed -i "s|^HOST_DIR=.*|HOST_DIR=${HOST_DIR}|" "$ENV_FILE"
        sed -i "s|^UID=.*|UID=${CURRENT_UID}|" "$ENV_FILE"
        sed -i "s|^GID=.*|GID=${CURRENT_GID}|" "$ENV_FILE"
    else
        cat > "$ENV_FILE" << ENVEOF
HOST_DIR=${HOST_DIR}
FASTQ_HOST_DIR=${HOST_DIR}/fastq
BED_HOST_DIR=${HOST_DIR}/data/bed/hg38
WEB_PORT=8080
UID=${CURRENT_UID}
GID=${CURRENT_GID}
DOCKER_GID=${DOCKER_GID}
TZ=Asia/Seoul
ENABLE_LONGITUDINAL=true
MAX_CPUS=0
MAX_MEMORY=0
MAX_CONCURRENT_SAMPLES=0
ENVEOF
    fi
fi

echo "  HOST_DIR = $HOST_DIR"
echo "  UID/GID  = $CURRENT_UID:$CURRENT_GID"

# 4. Create directories
echo ""
echo "[4/6] Creating directories..."
mkdir -p "$PROJECT_DIR/fastq"
mkdir -p "$PROJECT_DIR/results"
mkdir -p "$PROJECT_DIR/log"
mkdir -p "$PROJECT_DIR/work"

# 5. Check data symlink
echo ""
echo "[5/6] Checking reference data..."
if [ -L "$PROJECT_DIR/data" ]; then
    if [ -d "$PROJECT_DIR/data" ]; then
        echo "  Data symlink OK: $PROJECT_DIR/data -> $(readlink "$PROJECT_DIR/data")"
    else
        echo "  WARNING: Data symlink broken! Please set up roche_data/ directory"
        echo "  Expected: $PROJECT_DIR/data -> ../roche_data"
    fi
elif [ -d "$PROJECT_DIR/data" ]; then
    echo "  Data directory exists (not a symlink)"
else
    echo "  WARNING: No data directory found!"
    echo "  Please create a symlink: ln -s /path/to/roche_data $PROJECT_DIR/data"
fi

# 6. Start Web UI
echo ""
echo "[6/6] Starting Web UI..."
cd "$PROJECT_DIR"
docker-compose up -d

echo ""
echo "============================================"
echo "Installation complete!"
echo "============================================"
echo ""
echo "Web UI:  http://localhost:$(grep WEB_PORT "$ENV_FILE" 2>/dev/null | cut -d= -f2 || echo 8080)"
echo ""
echo "CLI usage:"
echo "  cd $HOST_DIR"
echo "  ./bin/nextflow run main.nf -profile docker --input samplesheet.csv"
echo ""
echo "Commands:"
echo "  docker-compose up -d    # Start Web UI"
echo "  docker-compose down     # Stop Web UI"
echo "  docker-compose logs -f  # View logs"
echo ""
