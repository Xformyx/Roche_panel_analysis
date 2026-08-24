#!/usr/bin/env bash
#
# Roche_nxt — Full offline patch installer (병원 서버에서 실행)
#
# apply_patch.sh + hg19 수동 설치 + chown 을 하나의 스크립트로 통합.
# EONE /home/roche 등 비표준 설치 경로에서도 안전하게 동작합니다.
#
# 처리 항목:
#   1. 중요 파일 백업 (.env, log/orders_nxt.db, nextflow.config)
#   2. roche_data_hg19.tar → DATA_HOST_DIR
#   3. Roche_nxt_v*.tar.gz → INSTALL_DIR (소스)
#   4. roche_nxt_web / analysis 이미지 docker load
#   5. Web 컨테이너 재시작
#   6. RUN_USER ownership + .env UID/GID 갱신
#
# 사용법:
#   sudo bash apply_full_patch.sh \
#       --install-dir /home/roche \
#       --patch-dir /home/roche/roche_install/patch \
#       --run-user roche
#
# 옵션:
#   --install-dir <path>   설치 디렉터리 (필수 권장)
#   --patch-dir <path>     패치 파일 디렉터리 (기본: 스크립트 위치)
#   --run-user <user>      런타임 소유자 (기본: roche)
#   --skip-hg19            hg19 레퍼런스 tar 해제 생략
#   --skip-source          소스 tar 해제 생략
#   --skip-analysis        Analysis 이미지 load 생략
#   -y, --yes              확인 프롬프트 생략
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

confirm() {
    local prompt="$1"
    [[ $ASSUME_YES -eq 1 ]] && return 0
    local ans
    read -r -p "  ${prompt} [y/N] " ans || true
    [[ "${ans,,}" == "y" ]]
}

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

find_patch_file() {
    local dir="$1" pattern="$2"
    find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null | sort -V | tail -1
}

read_env_value() {
    local file="$1" key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true
}

# ── 인수 파싱 ────────────────────────────────────────────────────────────────
INSTALL_DIR=""
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_USER="roche"
SKIP_HG19=false
SKIP_SOURCE=false
SKIP_ANALYSIS=false
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)  INSTALL_DIR="$2";  shift 2 ;;
        --patch-dir)    PATCH_DIR="$2";    shift 2 ;;
        --run-user)     RUN_USER="$2";     shift 2 ;;
        --skip-hg19)    SKIP_HG19=true;    shift ;;
        --skip-source)  SKIP_SOURCE=true;  shift ;;
        --skip-analysis) SKIP_ANALYSIS=true; shift ;;
        -y|--yes)       ASSUME_YES=1;      shift ;;
        -h|--help)
            sed -n '/^# 사용법:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *) die "알 수 없는 옵션: $1 (bash $0 --help)" ;;
    esac
done

