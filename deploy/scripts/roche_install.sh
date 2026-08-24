#!/usr/bin/env bash
# =============================================================================
# Roche_nxt 통합 설치 / 업그레이드 스크립트
#
# 4가지 케이스를 자동 감지하여 처리합니다:
#   A. 신규 설치  + 이미지 파일 (오프라인)
#   B. 업그레이드 + 이미지 파일 (오프라인 패치)
#   C. 신규 설치  + GitHub 빌드 (온라인)
#   D. 업그레이드 + GitHub 빌드 (온라인)
#
# 사용법:
#   bash roche_install.sh [옵션]
#
# 옵션:
#   --install-dir <경로>   설치 위치            (기본: /opt/roche_nxt)
#   --data-dir    <경로>   레퍼런스 데이터 위치  (기본: <install-dir>/data)
#   --fastq-dir   <경로>   FASTQ 디렉터리       (기본: <install-dir>/fastq)
#   --port        <포트>   Web UI 포트          (기본: 8080)
#   --tag         <태그>   GitHub 버전 태그     (기본: main 최신, 온라인 모드)
#   --patch-dir   <경로>   패치 파일 디렉터리   (기본: 스크립트 위치)
#   --mode        fresh|patch   모드 강제 지정   (기본: 자동 감지)
#   --source      online|offline 소스 강제 지정 (기본: 자동 감지)
#   --yes                  모든 확인 자동 승인
#   --skip-data            데이터 tar 압축 해제 생략
#   --skip-analysis-build  Analysis 이미지 빌드 생략 (온라인 신규설치)
#
# 예시:
#   # 오프라인 신규 설치 (이미지·소스 tar가 스크립트 옆에 있을 때)
#   bash roche_install.sh --install-dir /home/roche_nxt --port 8002
#
#   # 온라인 신규 설치 (GitHub 접속 가능)
#   bash roche_install.sh --install-dir /opt/roche_nxt --source online --tag v1.3.0
#
#   # 오프라인 패치 (패치 tar.gz 파일이 스크립트 옆에 있을 때)
#   bash roche_install.sh --install-dir /home/roche_nxt
#
#   # 온라인 업그레이드
#   bash roche_install.sh --install-dir /home/roche_nxt --source online
# =============================================================================
set -Eeuo pipefail

REPO_URL="https://github.com/Xformyx/Roche_panel_analysis.git"

# ── 색상 출력 ─────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    C_GRN=$'\033[0;32m' C_YEL=$'\033[1;33m' C_RED=$'\033[0;31m'
    C_CYN=$'\033[0;36m' C_BLD=$'\033[1m'    C_RST=$'\033[0m'
else
    C_GRN="" C_YEL="" C_RED="" C_CYN="" C_BLD="" C_RST=""
fi

TOTAL_STEPS=9
CUR_STEP=0
step()  { CUR_STEP=$((CUR_STEP+1)); echo; echo "${C_BLD}${C_CYN}[$CUR_STEP/$TOTAL_STEPS] $*${C_RST}"; }
ok()    { echo "  ${C_GRN}✓${C_RST} $*"; }
info()  { echo "  ${C_CYN}→${C_RST} $*"; }
warn()  { echo "  ${C_YEL}⚠${C_RST} $*"; }
die()   { echo; echo "  ${C_RED}✗ $*${C_RST}" >&2; exit 1; }
ask()   {
    [[ "$YES" == true ]] && return 0
    read -r -p "  $* [y/N] " _ans
    [[ "${_ans,,}" == "y" ]]
}

