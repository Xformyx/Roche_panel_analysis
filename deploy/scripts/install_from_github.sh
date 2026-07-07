#!/usr/bin/env bash
#
# Roche_nxt — GitHub 소스 빌드 신규 설치 스크립트
#
# 용도:
#   GitHub에서 소스를 클론하고 Docker 이미지를 빌드하여
#   처음부터 설치합니다. (SNUH 등 인터넷 접속 가능한 신규 서버)
#
# 사전 요구사항:
#   - Docker Engine + Docker Compose v2 설치 완료
#   - GitHub (https://github.com) 접속 가능
#   - 레퍼런스 데이터: 설치 후 FTP에서 별도 다운로드
#
# 사용법:
#   bash install_from_github.sh [옵션]
#
# 옵션:
#   --install-dir <경로>   설치 위치 (기본: /opt/roche_nxt)
#   --tag <v1.x.x>        특정 버전 태그 (기본: main 최신)
#   --port <포트>          웹 UI 포트 (기본: 8080)
#   --fastq-dir <경로>    FASTQ 디렉터리 (기본: <install-dir>/fastq)
#   --data-dir <경로>     레퍼런스 데이터 디렉터리 (기본: <install-dir>/data)
#   --skip-analysis-build  Analysis 이미지 빌드 생략 (나중에 직접 빌드)
#
# 예시:
#   bash install_from_github.sh --install-dir /opt/roche_nxt --tag v1.3.0
#
set -Eeuo pipefail

REPO_URL="https://github.com/Xformyx/Roche_panel_analysis.git"

# ── 색상 출력 ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'; C_RED=$'\033[0;31m'
    C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_YEL=""; C_RED=""; C_CYN=""; C_BLD=""; C_RST=""
fi

TOTAL_STEPS=7
CUR_STEP=0
step() { CUR_STEP=$((CUR_STEP+1)); echo; echo "${C_BLD}${C_CYN}[$CUR_STEP/$TOTAL_STEPS] $*${C_RST}"; }
ok()   { echo "  ${C_GRN}✓${C_RST} $*"; }
info() { echo "  ${C_CYN}→${C_RST} $*"; }
warn() { echo "  ${C_YEL}⚠${C_RST} $*"; }
die()  { echo "  ${C_RED}✗${C_RST} $*" >&2; exit 1; }

# ── 인수 파싱 ────────────────────────────────────────────────────────────────
INSTALL_DIR="/opt/roche_nxt"
TARGET_TAG=""
WEB_PORT="8080"
FASTQ_DIR=""
DATA_DIR=""
SKIP_ANALYSIS_BUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)         INSTALL_DIR="$2";          shift 2 ;;
        --tag)                 TARGET_TAG="$2";            shift 2 ;;
        --port)                WEB_PORT="$2";              shift 2 ;;
        --fastq-dir)           FASTQ_DIR="$2";             shift 2 ;;
        --data-dir)            DATA_DIR="$2";              shift 2 ;;
        --skip-analysis-build) SKIP_ANALYSIS_BUILD=true;   shift ;;
        -h|--help)
            sed -n '/^# 사용법:/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
            exit 0 ;;
        *) die "알 수 없는 옵션: $1" ;;
    esac
done

# 기본값 설정
FASTQ_DIR="${FASTQ_DIR:-${INSTALL_DIR}/fastq}"
DATA_DIR="${DATA_DIR:-${INSTALL_DIR}/data}"

echo
echo "${C_BLD}Roche_nxt — GitHub 소스 빌드 신규 설치${C_RST}"
echo "  설치 디렉터리  : $INSTALL_DIR"
echo "  버전           : ${TARGET_TAG:-main 최신}"
echo "  웹 포트        : $WEB_PORT"
echo "  FASTQ 디렉터리 : $FASTQ_DIR"
echo "  데이터 디렉터리: $DATA_DIR"
echo "  Analysis 빌드  : $([[ $SKIP_ANALYSIS_BUILD == true ]] && echo '생략 (나중에 직접)' || echo '포함')"
echo

# ── Step 1: Preflight ────────────────────────────────────────────────────────
step "Preflight 확인"

# Docker 확인
command -v docker &>/dev/null       || die "Docker가 설치되지 않았습니다. docs/INSTALL_BUILD.md Step 1 참조."
docker compose version &>/dev/null  || die "Docker Compose v2가 필요합니다."
ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
ok "Docker Compose $(docker compose version --short)"

# Git 확인
command -v git &>/dev/null || die "git이 설치되지 않았습니다. (sudo dnf install git 또는 sudo apt install git)"
ok "git $(git --version | grep -oP '\d+\.\d+\.\d+' | head -1)"

