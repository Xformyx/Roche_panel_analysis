#!/usr/bin/env bash
#
# Roche_nxt — hg38_primary 레퍼런스 설치 스크립트 (병원 서버에서 실행)
#
# alt contig 가 있으면 패널 영역의 read 가 primary 염색체와 alt 사본에 동점으로
# 붙어 MAPQ 0 이 되고, CollectHsMetrics 가 이를 버립니다. NHL 패널에서 845개
# 타깃 중 110개가 커버리지 0x 가 되고(82개가 chr14 IGH), Uniformity >=100x 가
# 91% -> 79% 로 떨어집니다. 이 스크립트는 _alt(261) / HLA-*(525) contig 를 제거한
# primary-only 레퍼런스를 설치합니다.
#
# 두 가지 방식 중 하나를 선택합니다:
#
#   usb   — USB 에 담아온 완성된 레퍼런스를 복사합니다.
#           약 8GB 전송, 10~20분. 서버 CPU 를 쓰지 않습니다.
#
#   build — 서버에 이미 있는 ucsc.hg38.fasta 에서 직접 만듭니다.
#           전송 불필요, 약 70분 (대부분 bwa index). CPU 1코어를 점유합니다.
#
#   auto  — payload 가 있으면 usb, 없으면 build (기본값).
#
# 사용법:
#   bash install_hg38_primary.sh                          # auto
#   bash install_hg38_primary.sh --mode usb --payload /media/usb/hg38_primary.tar.gz
#   bash install_hg38_primary.sh --mode build
#
# 요구사항:
#   - roche_nxt_analysis 이미지 (build 모드에서 samtools / bwa / gatk 사용)
#   - 여유 디스크 9GB 이상
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
DATA_DIR=""
MODE="auto"
PAYLOAD=""
FORCE=0
ANALYSIS_IMAGE="${ANALYSIS_IMAGE:-roche_nxt_analysis:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        --mode)     MODE="$2";     shift 2 ;;
        --payload)  PAYLOAD="$2";  shift 2 ;;
        --force)    FORCE=1;       shift ;;
        -h|--help)
            echo "Usage: $0 [--mode auto|usb|build] [--payload <tar.gz|dir>]"
            echo "          [--data-dir <path>] [--force]"
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

case "$MODE" in
    auto|usb|build) ;;
    *) die "--mode 는 auto / usb / build 중 하나여야 합니다: $MODE" ;;
esac