# ── 인수 파싱 ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/roche_nxt"
DATA_DIR=""
FASTQ_DIR=""
PORT="8080"
TAG=""
PATCH_DIR="$SCRIPT_DIR"
FORCE_MODE=""        # fresh | patch
FORCE_SOURCE=""      # online | offline
YES=false
SKIP_DATA=false
SKIP_ANALYSIS_BUILD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-dir)          INSTALL_DIR="$2";         shift 2 ;;
        --data-dir)             DATA_DIR="$2";            shift 2 ;;
        --fastq-dir)            FASTQ_DIR="$2";           shift 2 ;;
        --port)                 PORT="$2";                shift 2 ;;
        --tag)                  TAG="$2";                 shift 2 ;;
        --patch-dir)            PATCH_DIR="$2";           shift 2 ;;
        --mode)                 FORCE_MODE="$2";          shift 2 ;;
        --source)               FORCE_SOURCE="$2";        shift 2 ;;
        --yes|-y)               YES=true;                 shift ;;
        --skip-data)            SKIP_DATA=true;           shift ;;
        --skip-analysis-build)  SKIP_ANALYSIS_BUILD=true; shift ;;
        -h|--help)
            grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \?//'
            exit 0 ;;
        *) die "알 수 없는 옵션: $1  (--help 로 도움말 확인)" ;;
    esac
done

