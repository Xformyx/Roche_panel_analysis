#!/usr/bin/env bash
#
# Roche_nxt — 패치 패키지 생성 스크립트 (개발 서버에서 실행)
#
# 용도:
#   최신 Web 이미지를 저장하고, 소스 파일을 패키지로 묶어
#   병원 서버에 전달할 패치 파일을 생성합니다.
#
# 생성 파일:
#   roche_patch_vX.X.X/
#     roche_nxt_web_vX.X.X.tar.gz   — Web Docker 이미지
#     Roche_nxt_vX.X.X.tar.gz       — 소스 파일 (DB·.env 제외)
#     apply_patch.sh                 — 병원 서버 적용 스크립트 (복사본)
#     PATCH_NOTES.md                 — 변경 내용
#
# 사용법:
#   bash deploy/scripts/save_patch.sh [--output-dir <경로>] [--web-only]
#
# 예시:
#   bash deploy/scripts/save_patch.sh
#   bash deploy/scripts/save_patch.sh --output-dir /tmp/patch --web-only
#
set -Eeuo pipefail

# ── 색상 출력 ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'; C_RED=$'\033[0;31m'
    C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_YEL=""; C_RED=""; C_CYN=""; C_BLD=""; C_RST=""
fi
ok()   { echo "${C_GRN}✓${C_RST} $*"; }
info() { echo "${C_CYN}→${C_RST} $*"; }
die()  { echo "${C_RED}✗${C_RST} $*" >&2; exit 1; }
h()    { echo; echo "${C_BLD}${C_CYN}── $* ──────────────────────────────${C_RST}"; }

# ── 인수 파싱 ────────────────────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR=""
WEB_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --web-only)   WEB_ONLY=true; shift ;;
        -h|--help)
            echo "Usage: $0 [--output-dir <path>] [--web-only]"
            echo "  --web-only   Web 이미지만 포함 (분석 이미지 생략, 패치용)"
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── 버전 읽기 ────────────────────────────────────────────────────────────────
VERSION=$(python3 -c "import json; print(json.load(open('$REPO_DIR/web_ui/version.json'))['version'])" 2>/dev/null || echo "unknown")
PATCH_NAME="roche_patch_v${VERSION}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_DIR/deploy/patches/$PATCH_NAME}"

echo
echo "${C_BLD}Roche_nxt — 패치 패키지 생성 v${VERSION}${C_RST}"
echo "  소스 디렉터리  : $REPO_DIR"
echo "  출력 디렉터리  : $OUTPUT_DIR"
echo "  Web 이미지만   : $WEB_ONLY"
echo

# ── 이미지 존재 확인 ─────────────────────────────────────────────────────────
h "이미지 확인"
docker image inspect roche_nxt_web:latest &>/dev/null     || die "roche_nxt_web:latest 이미지가 없습니다. 먼저 빌드하세요."
if [[ "$WEB_ONLY" == false ]]; then
    docker image inspect roche_nxt_analysis:latest &>/dev/null || die "roche_nxt_analysis:latest 이미지가 없습니다."
fi
ok "이미지 확인 완료"

# ── 출력 디렉터리 준비 ───────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"

# ── Web 이미지 저장 ──────────────────────────────────────────────────────────
h "Web 이미지 저장"
WEB_IMAGE_FILE="$OUTPUT_DIR/roche_nxt_web_v${VERSION}.tar.gz"
info "저장 중: roche_nxt_web:latest → $(basename $WEB_IMAGE_FILE)"
docker save roche_nxt_web:latest | gzip > "$WEB_IMAGE_FILE"
ok "Web 이미지: $(du -sh $WEB_IMAGE_FILE | cut -f1)"

# ── Analysis 이미지 저장 (선택) ──────────────────────────────────────────────
if [[ "$WEB_ONLY" == false ]]; then
    h "Analysis 이미지 저장"
    ANALYSIS_IMAGE_FILE="$OUTPUT_DIR/roche_nxt_analysis_v${VERSION}.tar.gz"
    info "저장 중: roche_nxt_analysis:latest → $(basename $ANALYSIS_IMAGE_FILE) (수분 소요)"
    docker save roche_nxt_analysis:latest | gzip > "$ANALYSIS_IMAGE_FILE"
    ok "Analysis 이미지: $(du -sh $ANALYSIS_IMAGE_FILE | cut -f1)"
fi