# ── 데이터 디렉터리 자동 탐색 ────────────────────────────────────────────────
if [[ -z "$DATA_DIR" ]]; then
    # 실행 중인 web 컨테이너의 /roche_data 마운트가 가장 정확하다
    if docker ps -q --filter "name=roche_nxt_web" | grep -q .; then
        DATA_DIR=$(docker inspect roche_nxt_web \
            --format '{{range .Mounts}}{{if eq .Destination "/roche_data"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    fi
fi
if [[ -z "$DATA_DIR" ]]; then
    for d in /home/roche/roche_data /opt/roche_data /home/*/roche_data; do
        [[ -d "$d/refs/hg38" ]] && { DATA_DIR="$d"; break; }
    done
fi
[[ -z "$DATA_DIR" ]] && die "--data-dir 를 지정하세요. 예: --data-dir /opt/roche_data"
DATA_DIR="$(cd "$DATA_DIR" && pwd)"

SRC_FASTA="$DATA_DIR/refs/hg38/ucsc.hg38.fasta"
OUT_DIR="$DATA_DIR/refs/hg38_primary"
VENDOR_BAIT="$DATA_DIR/bed/hg38/NHL_bed/KAPA_HyperCap_DS_NHL_Panel_capture_targets_bait.interval_list"

OUT_FASTA="$OUT_DIR/ucsc.hg38.primary.fasta"
OUT_DICT="$OUT_DIR/ucsc.hg38.primary.dict"
OUT_BAIT="$OUT_DIR/KAPA_HyperCap_DS_NHL_Panel_capture_targets_bait.interval_list"

EXPECTED_CONTIGS=2580

# ── payload 자동 탐색 (auto / usb 모드) ──────────────────────────────────────
find_payload() {
    [[ -n "$PAYLOAD" ]] && { echo "$PAYLOAD"; return; }
    local c
    for c in "$SCRIPT_DIR/hg38_primary.tar.gz" \
             "$SCRIPT_DIR/../hg38_primary.tar.gz" \
             "$SCRIPT_DIR/../reference/hg38_primary.tar.gz" \
             /media/*/hg38_primary.tar.gz /mnt/*/hg38_primary.tar.gz; do
        [[ -f "$c" ]] && { echo "$c"; return; }
    done
    echo ""
}

PAYLOAD="$(find_payload)"

if [[ "$MODE" == "auto" ]]; then
    if [[ -n "$PAYLOAD" ]]; then MODE="usb"; else MODE="build"; fi
fi
if [[ "$MODE" == "usb" && -z "$PAYLOAD" ]]; then
    die "usb 모드인데 payload 를 찾을 수 없습니다. --payload 로 경로를 지정하세요."
fi

echo
echo "${C_BLD}Roche_nxt — hg38_primary 레퍼런스 설치${C_RST}"
echo "  데이터 디렉터리 : $DATA_DIR"
echo "  출력 디렉터리   : $OUT_DIR"
echo "  설치 방식       : $MODE"
[[ "$MODE" == "usb"   ]] && echo "  payload         : $PAYLOAD"
[[ "$MODE" == "build" ]] && echo "  원본 FASTA      : $SRC_FASTA"
[[ "$MODE" == "build" ]] && echo "  분석 이미지     : $ANALYSIS_IMAGE"
echo

# ── Preflight ────────────────────────────────────────────────────────────────
h "Preflight"

if [[ "$MODE" == "build" ]]; then
    command -v docker >/dev/null || die "docker 를 찾을 수 없습니다."
    docker image inspect "$ANALYSIS_IMAGE" &>/dev/null \
        || die "$ANALYSIS_IMAGE 이미지가 없습니다. 먼저 분석 이미지를 로드하세요."
    ok "분석 이미지 확인"
    [[ -f "$SRC_FASTA"     ]] || die "원본 FASTA 가 없습니다: $SRC_FASTA"
    [[ -f "$SRC_FASTA.fai" ]] || die "원본 FASTA 인덱스가 없습니다: $SRC_FASTA.fai"
    [[ -f "$VENDOR_BAIT"   ]] || die "bait interval_list 가 없습니다: $VENDOR_BAIT"
    ok "입력 파일 확인"
else
    [[ -e "$PAYLOAD" ]] || die "payload 를 찾을 수 없습니다: $PAYLOAD"
    ok "payload 확인 ($(du -sh "$PAYLOAD" | cut -f1))"
fi

AVAIL_KB=$(df -Pk "$DATA_DIR" | awk 'NR==2 {print $4}')
if (( AVAIL_KB < 9 * 1024 * 1024 )); then
    die "디스크 여유 공간 부족: $(( AVAIL_KB / 1024 / 1024 ))GB (9GB 이상 필요)"
fi
ok "디스크 여유 공간 $(( AVAIL_KB / 1024 / 1024 ))GB"

# 이미 완성되어 있으면 건너뛴다
if [[ $FORCE -eq 0 && -s "$OUT_FASTA.sa" && -s "$OUT_FASTA.bwt" && -s "$OUT_BAIT" ]]; then
    ok "hg38_primary 가 이미 설치되어 있습니다. 다시 설치하려면 --force 를 사용하세요."
    exit 0
fi

mkdir -p "$OUT_DIR"

# ═════════════════════════════════════════════════════════════════════════════
#  방식 1 — USB payload 복사
# ═════════════════════════════════════════════════════════════════════════════
install_from_payload() {
    h "1/2  payload 검증"

    if [[ -f "$PAYLOAD" ]]; then
        local sums="${PAYLOAD%.tar.gz}.sha256"
        if [[ -f "$sums" ]]; then
            info "sha256 검증 중 (수 분 소요)..."
            ( cd "$(dirname "$PAYLOAD")" && sha256sum -c "$(basename "$sums")" ) \
                || die "payload 체크섬이 일치하지 않습니다. USB 복사가 손상되었습니다."
            ok "체크섬 일치"
        else
            warn "체크섬 파일이 없어 무결성 검증을 건너뜁니다: $sums"
        fi
    fi

    h "2/2  레퍼런스 복사 (10~20분 소요)"
    if [[ -d "$PAYLOAD" ]]; then
        info "디렉터리 복사 중: $PAYLOAD → $OUT_DIR"
        cp -a "$PAYLOAD/." "$OUT_DIR/"
    else
        info "압축 해제 중: $PAYLOAD → $OUT_DIR"
        # payload 는 hg38_primary/ 를 최상위로 담고 있다
        tar -xzf "$PAYLOAD" -C "$(dirname "$OUT_DIR")"
    fi
    ok "복사 완료"
}

# ═════════════════════════════════════════════════════════════════════════════
#  방식 2 — 기존 hg38 에서 생성
# ═════════════════════════════════════════════════════════════════════════════
# 컨테이너에서 DATA_DIR 을 /data 로 마운트한다. .dict 의 UR 필드에 이 경로가
# 기록되므로 개발 환경과 동일하게 맞춰 산출물을 재현 가능하게 유지한다.
run_in_image() {
    docker run --rm --user "$(id -u):$(id -g)" -v "$DATA_DIR:/data" "$ANALYSIS_IMAGE" bash -lc "$1"
}

install_by_building() {
    h "1/6  contig 목록 작성"
    cut -f1 "$SRC_FASTA.fai" | grep -v '_alt$' | grep -v '^HLA-' > "$OUT_DIR/keep_contigs.txt"

    local total n_alt n_hla keep
    total=$(wc -l < "$SRC_FASTA.fai")
    n_alt=$(cut -f1 "$SRC_FASTA.fai" | grep -c '_alt$' || true)
    n_hla=$(cut -f1 "$SRC_FASTA.fai" | grep -c '^HLA-' || true)
    keep=$(wc -l < "$OUT_DIR/keep_contigs.txt")

    echo "    전체 contig : $total"
    echo "    제외 _alt   : $n_alt"
    echo "    제외 HLA-*  : $n_hla"
    echo "    유지        : $keep"
    (( keep == total - n_alt - n_hla )) || die "contig 수 계산이 맞지 않습니다."
    ok "contig 목록 작성 완료"

    h "2/6  FASTA 추출 (수 분 소요)"
    run_in_image "samtools faidx -r /data/refs/hg38_primary/keep_contigs.txt /data/refs/hg38/ucsc.hg38.fasta > /data/refs/hg38_primary/ucsc.hg38.primary.fasta"
    ok "FASTA 추출 완료 ($(du -h "$OUT_FASTA" | cut -f1))"

    h "3/6  FASTA 인덱스 (.fai)"
    run_in_image "samtools faidx /data/refs/hg38_primary/ucsc.hg38.primary.fasta"
    ok ".fai 생성 완료"

    h "4/6  sequence dictionary / genome file"
    rm -f "$OUT_DICT"
    run_in_image "gatk CreateSequenceDictionary -R /data/refs/hg38_primary/ucsc.hg38.primary.fasta -O /data/refs/hg38_primary/ucsc.hg38.primary.dict" \
        > "$OUT_DIR/create_dict.log" 2>&1 \
        || { cat "$OUT_DIR/create_dict.log"; die "CreateSequenceDictionary 실패 (로그: $OUT_DIR/create_dict.log)"; }
    cut -f1,2 "$OUT_FASTA.fai" > "$OUT_DIR/genome_file.txt"
    ok ".dict / genome_file.txt 생성 완료"

    # 좌표는 그대로 두고 @SQ 헤더만 새 dict 로 교체한다. CollectHsMetrics 는 BAM 과
    # interval_list 의 sequence dictionary 가 일치해야 동작한다.
    h "5/6  bait interval_list 재생성"
    {
        printf '@HD\tVN:1.6\tSO:coordinate\n'
        grep '^@SQ' "$OUT_DICT"
        grep -v '^@' "$VENDOR_BAIT"
    } > "$OUT_BAIT"
    ok "bait interval_list 재생성 완료 ($(grep -vc '^@' "$OUT_BAIT") intervals)"

    h "6/6  BWA 인덱스 (약 60~70분 소요)"
    info "시작: $(date '+%H:%M:%S') — 완료까지 기다려 주세요."
    run_in_image "bwa index /data/refs/hg38_primary/ucsc.hg38.primary.fasta" \
        > "$OUT_DIR/bwa_index.log" 2>&1 \
        || { tail -20 "$OUT_DIR/bwa_index.log"; die "bwa index 실패 (로그: $OUT_DIR/bwa_index.log)"; }
    ok "BWA 인덱스 완료: $(date '+%H:%M:%S')"
}

case "$MODE" in
    usb)   install_from_payload ;;
    build) install_by_building  ;;
esac

# ═════════════════════════════════════════════════════════════════════════════
#  검증 — 두 방식 모두 동일하게 통과해야 한다
# ═════════════════════════════════════════════════════════════════════════════
h "검증"

for f in "$OUT_FASTA" "$OUT_DICT" "$OUT_BAIT" "$OUT_DIR/genome_file.txt"; do
    [[ -s "$f" ]] || die "필수 파일 누락: $f"
done
for ext in amb ann bwt pac sa fai; do
    [[ -s "$OUT_FASTA.$ext" ]] || die "인덱스 파일 누락: ucsc.hg38.primary.fasta.$ext"
done
ok "필수 파일 존재"

N_FAI=$(wc -l < "$OUT_FASTA.fai")
N_ANN=$(head -1 "$OUT_FASTA.ann" | awk '{print $2}')
N_SQ=$(grep -c '^@SQ' "$OUT_DICT")
N_BAIT_SQ=$(grep -c '^@SQ' "$OUT_BAIT")
echo "    .fai contig       : $N_FAI"
echo "    .ann contig       : $N_ANN"
echo "    .dict @SQ         : $N_SQ"
echo "    bait @SQ          : $N_BAIT_SQ"
[[ "$N_FAI" == "$N_ANN" && "$N_FAI" == "$N_SQ" && "$N_FAI" == "$N_BAIT_SQ" ]] \
    || die "contig 수가 일치하지 않습니다. --force 로 재설치하세요."
ok "contig 수 일치 ($N_FAI)"

if [[ "$N_FAI" != "$EXPECTED_CONTIGS" ]]; then
    warn "contig 수가 예상값 $EXPECTED_CONTIGS 과 다릅니다 ($N_FAI)."
    warn "원본 hg38 빌드가 표준 UCSC 3,366 contig 가 아닐 수 있습니다."
fi

ALT_LEFT=$(cut -f1 "$OUT_FASTA.fai" | grep -cE '_alt$|^HLA-' || true)
[[ "$ALT_LEFT" == "0" ]] || die "alt/HLA contig 가 $ALT_LEFT 개 남아 있습니다."
ok "alt / HLA contig 제거 확인"

echo
echo "${C_BLD}${C_GRN}hg38_primary 설치 완료!${C_RST}"
echo "  방식       : $MODE"
echo "  경로       : $OUT_DIR"
echo "  용량       : $(du -sh "$OUT_DIR" | cut -f1)"
echo "  contig 수  : $N_FAI"
echo
# 업그레이드 스크립트가 이 단계를 감싸 호출할 때는 뒤이어 코드 패치를 알아서
# 진행하므로, 사용자에게 추가 작업이 남은 것처럼 안내하지 않는다.
if [[ "${HG38_PRIMARY_EMBEDDED:-0}" != "1" ]]; then
    echo "  다음 단계: 코드 패치를 적용하세요."
    echo "            nextflow.config 의 genomes.hg38 이 이 경로를 가리키게 됩니다."
    echo
fi