# 기존 .env 가 있으면 DATA/FASTQ 경로를 우선 사용 (패치 시 병원별 경로 유지)
if [[ -z "${DATA_DIR:-}" && -f "$INSTALL_DIR/.env" ]]; then
    DATA_DIR=$(grep -E '^DATA_HOST_DIR=' "$INSTALL_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
fi
if [[ -z "${FASTQ_DIR:-}" && -f "$INSTALL_DIR/.env" ]]; then
    FASTQ_DIR=$(grep -E '^FASTQ_HOST_DIR=' "$INSTALL_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- || true)
fi
DATA_DIR="${DATA_DIR:-${INSTALL_DIR}/data}"
FASTQ_DIR="${FASTQ_DIR:-${INSTALL_DIR}/fastq}"

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

# ── Step 1: 모드 자동 감지 ────────────────────────────────────────────────────
step "설치 모드 감지"

# --- fresh vs patch ---
if [[ -n "$FORCE_MODE" ]]; then
    MODE="$FORCE_MODE"
elif [[ -f "$INSTALL_DIR/.env" ]] || resolve_compose_file "$INSTALL_DIR" >/dev/null 2>&1; then
    MODE="patch"
else
    MODE="fresh"
fi

# --- online vs offline ---
_find_file() {
    local pat="$1"
    # maxdepth 2: USB/v1.4.0/ 또는 그 안의 roche_patch_v1.4.0/ 모두 허용
    find "$PATCH_DIR" -maxdepth 2 -name "$pat" 2>/dev/null | sort -V | tail -1
}

# 패치 번들(roche_patch_v*.tar.gz)만 있고 풀려 있지 않으면 자동 해제
PATCH_BUNDLE=$(_find_file "roche_patch_v*.tar.gz")
WEB_IMAGE_TAR=$(_find_file "roche_nxt_web*.tar.gz")
if [[ -z "$WEB_IMAGE_TAR" && -n "$PATCH_BUNDLE" ]]; then
    info "패치 번들 압축 해제: $(basename "$PATCH_BUNDLE")"
    tar -xzf "$PATCH_BUNDLE" -C "$PATCH_DIR"
    WEB_IMAGE_TAR=$(_find_file "roche_nxt_web*.tar.gz")
fi

ANALYSIS_IMAGE_TAR=$(_find_file "roche_nxt_analysis*.tar.gz")
SOURCE_TAR=$(_find_file "Roche_nxt_v*.tar.gz")

if [[ -n "$FORCE_SOURCE" ]]; then
    SOURCE="$FORCE_SOURCE"
elif [[ -n "$WEB_IMAGE_TAR" ]]; then
    SOURCE="offline"
elif command -v git &>/dev/null && git ls-remote --exit-code "$REPO_URL" &>/dev/null 2>&1; then
    SOURCE="online"
else
    die "이미지 파일도 없고 GitHub 연결도 안 됩니다.\n  이미지 tar 파일을 스크립트 옆에 두거나, 인터넷 연결을 확인하세요."
fi

echo
echo "  ${C_BLD}감지된 케이스:${C_RST}"
echo "    모드   : ${C_BLD}$MODE${C_RST}  $([ "$MODE" = "fresh" ] && echo "(신규 설치)" || echo "(업그레이드/패치)")"
echo "    소스   : ${C_BLD}$SOURCE${C_RST}  $([ "$SOURCE" = "online" ] && echo "(GitHub 빌드)" || echo "(이미지 파일)")"
echo "    설치 위치: $INSTALL_DIR"
echo "    데이터 위치: $DATA_DIR"
echo "    포트   : $PORT"
[[ -n "$WEB_IMAGE_TAR"     ]] && echo "    Web 이미지  : $(basename $WEB_IMAGE_TAR)"
[[ -n "$ANALYSIS_IMAGE_TAR" ]] && echo "    분석 이미지 : $(basename $ANALYSIS_IMAGE_TAR)"
[[ -n "$SOURCE_TAR"         ]] && echo "    소스 tar   : $(basename $SOURCE_TAR)"
echo

if [[ "$MODE" = "patch" ]]; then
    warn "기존 설치를 업그레이드합니다. DB·.env·config는 자동 백업 후 보존됩니다."
fi
ask "위 설정으로 진행하시겠습니까?" || { echo "취소됨."; exit 0; }

# ── Step 2: Preflight ─────────────────────────────────────────────────────────
step "Preflight 확인"

command -v docker &>/dev/null         || die "Docker가 설치되지 않았습니다."
docker compose version &>/dev/null    || die "Docker Compose v2가 필요합니다."
ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'v2')"

# docker 그룹 확인
if ! docker info &>/dev/null; then
    warn "현재 사용자($USER)가 docker 그룹에 없습니다. sudo로 진행합니다."
    DOCKER_SUDO="sudo"
else
    DOCKER_SUDO=""
fi

# 디스크 여유 (신규: 20GB, 패치: 5GB)
MIN_GB=$([[ "$MODE" = "fresh" ]] && echo 20 || echo 5)
AVAIL_GB=$(df -BG "$(dirname $INSTALL_DIR)" 2>/dev/null | awk 'NR==2{gsub("G","");print $4}' || echo 999)
if (( AVAIL_GB < MIN_GB )); then
    warn "디스크 여유 공간 ${AVAIL_GB}GB — 최소 ${MIN_GB}GB 권장"
fi
ok "디스크 여유: ${AVAIL_GB}GB"

# 실행 중인 분석 컨테이너 확인 (패치 모드)
if [[ "$MODE" = "patch" ]]; then
    RUNNING=$(${DOCKER_SUDO} docker ps --filter "name=nxt_" --format "{{.Names}}" 2>/dev/null | wc -l)
    if (( RUNNING > 0 )); then
        warn "실행 중인 분석 컨테이너 ${RUNNING}개:"
        ${DOCKER_SUDO} docker ps --filter "name=nxt_" --format "  {{.Names}} ({{.Status}})"
        ask "분석 완료 전 업그레이드를 진행하시겠습니까?" || { echo "취소됨. 분석 완료 후 다시 실행하세요."; exit 0; }
    fi
fi

# ── Step 3: 중요 파일 백업 (패치 모드) ───────────────────────────────────────
if [[ "$MODE" = "patch" ]]; then
    step "중요 파일 백업"
    BACKUP_DIR="$INSTALL_DIR/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    for f in "web_ui/orders.db" "log/orders_nxt.db" "web_ui/app.py" ".env" "nextflow.config"; do
        if [[ -f "$INSTALL_DIR/$f" ]]; then
            mkdir -p "$BACKUP_DIR/$(dirname "$f")"
            cp "$INSTALL_DIR/$f" "$BACKUP_DIR/$f"
            ok "백업: $f → $BACKUP_DIR/$f"
        fi
    done
    echo "  (복원 방법: cp $BACKUP_DIR/<상대경로> $INSTALL_DIR/<동일경로>)"
else
    step "디렉터리 준비"
fi

# ── Step 4: 소스 코드 설치 ───────────────────────────────────────────────────
step "소스 코드 설치"

_ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
    fi
    # owner를 현재 사용자로 설정 (sudo 없이 쓸 수 있도록)
    if [[ "$(stat -c '%U' "$dir")" != "$USER" ]]; then
        sudo chown -R "$USER:$USER" "$dir" || true
    fi
}