# ── 소스 파일 패키징 ─────────────────────────────────────────────────────────
h "소스 파일 패키징"
SOURCE_TAR="$OUTPUT_DIR/Roche_nxt_v${VERSION}.tar.gz"
info "소스 패키징 중 (DB·.env·large files 제외)..."

tar -czf "$SOURCE_TAR" \
    -C "$(dirname $REPO_DIR)" \
    --exclude="$(basename $REPO_DIR)/web_ui/orders.db" \
    --exclude="$(basename $REPO_DIR)/web_ui/*.db" \
    --exclude="$(basename $REPO_DIR)/.env" \
    --exclude="$(basename $REPO_DIR)/log" \
    --exclude="$(basename $REPO_DIR)/results" \
    --exclude="$(basename $REPO_DIR)/work" \
    --exclude="$(basename $REPO_DIR)/data" \
    --exclude="$(basename $REPO_DIR)/fastq" \
    --exclude="$(basename $REPO_DIR)/.git" \
    --exclude="$(basename $REPO_DIR)/deploy/patches" \
    --exclude="$(basename $REPO_DIR)/deploy/images" \
    --exclude="$(basename $REPO_DIR)/deploy/*.tar" \
    --exclude="$(basename $REPO_DIR)/deploy/*.tar.gz" \
    --exclude="$(basename $REPO_DIR)/backup" \
    --exclude="$(basename $REPO_DIR)/deploy/usb" \
    --exclude="$(basename $REPO_DIR)/deploy/snuh_usb" \
    "$(basename $REPO_DIR)"

ok "소스 패키지: $(du -sh $SOURCE_TAR | cut -f1)"

# ── apply_patch.sh 복사 ──────────────────────────────────────────────────────
cp "$REPO_DIR/deploy/scripts/upgrade_from_image.sh" "$OUTPUT_DIR/apply_patch.sh"
cp "$REPO_DIR/deploy/scripts/apply_full_patch.sh"  "$OUTPUT_DIR/apply_full_patch.sh"
chmod +x "$OUTPUT_DIR/apply_patch.sh" "$OUTPUT_DIR/apply_full_patch.sh"
ok "apply_patch.sh, apply_full_patch.sh 복사 완료"

# ── PATCH_NOTES.md 생성 ──────────────────────────────────────────────────────
cat > "$OUTPUT_DIR/PATCH_NOTES.md" << NOTES
# Roche_nxt 패치 v${VERSION}

생성 일시: $(date '+%Y-%m-%d %H:%M:%S')

## 적용 방법

### 1. 이 디렉터리를 병원 서버로 전송

\`\`\`bash
scp -r $(basename $OUTPUT_DIR)/ user@hospital-server:/tmp/
\`\`\`

### 2. 병원 서버에서 패치 적용

\`\`\`bash
cd /tmp/$(basename $OUTPUT_DIR)

# 설치 경로 자동 탐색 + 적용
bash apply_patch.sh

# 또는 설치 경로 직접 지정
bash apply_patch.sh --install-dir /opt/roche_nxt
\`\`\`

### 3. 확인

웹 브라우저에서 접속 후 사이드바 하단 \`Ver.${VERSION}\` 표시 확인.

## 파일 목록

$(ls -lh "$OUTPUT_DIR/" | awk 'NR>1 {print "- "$NF": "$5}')

## 변경 내용

자세한 변경 내용은 [PATCH_v1.3.md](https://github.com/Xformyx/Roche_panel_analysis/blob/main/deploy/PATCH_v1.3.md) 참조.
NOTES

ok "PATCH_NOTES.md 생성 완료"

# ── 최종 요약 ────────────────────────────────────────────────────────────────
h "생성 완료"
echo
du -sh "$OUTPUT_DIR"
echo
ls -lh "$OUTPUT_DIR/"
echo
echo "${C_BLD}전달 방법:${C_RST}"
echo "  # SCP로 병원 서버에 전송"
echo "  scp -r $OUTPUT_DIR user@hospital-server:/tmp/"
echo
echo "  # 또는 tar로 묶어서 전송"
echo "  tar -czf $(basename $OUTPUT_DIR).tar.gz -C $(dirname $OUTPUT_DIR) $(basename $OUTPUT_DIR)"
echo
echo "${C_BLD}병원 서버 적용 명령:${C_RST}"
echo "  bash /tmp/$(basename $OUTPUT_DIR)/apply_patch.sh --install-dir /opt/roche_nxt"
echo