# GitHub 연결 확인
info "GitHub 연결 확인 중..."
if ! git ls-remote --exit-code "$REPO_URL" &>/dev/null; then
    die "GitHub에 연결할 수 없습니다. 인터넷 연결 및 방화벽을 확인하세요.\n  URL: $REPO_URL"
fi
ok "GitHub 연결 확인"

# 디스크 여유 공간 확인 (최소 20GB — 이미지 빌드용)
AVAIL_GB=$(df -BG "$( dirname $INSTALL_DIR 2>/dev/null || echo / )" | awk 'NR==2 {gsub("G",""); print $4}')
if [[ "$AVAIL_GB" -lt 20 ]]; then
    warn "디스크 여유 공간이 ${AVAIL_GB}GB입니다. Analysis 이미지 빌드에 최소 20GB 필요합니다."
fi
ok "디스크 여유 공간: ${AVAIL_GB}GB"

# 이미 설치된 경우 경고
if [[ -f "$INSTALL_DIR/docker-compose.prod.yml" ]]; then
    warn "$INSTALL_DIR 에 이미 설치가 존재합니다."
    read -r -p "  덮어쓰시겠습니까? (기존 .env·DB는 보존됩니다) [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "설치를 취소했습니다."; exit 0; }
fi

# ── Step 2: 소스코드 클론 ────────────────────────────────────────────────────
step "소스코드 클론"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "기존 git 저장소 발견 — pull로 업데이트"
    cd "$INSTALL_DIR"
    git fetch origin
else
    info "클론 중: $REPO_URL → $INSTALL_DIR"
    # 기존 .env와 DB 보존
    if [[ -f "$INSTALL_DIR/.env" ]]; then
        cp "$INSTALL_DIR/.env" /tmp/.env.roche_backup
        info ".env 백업 → /tmp/.env.roche_backup"
    fi
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    # .env 복원
    if [[ -f "/tmp/.env.roche_backup" ]]; then
        cp /tmp/.env.roche_backup "$INSTALL_DIR/.env"
        ok ".env 복원 완료"
    fi
fi

if [[ -n "$TARGET_TAG" ]]; then
    git checkout "$TARGET_TAG"
    ok "버전: $TARGET_TAG"
else
    git checkout main && git pull origin main
    TARGET_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
    ok "버전: $TARGET_TAG (main 최신)"
fi

VERSION=$(python3 -c "import json; print(json.load(open('web_ui/version.json'))['version'])" 2>/dev/null || echo "unknown")
ok "Roche_nxt v$VERSION"

# ── Step 3: Web 이미지 빌드 ──────────────────────────────────────────────────
step "Web 이미지 빌드 (~2분)"

info "roche_nxt_web:latest 빌드 중..."
docker build -f web_ui/Dockerfile web_ui/ -t roche_nxt_web:latest
ok "roche_nxt_web:latest 빌드 완료"

# ── Step 4: Analysis 이미지 빌드 ─────────────────────────────────────────────
step "Analysis 이미지 빌드"

if [[ "$SKIP_ANALYSIS_BUILD" == true ]]; then
    warn "Analysis 이미지 빌드 생략 (--skip-analysis-build)"
    warn "나중에 직접 빌드하세요:"
    warn "  cd $INSTALL_DIR"
    warn "  docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest"
else
    info "roche_nxt_analysis:latest 빌드 중 (30분~2시간 소요)..."
    info "빌드 로그: docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest"
    docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest
    ok "roche_nxt_analysis:latest 빌드 완료"
fi

# ── Step 5: 디렉터리 생성 ────────────────────────────────────────────────────
step "디렉터리 및 환경설정"

sudo mkdir -p "$FASTQ_DIR" "$DATA_DIR"
sudo chown "$USER:$USER" "$FASTQ_DIR" "$DATA_DIR"
ok "FASTQ 디렉터리: $FASTQ_DIR"
ok "데이터 디렉터리: $DATA_DIR"

# ── Step 6: .env 파일 생성 ───────────────────────────────────────────────────
step ".env 환경설정"

if [[ -f "$INSTALL_DIR/.env" ]]; then
    ok ".env 파일 이미 존재 — 유지합니다."
    warn "필요 시 직접 편집하세요: nano $INSTALL_DIR/.env"
else
    _UID=$(id -u)
    _GID=$(id -g)
    _DOCKER_GID=$(getent group docker | cut -d: -f3 || echo "999")

    cat > "$INSTALL_DIR/.env" << ENV