if [[ "$SOURCE" = "offline" && -n "$SOURCE_TAR" ]]; then
    info "소스 tar 압축 해제: $(basename $SOURCE_TAR) → $INSTALL_DIR"
    _ensure_dir "$INSTALL_DIR"
    tar -xzf "$SOURCE_TAR" \
        -C "$INSTALL_DIR" \
        --strip-components=1 \
        --exclude='web_ui/orders.db' \
        --exclude='web_ui/*.db' \
        --exclude='.env' \
        --exclude='log' \
        --exclude='results' \
        --exclude='work' \
        --exclude='data' \
        --exclude='fastq' \
        --exclude='backup'
    ok "소스 코드 설치 완료"

elif [[ "$SOURCE" = "online" ]]; then
    command -v git &>/dev/null || die "git이 설치되지 않았습니다. (sudo dnf/apt install git)"
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        info "git pull — 기존 저장소 업데이트"
        cd "$INSTALL_DIR"
        git fetch origin
        if [[ -n "$TAG" ]]; then
            git checkout "$TAG"
            ok "버전: $TAG"
        else
            git checkout main && git pull origin main
            TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
            ok "버전: $TAG (main 최신)"
        fi
    else
        info "git clone: $REPO_URL → $INSTALL_DIR"
        _ensure_dir "$(dirname $INSTALL_DIR)"
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        if [[ -n "$TAG" ]]; then
            git checkout "$TAG"
        else
            TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "main")
        fi
        ok "클론 완료 (버전: $TAG)"
    fi

else
    # offline이지만 소스 tar가 없는 경우 — 이미지만 교체
    warn "소스 tar 파일 없음 — Docker 이미지만 교체합니다. (소스 코드 업데이트 생략)"
fi

# ── Step 5: 디렉터리 및 권한 설정 ────────────────────────────────────────────
step "디렉터리 및 권한 설정"

for dir in "$INSTALL_DIR" "$DATA_DIR" "$FASTQ_DIR" \
           "$INSTALL_DIR/log" "$INSTALL_DIR/results" "$INSTALL_DIR/backup"; do
    _ensure_dir "$dir"
done
ok "디렉터리 생성 완료"

# docker.sock 접근을 위한 docker 그룹 확인
if ! groups "$USER" | grep -q docker; then
    warn "$USER 가 docker 그룹에 없습니다. 추가합니다 (재로그인 필요할 수 있음)."
    sudo usermod -aG docker "$USER" || true
fi

# ── Step 6: Docker 이미지 준비 ────────────────────────────────────────────────
step "Docker 이미지 준비"

if [[ "$SOURCE" = "offline" ]]; then
    # Web 이미지 로드
    if [[ -n "$WEB_IMAGE_TAR" ]]; then
        info "Web 이미지 로드: $(basename $WEB_IMAGE_TAR)"
        ${DOCKER_SUDO} docker load < "$WEB_IMAGE_TAR"
        ok "roche_nxt_web:latest 로드 완료"
    else
        die "Web 이미지 tar 파일을 찾을 수 없습니다: $PATCH_DIR/roche_nxt_web*.tar.gz"
    fi

    # Analysis 이미지 로드 (있는 경우만)
    if [[ -n "$ANALYSIS_IMAGE_TAR" ]]; then
        info "Analysis 이미지 로드: $(basename $ANALYSIS_IMAGE_TAR) (수분 소요)"
        ${DOCKER_SUDO} docker load < "$ANALYSIS_IMAGE_TAR"
        ok "roche_nxt_analysis:latest 로드 완료"
    else
        if ${DOCKER_SUDO} docker image inspect roche_nxt_analysis:latest &>/dev/null; then
            ok "roche_nxt_analysis:latest — 기존 이미지 유지"
        else
            warn "Analysis 이미지 없음 — 분석 실행 전 별도 설치 필요"
        fi
    fi