# ── 설치 디렉터리 자동 탐색 ──────────────────────────────────────────────────
if [[ -z "$INSTALL_DIR" ]]; then
    for d in /home/roche /opt/roche_nxt /opt/roche_bsch /opt/roche_eone /home/*/roche_nxt; do
        if has_compose_file "$d"; then
            INSTALL_DIR="$d"
            break
        fi
    done
    if [[ -z "$INSTALL_DIR" ]] && docker ps -q --filter "name=roche_nxt_web" | grep -q .; then
        INSTALL_DIR=$(docker inspect roche_nxt_web \
            --format '{{range .Mounts}}{{if eq .Destination "/roche_nxt"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    fi
fi

[[ -z "$INSTALL_DIR" ]] && die "--install-dir 를 지정하세요. 예: --install-dir /home/roche"
INSTALL_DIR="$(cd "$INSTALL_DIR" && pwd)"
PATCH_DIR="$(cd "$PATCH_DIR" && pwd)"

COMPOSE_FILE="$(resolve_compose_file "$INSTALL_DIR")" \
    || die "$INSTALL_DIR 에 docker-compose.prod.yml 또는 docker-compose.yml 이 없습니다."

[[ -f "$INSTALL_DIR/.env" ]] || die "$INSTALL_DIR/.env 가 없습니다."

id "$RUN_USER" &>/dev/null || die "런타임 사용자 없음: $RUN_USER"

# ── 패치 파일 탐색 ───────────────────────────────────────────────────────────
WEB_IMAGE=$(find_patch_file "$PATCH_DIR" "roche_nxt_web_*.tar.gz")
ANALYSIS_IMAGE=$(find_patch_file "$PATCH_DIR" "roche_nxt_analysis_*.tar.gz")
SOURCE_TAR=$(find_patch_file "$PATCH_DIR" "Roche_nxt_*.tar.gz")
HG19_TAR=$(find_patch_file "$PATCH_DIR" "roche_data_hg19.tar")
[[ -z "$HG19_TAR" ]] && HG19_TAR=$(find_patch_file "$PATCH_DIR" "roche_data_hg19.tar.gz")

DATA_DIR="$(read_env_value "$INSTALL_DIR/.env" "DATA_HOST_DIR")"
[[ -z "$DATA_DIR" ]] && DATA_DIR="${INSTALL_DIR}/data"

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
echo "${C_BLD}Roche_nxt — Full Patch Install${C_RST}"
echo "  설치 디렉터리  : $INSTALL_DIR"
echo "  패치 디렉터리  : $PATCH_DIR"
echo "  Compose 파일   : $COMPOSE_FILE"
echo "  DATA_HOST_DIR  : $DATA_DIR"
echo "  RUN_USER       : $RUN_USER"
echo "  현재 버전      : $CURRENT_VER"
echo "  목표 버전      : $NEW_VER"
echo
echo "  패치 파일:"
[[ -n "$WEB_IMAGE"      ]] && echo "    Web      : $(basename "$WEB_IMAGE")"       || echo "    Web      : (없음)"
[[ -n "$ANALYSIS_IMAGE" ]] && echo "    Analysis : $(basename "$ANALYSIS_IMAGE")"  || echo "    Analysis : (없음)"
[[ -n "$SOURCE_TAR"     ]] && echo "    Source   : $(basename "$SOURCE_TAR")"      || echo "    Source   : (없음)"
[[ -n "$HG19_TAR"       ]] && echo "    hg19 data: $(basename "$HG19_TAR")"        || echo "    hg19 data: (없음)"
echo

[[ -n "$WEB_IMAGE" ]] || die "Web 이미지(roche_nxt_web_*.tar.gz)가 패치 디렉터리에 없습니다."
command -v docker &>/dev/null || die "docker 가 설치되지 않았습니다."
docker compose version &>/dev/null || die "docker compose v2 가 필요합니다."

# ── Step 1: Preflight ─────────────────────────────────────────────────────────
h "Step 1/7 — Preflight"

RUNNING=$(docker ps --filter "name=nxt_" --format "{{.Names}}" 2>/dev/null | wc -l)
if [[ "$RUNNING" -gt 0 ]]; then
    warn "실행 중인 분석 컨테이너 ${RUNNING}개:"
    docker ps --filter "name=nxt_" --format "  {{.Names}} ({{.Status}})"
    confirm "계속 진행하시겠습니까?" || { echo "취소했습니다."; exit 0; }
fi
ok "Preflight 완료"

# ── Step 2: Backup ───────────────────────────────────────────────────────────
h "Step 2/7 — 중요 파일 백업"

BACKUP_DIR="$INSTALL_DIR/backup/full_patch_$(date +%Y%m%d_%H%M%S)"
if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        BACKUP_DIR="/tmp/roche_full_patch_backup_$(date +%Y%m%d_%H%M%S)_$$"
        mkdir -p "$BACKUP_DIR" || die "백업 디렉터리 생성 실패"
        warn "임시 백업 사용: $BACKUP_DIR"
    else
        warn "형제 backup 사용: $BACKUP_DIR"
    fi
fi

for f in ".env" "nextflow.config" "log/orders_nxt.db" "web_ui/orders.db"; do
    if [[ -f "$INSTALL_DIR/$f" ]]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp -p "$INSTALL_DIR/$f" "$BACKUP_DIR/$f"
        ok "백업: $f"
    fi
done

# ── Step 3: hg19 reference data ──────────────────────────────────────────────
h "Step 3/7 — hg19 레퍼런스 데이터"

if [[ "$SKIP_HG19" == true ]]; then
    warn "hg19 설치 생략 (--skip-hg19)"
elif [[ -z "$HG19_TAR" ]]; then
    warn "roche_data_hg19.tar 를 찾지 못했습니다 — hg19 단계 생략"
else
    mkdir -p "$DATA_DIR"
    if [[ -d "$DATA_DIR/refs/hg19" || -d "$DATA_DIR/snpeff" || -d "$DATA_DIR/dbsnp/hg19" ]]; then
        warn "기존 hg19 관련 데이터가 있습니다 — tar 내용으로 덮어씁니다 (refs, dbsnp, snpeff, bed 등)"
    fi
    info "압축 해제: $(basename "$HG19_TAR") → $DATA_DIR"
    case "$HG19_TAR" in
        *.tar.gz|*.tgz) tar -xzf "$HG19_TAR" -C "$DATA_DIR" ;;
        *.tar)          tar -xf  "$HG19_TAR" -C "$DATA_DIR" ;;
        *) die "지원하지 않는 hg19 tar 형식: $HG19_TAR" ;;
    esac
    [[ -f "$DATA_DIR/refs/hg19/hg19.fa" ]] \
        || die "hg19 압축 해제 후 $DATA_DIR/refs/hg19/hg19.fa 를 찾을 수 없습니다."
    ok "hg19 레퍼런스 설치 완료 (refs, dbsnp, snpeff, bed 등)"
    if [[ ! -f "$DATA_DIR/blocklist/panel_blocklist_hg19ucsc.txt" ]]; then
        warn "blocklist 없음: $DATA_DIR/blocklist/panel_blocklist_hg19ucsc.txt"
        warn "hg19 분석 시 필요할 수 있습니다 — tarball 내용을 확인하세요."
    fi
fi

# 소스 tar는 data/ 를 제외하는 경우가 있어, 바뀐 레퍼런스만 overlay로 복사
if [[ -d "$PATCH_DIR/data_overlay" ]]; then
    mkdir -p "$DATA_DIR"
    cp -a "$PATCH_DIR/data_overlay/." "$DATA_DIR/"
    ok "data overlay 적용 → $DATA_DIR"
    if [[ -f "$DATA_DIR/blocklist/panel_blocklist_hg19ucsc.txt" ]]; then
        ok "hg19 blocklist: $DATA_DIR/blocklist/panel_blocklist_hg19ucsc.txt"
    fi
fi

# ── Step 4: Source update ─────────────────────────────────────────────────────
h "Step 4/7 — 소스 파일 업데이트"

if [[ "$SKIP_SOURCE" == true ]]; then
    warn "소스 업데이트 생략 (--skip-source)"
elif [[ -z "$SOURCE_TAR" ]]; then
    warn "Roche_nxt_*.tar.gz 없음 — 소스 업데이트 생략"
else
    info "소스 교체: $(basename "$SOURCE_TAR") → $INSTALL_DIR"
    tar -xzf "$SOURCE_TAR" \
        -C "$INSTALL_DIR" \
        --strip-components=1 \
        --exclude='web_ui/orders.db' \
        --exclude='web_ui/*.db' \
        --exclude='.env' \
        --exclude='log' \
        --exclude='results' \
        --exclude='work'
    ok "소스 파일 업데이트 완료"
fi

# ── Step 5: Docker images ─────────────────────────────────────────────────────
h "Step 5/7 — Docker 이미지 로드"

info "Web 이미지: $(basename "$WEB_IMAGE")"
docker load < "$WEB_IMAGE"
ok "roche_nxt_web:latest 로드 완료"

if [[ "$SKIP_ANALYSIS" == true ]]; then
    warn "Analysis 이미지 생략 (--skip-analysis)"
elif [[ -n "$ANALYSIS_IMAGE" ]]; then
    info "Analysis 이미지: $(basename "$ANALYSIS_IMAGE") (수분 소요)"
    docker load < "$ANALYSIS_IMAGE"
    ok "roche_nxt_analysis:latest 로드 완료"
else
    warn "Analysis 이미지 없음 — 기존 이미지 유지"
fi

# ── Step 6: Ownership + .env ──────────────────────────────────────────────────
h "Step 6/7 — ownership 및 .env"

RUN_UID="$(id -u "$RUN_USER")"
RUN_GID="$(id -g "$RUN_USER")"
DOCKER_GID="$(getent group docker | cut -d: -f3 || echo 999)"

upsert_env() {
    local key="$1" val="$2"
    local file="$INSTALL_DIR/.env"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

upsert_env "HOST_DIR" "$INSTALL_DIR"
upsert_env "UID" "$RUN_UID"
upsert_env "GID" "$RUN_GID"
upsert_env "DOCKER_GID" "$DOCKER_GID"
ok ".env UID/GID → ${RUN_USER} (${RUN_UID}:${RUN_GID})"

# v1.4 신규 변수: 기존 .env에 없으면 기본값으로 추가
DEFAULT_DATA_DIR="${DATA_DIR:-${INSTALL_DIR}/data}"
upsert_env "LIFTOVER_HOST_DIR"           "${DEFAULT_DATA_DIR}/liftover"
upsert_env "LIFTOVER_CHAIN_HG38_TO_HG19" "/liftover/hg38ToHg19.over.chain.gz"
ok ".env 신규 변수 확인 완료 (LIFTOVER_HOST_DIR 등)"

chown -R "${RUN_UID}:${RUN_GID}" "$INSTALL_DIR"
if [[ -d "$DATA_DIR" ]]; then
    chown -R "${RUN_UID}:${RUN_GID}" "$DATA_DIR"
    ok "ownership: $INSTALL_DIR, $DATA_DIR → ${RUN_USER}"
else
    ok "ownership: $INSTALL_DIR → ${RUN_USER}"
fi

if ! id -nG "$RUN_USER" | tr ' ' '\n' | grep -qx docker; then
    warn "${RUN_USER} 가 docker 그룹에 없습니다."
    warn "root에서 1회 실행: usermod -aG docker ${RUN_USER}  (재로그인 필요)"
fi

# ── Step 7: Restart + verify ──────────────────────────────────────────────────
h "Step 7/7 — Web 서비스 재시작 및 확인"

cd "$INSTALL_DIR"
docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate roche-nxt-web
ok "Web 컨테이너 재시작 완료"

info "안정화 대기 (10초)..."
sleep 10

docker ps | grep -q roche_nxt_web \
    || die "roche_nxt_web 컨테이너가 실행 중이 아닙니다. docker logs roche_nxt_web 확인"

WEB_PORT="$(read_env_value "$INSTALL_DIR/.env" "WEB_PORT")"
WEB_PORT="${WEB_PORT:-8080}"

if curl -sf "http://localhost:${WEB_PORT}/api/version" &>/dev/null; then
    RUNNING_VER=$(curl -s "http://localhost:${WEB_PORT}/api/version" \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null || echo "?")
    ok "HTTP 응답 OK — 버전: $RUNNING_VER (port ${WEB_PORT})"
else
    warn "HTTP 응답 확인 실패 — http://<서버IP>:${WEB_PORT} 수동 확인"
fi

SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "<서버IP>")

echo
echo "${C_BLD}${C_GRN}════════════════════════════════════════${C_RST}"
echo "${C_BLD}${C_GRN}  Full patch install 완료${C_RST}"
echo "${C_BLD}${C_GRN}════════════════════════════════════════${C_RST}"
echo
echo "  이전 버전   : $CURRENT_VER"
echo "  목표 버전   : $NEW_VER"
echo "  백업 위치   : $BACKUP_DIR"
echo "  설치 디렉터리: $INSTALL_DIR"
echo "  DATA_HOST_DIR: $DATA_DIR"
echo "  RUN_USER     : $RUN_USER"
echo "  접속 URL     : http://${SERVER_IP}:${WEB_PORT}/"
echo
echo "  롤백 예시:"
echo "    cp ${BACKUP_DIR}/.env ${INSTALL_DIR}/.env"
echo "    cp ${BACKUP_DIR}/log/orders_nxt.db ${INSTALL_DIR}/log/orders_nxt.db"
echo "    chown -R ${RUN_USER}:${RUN_USER} ${INSTALL_DIR}"
echo