# Roche_nxt 환경설정 — $(date '+%Y-%m-%d') 자동 생성
# 서버 환경에 맞게 수정하세요.

HOST_DIR=${INSTALL_DIR}
DATA_HOST_DIR=${DATA_DIR}
FASTQ_HOST_DIR=${FASTQ_DIR}
BED_HOST_DIR=${DATA_DIR}/bed/hg38

WEB_PORT=${WEB_PORT}
TZ=Asia/Seoul

UID=${_UID}
GID=${_GID}
DOCKER_GID=${_DOCKER_GID}

# 성능 제한 (0 = 제한없음)
MAX_CPUS=0
MAX_MEMORY=0
MAX_CONCURRENT_SAMPLES=0
ENV
    ok ".env 파일 생성 완료"
fi

# ── Step 6b: 레퍼런스 데이터 압축 해제 (파일이 있으면) ──────────────────────
# 스크립트 실행 디렉터리 또는 --data-dir 경로에 tar 파일이 있으면 자동으로 풀어줌
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_DATA_TARS=()
for _cand in \
    "$SCRIPT_DIR/roche_data_hg38.tar"  "$SCRIPT_DIR/roche_data_hg38.tar.gz" \
    "$SCRIPT_DIR/roche_data_hg19.tar"  "$SCRIPT_DIR/roche_data_hg19.tar.gz" \
    "$SCRIPT_DIR/rna_refs.tar.gz"       "$SCRIPT_DIR/rna_refs.tar" \
    "$DATA_DIR/roche_data_hg38.tar"    "$DATA_DIR/roche_data_hg38.tar.gz" \
    "$DATA_DIR/roche_data_hg19.tar"    "$DATA_DIR/roche_data_hg19.tar.gz" \
    "$DATA_DIR/rna_refs.tar.gz"         "$DATA_DIR/rna_refs.tar"; do
    [[ -f "$_cand" ]] && _DATA_TARS+=("$_cand")
done

if [[ ${#_DATA_TARS[@]} -gt 0 ]]; then
    step "레퍼런스 데이터 압축 해제"
    for _tar in "${_DATA_TARS[@]}"; do
        info "$(basename "$_tar") → $DATA_DIR ..."
        case "$_tar" in
            *.tar.gz|*.tgz) tar -xzf "$_tar" -C "$DATA_DIR" --strip-components=1 ;;
            *.tar)           tar -xf  "$_tar" -C "$DATA_DIR" --strip-components=1 ;;
        esac
        ok "$(basename "$_tar") 완료"
    done
else
    info "레퍼런스 데이터 tar 파일을 찾지 못했습니다."
    info "설치 완료 후 아래 안내에 따라 수동으로 복사·해제하세요."
fi

# ── Step 7: 서비스 시작 ──────────────────────────────────────────────────────
step "서비스 시작"

cd "$INSTALL_DIR"
docker compose -f docker-compose.prod.yml up -d
ok "서비스 시작 완료"

info "안정화 대기 (10초)..."
sleep 10

if docker ps | grep -q roche_nxt_web; then
    ok "roche_nxt_web 컨테이너 실행 중"
else
    die "컨테이너 시작 실패. 'docker logs roche_nxt_web' 로 확인하세요."
fi

# ── 완료 ─────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "<서버IP>")

echo
echo "${C_BLD}${C_GRN}════════════════════════════════════════${C_RST}"
echo "${C_BLD}${C_GRN}  설치 완료! Roche_nxt v${VERSION}${C_RST}"
echo "${C_BLD}${C_GRN}════════════════════════════════════════${C_RST}"
echo
echo "  웹 UI 접속: ${C_BLD}http://${SERVER_IP}:${WEB_PORT}${C_RST}"
echo
echo "  다음 단계:"
echo "  1. 레퍼런스 데이터 다운로드 (FTP에서):"
echo "       wget ftp://[FTP_SERVER]/roche_nxt/data/roche_data_hg38.tar"
echo "       tar -xf roche_data_hg38.tar -C ${DATA_DIR}"
echo
echo "  2. (hg19 필요 시)"
echo "       wget ftp://[FTP_SERVER]/roche_nxt/data/roche_data_hg19.tar"
echo "       tar -xf roche_data_hg19.tar -C ${DATA_DIR}"
echo
echo "  3. SNUH BED 파일 설정은 SNUH_DEPLOY.md 참조"
echo
if [[ "$SKIP_ANALYSIS_BUILD" == true ]]; then
    echo "  ⚠ Analysis 이미지 빌드 필요:"
    echo "       cd $INSTALL_DIR"
    echo "       docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest"
    echo
fi
