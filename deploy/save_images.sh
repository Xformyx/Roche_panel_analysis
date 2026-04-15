#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/images"

echo "============================================"
echo "Roche_nxt - Save Docker Images for Offline"
echo "============================================"

mkdir -p "$OUTPUT_DIR"

echo "[1/2] Saving roche_nxt_analysis:latest..."
docker save roche_nxt_analysis:latest | gzip > "$OUTPUT_DIR/roche_nxt_analysis.tar.gz"
echo "  -> $(ls -lh "$OUTPUT_DIR/roche_nxt_analysis.tar.gz" | awk '{print $5}')"

echo "[2/2] Saving roche_nxt_web:latest..."
docker save roche_nxt_web:latest | gzip > "$OUTPUT_DIR/roche_nxt_web.tar.gz"
echo "  -> $(ls -lh "$OUTPUT_DIR/roche_nxt_web.tar.gz" | awk '{print $5}')"

echo ""
echo "Done! Files saved to: $OUTPUT_DIR/"
ls -lh "$OUTPUT_DIR/"
echo ""
echo "To deploy on an offline server:"
echo "  1. Copy the entire Roche_nxt/ directory"
echo "  2. Copy roche_data/ directory (reference data)"
echo "  3. Run: bash deploy/install.sh"
