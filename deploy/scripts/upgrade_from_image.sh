#!/usr/bin/env bash
#
# Roche_nxt — Docker 이미지 기반 업그레이드 스크립트 (병원 서버에서 실행)
#
# 용도:
#   개발자로부터 전달받은 이미지 파일(.tar.gz)과 소스 파일로
#   기존 설치를 업그레이드합니다.
#   GitHub 접속이 불가한 환경(오프라인 패치)에서 사용합니다.
#
# 사용법:
#   bash upgrade_from_image.sh [--install-dir <경로>] [--patch-dir <경로>]
#
# 예시:
#   # 패치 파일과 같은 디렉터리에서 실행 (자동 탐색)
#   bash apply_patch.sh
#
#   # 명시적으로 경로 지정
#   bash upgrade_from_image.sh \
#       --install-dir /opt/roche_nxt \
#       --patch-dir /tmp/roche_patch_v1.3.0
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
warn() { echo "${C_YEL}⚠${C_RST} $*"; }
die()  { echo "${C_RED}✗${C_RST} $*" >&2; exit 1; }
h()    { echo; echo "${C_BLD}${C_CYN}── $* ──────────────────────────────${C_RST}"; }

# ── 인수 파싱 ────────────────────────────────────────────────────────────────
INSTALL_DIR=""
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # 스크립트 위치 = 패치 디렉터리

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --patch-dir)   PATCH_DIR="$2";   shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--install-dir <path>] [--patch-dir <path>]"
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── 설치 디렉터리 자동 탐색 ──────────────────────────────────────────────────
if [[ -z "$INSTALL_DIR" ]]; then
    for d in /opt/roche_nxt /opt/roche_bsch /opt/roche_eone /home/*/roche_nxt; do
        if [[ -f "$d/docker-compose.prod.yml" ]]; then
            INSTALL_DIR="$d"
            break
        fi
    done
    # docker inspect로 탐색 (위에서 못찾은 경우)
    if [[ -z "$INSTALL_DIR" ]] && docker ps -q --filter "name=roche_nxt_web" | grep -q .; then
        INSTALL_DIR=$(docker inspect roche_nxt_web \
            --format '{{range .Mounts}}{{if eq .Destination "/roche_nxt"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    fi
fi

[[ -z "$INSTALL_DIR" ]] && die "--install-dir 를 지정하세요. 예: --install-dir /opt/roche_nxt"
[[ -f "$INSTALL_DIR/docker-compose.prod.yml" ]] || die "$INSTALL_DIR 에 docker-compose.prod.yml 이 없습니다."

# ── 패치 파일 탐색 ───────────────────────────────────────────────────────────
find_image() {
    local pattern="$1"
    find "$PATCH_DIR" -maxdepth 1 -name "$pattern" 2>/dev/null | sort -V | tail -1
}

WEB_IMAGE=$(find_image "roche_nxt_web_*.tar.gz")
ANALYSIS_IMAGE=$(find_image "roche_nxt_analysis_*.tar.gz")
SOURCE_TAR=$(find_image "Roche_nxt_*.tar.gz")

# ── 현재 버전 확인 ───────────────────────────────────────────────────────────
CURRENT_VER="unknown"
if [[ -f "$INSTALL_DIR/web_ui/version.json" ]]; then
    CURRENT_VER=$(python3 -c "import json; print(json.load(open('$INSTALL_DIR/web_ui/version.json'))['version'])" 2>/dev/null || echo "unknown")
fi

NEW_VER="unknown"
if [[ -n "$SOURCE_TAR" ]]; then
    NEW_VER=$(basename "$SOURCE_TAR" | sed 's/Roche_nxt_v//;s/.tar.gz//')
elif [[ -n "$WEB_IMAGE" ]]; then
    NEW_VER=$(basename "$WEB_IMAGE" | sed 's/roche_nxt_web_v//;s/.tar.gz//')
fi

echo
echo "${C_BLD}Roche_nxt — 이미지 기반 업그레이드${C_RST}"
echo "  설치 디렉터리  : $INSTALL_DIR"
echo "  패치 디렉터리  : $PATCH_DIR"
echo "  현재 버전      : $CURRENT_VER"
echo "  새 버전        : $NEW_VER"
echo
echo "  발견된 파일:"
[[ -n "$WEB_IMAGE"      ]] && echo "    Web 이미지     : $(basename $WEB_IMAGE)"   || echo "    Web 이미지     : (없음)"
[[ -n "$ANALYSIS_IMAGE" ]] && echo "    Analysis 이미지: $(basename $ANALYSIS_IMAGE)" || echo "    Analysis 이미지: (없음 — 기존 유지)"
[[ -n "$SOURCE_TAR"     ]] && echo "    소스 파일      : $(basename $SOURCE_TAR)"  || echo "    소스 파일      : (없음 — 이미지만 교체)"
echo

[[ -z "$WEB_IMAGE" ]] && die "Web 이미지 파일(roche_nxt_web_*.tar.gz)을 찾을 수 없습니다. --patch-dir 를 확인하세요."

# ── 실행 중인 분석 확인 ──────────────────────────────────────────────────────
h "Preflight"

RUNNING=$(docker ps --filter "name=nxt_" --format "{{.Names}}" 2>/dev/null | wc -l)
if [[ "$RUNNING" -gt 0 ]]; then
    warn "현재 실행 중인 분석 컨테이너가 ${RUNNING}개 있습니다:"
    docker ps --filter "name=nxt_" --format "  {{.Names}} ({{.Status}})"
    warn "분석이 완료될 때까지 기다린 후 업그레이드하는 것을 권장합니다."
    read -r -p "  계속 진행하시겠습니까? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "업그레이드를 취소했습니다."; exit 0; }
fi
ok "Preflight 완료"

# ── 중요 파일 백업 ───────────────────────────────────────────────────────────
h "중요 파일 백업"

BACKUP_DIR="$INSTALL_DIR/backup/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

for f in "web_ui/orders.db" "web_ui/app.py" ".env" "nextflow.config"; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        cp "$INSTALL_DIR/$f" "$BACKUP_DIR/$(basename $f)"
        ok "백업: $f"
    fi
done

# ── 소스 파일 업데이트 ───────────────────────────────────────────────────────
if [[ -n "$SOURCE_TAR" ]]; then
    h "소스 파일 업데이트"
    info "소스 파일 교체 중 (DB·.env 보존)..."
    tar -xzf "$SOURCE_TAR" \
        -C "$(dirname $INSTALL_DIR)" \
        --strip-components=1 \
        --exclude='web_ui/orders.db' \
        --exclude='web_ui/*.db' \
        --exclude='.env' \
        --exclude='log' \
        --exclude='results' \
        --exclude='work'
    ok "소스 파일 업데이트 완료"
else
    warn "소스 파일 없음 — Docker 이미지만 교체합니다."
fi

# ── Docker 이미지 로드 ───────────────────────────────────────────────────────
h "Docker 이미지 로드"

info "Web 이미지 로드 중: $(basename $WEB_IMAGE)"
docker load < "$WEB_IMAGE"
ok "Web 이미지 로드 완료"

if [[ -n "$ANALYSIS_IMAGE" ]]; then
    info "Analysis 이미지 로드 중: $(basename $ANALYSIS_IMAGE) (수분 소요)"
    docker load < "$ANALYSIS_IMAGE"
    ok "Analysis 이미지 로드 완료"
else
    info "Analysis 이미지: 기존 이미지 유지 (교체 불필요)"
fi

# ── 서비스 재시작 ────────────────────────────────────────────────────────────
h "서비스 재시작"

cd "$INSTALL_DIR"

docker compose -f docker-compose.prod.yml up -d --no-deps --force-recreate roche-nxt-web
ok "Web 서비스 재시작 완료"

# ── 확인 ─────────────────────────────────────────────────────────────────────
h "기동 확인"

info "안정화 대기 (10초)..."
sleep 10

if docker ps | grep -q roche_nxt_web; then
    ok "roche_nxt_web 컨테이너 실행 중"
else
    die "컨테이너가 기동되지 않았습니다. docker logs roche_nxt_web 으로 확인하세요."
fi

WEB_PORT=$(grep WEB_PORT .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "8080")
if curl -sf "http://localhost:${WEB_PORT}/api/version" &>/dev/null; then
    RUNNING_VER=$(curl -s "http://localhost:${WEB_PORT}/api/version" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
    ok "웹 서비스 응답 확인 — 실행 중 버전: $RUNNING_VER"
else
    warn "웹 응답 확인 실패. 수동으로 http://<서버IP>:${WEB_PORT} 접속해보세요."
fi

echo
echo "${C_BLD}${C_GRN}업그레이드 완료!${C_RST}"
echo "  이전 버전 : $CURRENT_VER"
echo "  새 버전   : $NEW_VER"
echo "  백업 위치 : $BACKUP_DIR"
echo "  접속 URL  : http://<서버IP>:${WEB_PORT}"
echo
echo "  ※ 웹 UI 사이드바 하단에서 Ver.${NEW_VER} 확인"
echo