else  # online — Dockerfile 빌드
    info "Web 이미지 빌드 중 (~2분)..."
    cd "$INSTALL_DIR"
    ${DOCKER_SUDO} docker build -f web_ui/Dockerfile web_ui/ -t roche_nxt_web:latest
    ok "roche_nxt_web:latest 빌드 완료"

    if [[ "$SKIP_ANALYSIS_BUILD" = true ]]; then
        warn "Analysis 이미지 빌드 생략 (--skip-analysis-build)"
        warn "나중에 직접 빌드: docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest"
    elif [[ "$MODE" = "patch" ]] && ${DOCKER_SUDO} docker image inspect roche_nxt_analysis:latest &>/dev/null; then
        ok "roche_nxt_analysis:latest — 기존 이미지 유지 (패치 시 재빌드 불필요)"
    else
        info "Analysis 이미지 빌드 중 (30분~2시간 소요)..."
        ${DOCKER_SUDO} docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest
        ok "roche_nxt_analysis:latest 빌드 완료"
    fi
fi

# ── Step 7: 레퍼런스 데이터 압축 해제 ─────────────────────────────────────────
step "레퍼런스 데이터 확인 및 설치"

if [[ "$SKIP_DATA" = true ]]; then
    warn "데이터 설치 생략 (--skip-data)"
