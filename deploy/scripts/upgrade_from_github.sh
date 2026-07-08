#!/usr/bin/env bash
#
# Roche_nxt — GitHub 소스 기반 업그레이드 스크립트
#
# 용도:
#   병원 서버에서 GitHub에 직접 접근 가능한 경우 사용.
#   최신 버전을 받아 Web 이미지를 재빌드하고 서비스를 재시작합니다.
#   레퍼런스 데이터와 분석 이미지는 변경하지 않습니다.
#
# 사용법:
#   bash upgrade_from_github.sh [--install-dir <경로>] [--tag <v1.x.x>]
#
# 예시:
#   bash upgrade_from_github.sh --install-dir /opt/roche_nxt --tag v1.3.0
#   bash upgrade_from_github.sh --install-dir /opt/roche_nxt   # main 최신 버전
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

resolve_compose_file() {
    local dir="$1"
    if [[ -f "$dir/docker-compose.prod.yml" ]]; then
        echo "docker-compose.prod.yml"
    elif [[ -f "$dir/docker-compose.yml" ]]; then
        echo "docker-compose.yml"
    else
        return 1
    fi
}

has_compose_file() {
    [[ -f "$1/docker-compose.prod.yml" || -f "$1/docker-compose.yml" ]]
}

# ── 인수 파싱 ────────────────────────────────────────────────────────────────
INSTALL_DIR=""
TARGET_TAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --tag)         TARGET_TAG="$2";  shift 2 ;;
        -h|--help)
            echo "Usage: $0 --install-dir <path> [--tag <v1.x.x>]"
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# 설치 디렉터리 자동 탐색
if [[ -z "$INSTALL_DIR" ]]; then
    for d in /opt/roche_nxt /home/*/roche_nxt /opt/roche*; do
        if has_compose_file "$d"; then
            INSTALL_DIR="$d"
            break
        fi
    done
fi

[[ -z "$INSTALL_DIR" ]] && die "--install-dir 를 지정하거나 /opt/roche_nxt 에 설치하세요."
COMPOSE_FILE="$(resolve_compose_file "$INSTALL_DIR")" \
    || die "$INSTALL_DIR 에 docker-compose.prod.yml 또는 docker-compose.yml 이 없습니다."

cd "$INSTALL_DIR"

# ── 현재 버전 확인 ───────────────────────────────────────────────────────────
CURRENT_VER="unknown"
if [[ -f "$INSTALL_DIR/web_ui/version.json" ]]; then
    CURRENT_VER=$(python3 -c "import json; print(json.load(open('web_ui/version.json'))['version'])" 2>/dev/null || echo "unknown")
fi

echo
echo "${C_BLD}Roche_nxt — GitHub 업그레이드${C_RST}"
echo "  설치 디렉터리 : $INSTALL_DIR"
echo "  현재 버전     : $CURRENT_VER"
echo "  목표 버전     : ${TARGET_TAG:-main 최신}"
echo

# ── Preflight ────────────────────────────────────────────────────────────────
h "Preflight"

# git 확인
git rev-parse --is-inside-work-tree &>/dev/null || die "$INSTALL_DIR 는 git 저장소가 아닙니다."
ok "Git 저장소 확인"

# GitHub 연결 확인
if ! git ls-remote --exit-code origin &>/dev/null; then
    die "GitHub 원격 저장소에 연결할 수 없습니다. 인터넷 연결을 확인하세요."
fi
ok "GitHub 연결 확인"

# 실행 중인 분석 확인
RUNNING=$(docker ps --filter "name=nxt_" --format "{{.Names}}" 2>/dev/null | wc -l)
if [[ "$RUNNING" -gt 0 ]]; then
    warn "현재 실행 중인 분석 컨테이너가 ${RUNNING}개 있습니다:"
    docker ps --filter "name=nxt_" --format "  {{.Names}} ({{.Status}})"
    warn "분석이 완료될 때까지 기다린 후 업그레이드하는 것을 권장합니다."
    read -r -p "  계속 진행하시겠습니까? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "업그레이드를 취소했습니다."; exit 0; }
fi

# ── DB·설정 백업 ─────────────────────────────────────────────────────────────
h "중요 파일 백업"

BACKUP_DIR="$INSTALL_DIR/backup/$(date +%Y%m%d_%H%M%S)"
if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        BACKUP_DIR="/tmp/roche_nxt_backup_$(date +%Y%m%d_%H%M%S)_$$"
        mkdir -p "$BACKUP_DIR" || die "백업 디렉터리를 만들 수 없습니다: $INSTALL_DIR/backup (permission denied)"
        warn "설치 디렉터리에 쓸 수 없어 임시 백업 사용: $BACKUP_DIR"
    else
        warn "설치 디렉터리에 쓸 수 없어 형제 backup 사용: $BACKUP_DIR"
    fi
fi

for f in "web_ui/orders.db" "web_ui/app.py" ".env" "nextflow.config"; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        cp "$INSTALL_DIR/$f" "$BACKUP_DIR/$(basename $f)"
        ok "백업: $f → $BACKUP_DIR/"
    fi
done

# ── 소스 업데이트 ────────────────────────────────────────────────────────────
h "GitHub에서 소스 업데이트"

git fetch origin
if [[ -n "$TARGET_TAG" ]]; then
    git checkout "$TARGET_TAG"
    ok "버전 전환: $TARGET_TAG"
else
    git pull origin main
    ok "main 최신 버전으로 업데이트"
fi

NEW_VER=$(python3 -c "import json; print(json.load(open('web_ui/version.json'))['version'])" 2>/dev/null || echo "unknown")
info "새 버전: $NEW_VER"

# ── DB 마이그레이션 주의 ─────────────────────────────────────────────────────
if [[ -f "$BACKUP_DIR/orders.db" ]]; then
    info "DB 마이그레이션은 web 컨테이너 시작 시 자동으로 수행됩니다."
fi

# ── Web 이미지 재빌드 ────────────────────────────────────────────────────────
h "Web 이미지 재빌드"

info "roche_nxt_web:latest 빌드 중 (~2분)..."
docker build -f web_ui/Dockerfile web_ui/ -t roche_nxt_web:latest
ok "이미지 빌드 완료"

# ── 서비스 재시작 ────────────────────────────────────────────────────────────
h "서비스 재시작"

docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate roche-nxt-web
ok "Web 서비스 재시작 완료"

# ── 확인 ─────────────────────────────────────────────────────────────────────
h "기동 확인"

info "서비스 안정화 대기 (10초)..."
sleep 10

if docker ps | grep -q roche_nxt_web; then
    ok "roche_nxt_web 컨테이너 실행 중"
else
    die "컨테이너가 기동되지 않았습니다. docker logs roche_nxt_web 으로 확인하세요."
fi

# 버전 확인 (HTTP)
WEB_PORT=$(grep WEB_PORT .env 2>/dev/null | cut -d= -f2 | tr -d ' ' || echo "8080")
if curl -sf "http://localhost:${WEB_PORT}/api/version" &>/dev/null; then
    ok "웹 서비스 응답 확인 (port ${WEB_PORT})"
else
    warn "웹 응답 확인 실패. 수동으로 http://<서버IP>:${WEB_PORT} 접속해보세요."
fi

echo
echo "${C_BLD}${C_GRN}업그레이드 완료!${C_RST}"
echo "  이전 버전 : $CURRENT_VER"
echo "  현재 버전 : $NEW_VER"
echo "  백업 위치 : $BACKUP_DIR"
echo "  접속 URL  : http://<서버IP>:${WEB_PORT}"
echo