else
    # 지원 파일명:
    #   roche_data_hg19.tar.gz
    #   roche_data_hg38.tar.gz | roche_data_hg38_base.tar.gz + roche_data_hg38_dbsnp.tar.gz
    #   rna_refs.tar.gz | roche_data.tar.gz
    # 최상단이 refs/ 등이면 strip 없이 해제 (신규 패키징). 래퍼 1단이면 strip=1.
    DATA_TARS=()
    for cand in \
        "$PATCH_DIR"/roche_data_hg38.tar "$PATCH_DIR"/roche_data_hg38.tar.gz \
        "$PATCH_DIR"/roche_data_hg38_base.tar.gz "$PATCH_DIR"/roche_data_hg38_dbsnp.tar.gz \
        "$PATCH_DIR"/roche_data_hg19.tar "$PATCH_DIR"/roche_data_hg19.tar.gz \
        "$PATCH_DIR"/rna_refs.tar.gz "$PATCH_DIR"/rna_refs.tar \
        "$PATCH_DIR"/roche_data.tar.gz "$PATCH_DIR"/roche_data.tar \
        "$(dirname "$PATCH_DIR")"/roche_data_hg38.tar.gz \
        "$(dirname "$PATCH_DIR")"/roche_data_hg38_base.tar.gz \
        "$(dirname "$PATCH_DIR")"/roche_data_hg38_dbsnp.tar.gz \
        "$(dirname "$PATCH_DIR")"/roche_data_hg19.tar.gz \
        "$(dirname "$PATCH_DIR")"/rna_refs.tar.gz; do
        [[ -f "$cand" ]] && DATA_TARS+=("$cand")
    done
    # 중복 제거 (같은 파일을 PATCH_DIR / parent 에서 둘 다 잡지 않도록)
    if [[ ${#DATA_TARS[@]} -gt 0 ]]; then
        mapfile -t DATA_TARS < <(printf '%s\n' "${DATA_TARS[@]}" | awk '!seen[$0]++')
    fi

    _extract_data_tar() {
        local tar_file="$1"
        local top
        top=$(tar -tf "$tar_file" 2>/dev/null | head -1 | cut -d/ -f1)
        local strip=0
        case "$top" in
            refs|dbsnp|snpeff|bed|blocklist|liftover) strip=0 ;;
            *) strip=1 ;;   # 예: data/refs/... 또는 roche_data/refs/...
        esac
        info "압축 해제: $(basename "$tar_file") → $DATA_DIR (strip=$strip)"
        case "$tar_file" in
            *.tar.gz|*.tgz) tar -xzf "$tar_file" -C "$DATA_DIR" --strip-components="$strip" ;;
            *.tar)          tar -xf  "$tar_file" -C "$DATA_DIR" --strip-components="$strip" ;;
        esac
    }

    if [[ ${#DATA_TARS[@]} -eq 0 ]]; then
        if [[ -d "$DATA_DIR/refs" ]] && [[ -n "$(ls -A "$DATA_DIR/refs" 2>/dev/null)" ]]; then
            ok "레퍼런스 데이터 이미 설치됨: $DATA_DIR/refs"
        else
            warn "레퍼런스 데이터 tar 파일 없음 — 분석 전 수동 설치 필요"
            warn "파일을 스크립트 옆에 두거나 --patch-dir 로 경로 지정:"
            warn "  roche_data_hg19.tar.gz"
            warn "  roche_data_hg38_base.tar.gz + roche_data_hg38_dbsnp.tar.gz"
            warn "  (또는 roche_data_hg38.tar.gz)"
        fi
    else
        _ensure_dir "$DATA_DIR"
        for tar_file in "${DATA_TARS[@]}"; do
            _extract_data_tar "$tar_file"
            ok "$(basename "$tar_file") 완료"
        done
    fi
fi

# 소스 tar는 data/ 를 제외하므로, 이번 패치에서 바뀐 레퍼런스 파일은 overlay로 복사
_OVERLAY=""
if [[ -d "$PATCH_DIR/data_overlay" ]]; then
    _OVERLAY="$PATCH_DIR/data_overlay"
elif [[ -d "$(dirname "$PATCH_DIR")/data_overlay" ]]; then
    _OVERLAY="$(dirname "$PATCH_DIR")/data_overlay"
fi
if [[ -n "$_OVERLAY" ]]; then
    _ensure_dir "$DATA_DIR"
    cp -a "$_OVERLAY/." "$DATA_DIR/"
    ok "data overlay 적용 → $DATA_DIR"
fi

# ── Step 8: .env 파일 설정 ─────────────────────────────────────────────────────
step ".env 환경 설정"

ENV_FILE="$INSTALL_DIR/.env"
upsert_env() {
    local key="$1" val="$2" file="$ENV_FILE"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${val}|" "$file"
    else
        echo "${key}=${val}" >> "$file"
    fi
}

if [[ -f "$ENV_FILE" ]]; then
    ok ".env 파일 이미 존재 — 기존 설정 유지 (신규 키만 보강)"
    EXISTING_PORT=$(grep -oP '(?<=WEB_PORT=)\S+' "$ENV_FILE" 2>/dev/null || echo "")
    if [[ -n "$EXISTING_PORT" && "$EXISTING_PORT" != "$PORT" ]]; then
        warn "기존 .env의 포트($EXISTING_PORT)와 지정 포트($PORT)가 다릅니다. 기존 값을 유지합니다."
    fi
else
    info ".env 파일 생성 중..."
    _UID=$(id -u)
    _GID=$(id -g)
    _DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo "999")

    cat > "$ENV_FILE" << ENVEOF
# Roche_nxt 환경 설정 — $(date '+%Y-%m-%d') 자동 생성
# 필요 시 직접 편집하세요.

HOST_DIR=${INSTALL_DIR}
DATA_HOST_DIR=${DATA_DIR}
FASTQ_HOST_DIR=${FASTQ_DIR}
BED_HOST_DIR=${DATA_DIR}/bed
RESULTS_HOST_DIR=${INSTALL_DIR}/results
WORK_HOST_DIR=${INSTALL_DIR}/work
LOG_HOST_DIR=${INSTALL_DIR}/log
LIFTOVER_HOST_DIR=${DATA_DIR}/liftover
LIFTOVER_CHAIN_HG38_TO_HG19=/liftover/hg38ToHg19.over.chain.gz

WEB_PORT=${PORT}
TZ=Asia/Seoul

UID=${_UID}
GID=${_GID}
DOCKER_GID=${_DOCKER_GID}

# 성능 제한 (0 = 제한없음)
MAX_CPUS=0
MAX_MEMORY=0
MAX_CONCURRENT_SAMPLES=0
ENVEOF
    ok ".env 파일 생성 완료 ($ENV_FILE)"
fi

# 패치/신규 공통: v1.4 필수 키 보강
upsert_env "HOST_DIR" "$INSTALL_DIR"
upsert_env "LIFTOVER_HOST_DIR" "${DATA_DIR}/liftover"
upsert_env "LIFTOVER_CHAIN_HG38_TO_HG19" "/liftover/hg38ToHg19.over.chain.gz"
# 예전 Nextflow 우회가 남아 있으면 제거 (최종 파이프라인과 충돌)
if grep -qE '^NXF_SYNTAX_PARSER=' "$ENV_FILE" 2>/dev/null; then
    sed -i '/^NXF_SYNTAX_PARSER=/d' "$ENV_FILE"
    warn ".env 에서 NXF_SYNTAX_PARSER 제거 (더 이상 불필요)"
fi
ok ".env 키 보강 완료"

# ── Step 9: 서비스 시작 ───────────────────────────────────────────────────────
step "서비스 시작"

cd "$INSTALL_DIR"
COMPOSE_NAME="$(resolve_compose_file "$INSTALL_DIR")" \
    || die "docker-compose.prod.yml / docker-compose.yml 을 찾을 수 없습니다: $INSTALL_DIR"
COMPOSE_FILE="$INSTALL_DIR/$COMPOSE_NAME"
info "Compose 파일: $COMPOSE_NAME"

${DOCKER_SUDO} docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
${DOCKER_SUDO} docker compose -f "$COMPOSE_FILE" up -d --force-recreate
ok "서비스 시작 완료"

info "안정화 대기 (8초)..."
sleep 8

if ${DOCKER_SUDO} docker ps --format "{{.Names}}" | grep -q roche_nxt_web; then
    ok "roche_nxt_web 컨테이너 정상 실행 중"
else
    die "컨테이너 시작 실패. 로그 확인: docker logs roche_nxt_web"
fi

# 버전 확인
APP_VER=$(curl -s "http://localhost:${PORT}/api/version" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null \
    || cat "$INSTALL_DIR/web_ui/version.json" 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('version','?'))" 2>/dev/null \
    || echo "?")
ok "Roche_nxt v${APP_VER}"

# ── 완료 메시지 ───────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<서버IP>")
echo
echo "${C_BLD}${C_GRN}══════════════════════════════════════════${C_RST}"
if [[ "$MODE" = "fresh" ]]; then
    echo "${C_BLD}${C_GRN}  설치 완료! Roche_nxt v${APP_VER}${C_RST}"
else
    echo "${C_BLD}${C_GRN}  업그레이드 완료! Roche_nxt v${APP_VER}${C_RST}"
fi
echo "${C_BLD}${C_GRN}══════════════════════════════════════════${C_RST}"
echo
echo "  웹 UI 접속: ${C_BLD}http://${SERVER_IP}:${PORT}${C_RST}"
echo
if [[ "$MODE" = "patch" ]]; then
    echo "  백업 위치: $BACKUP_DIR"
    echo "  (문제 발생 시 백업에서 복원 후 재시작하세요)"
fi
if [[ "$SKIP_DATA" = true ]] || [[ ${#DATA_TARS[@]-0} -eq 0 ]]; then
    echo
    echo "  ${C_YEL}⚠ 레퍼런스 데이터 미설치 — 분석 전 아래 명령 실행 필요:${C_RST}"
    echo "     tar -xf roche_data_hg38.tar -C ${DATA_DIR}"
    echo "     tar -xf roche_data_hg19.tar -C ${DATA_DIR}  # hg19 필요 시"
fi
echo
