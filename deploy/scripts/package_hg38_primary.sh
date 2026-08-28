#!/usr/bin/env bash
#
# Roche_nxt — hg38_primary USB 페이로드 생성 (개발 서버에서 실행)
#
# 완성된 refs/hg38_primary 를 tar.gz 로 묶고 sha256 을 남깁니다.
# 병원 서버에서는 install_hg38_primary.sh --mode usb 로 설치합니다.
#
# 사용법:
#   bash package_hg38_primary.sh --out /media/usb
#   bash package_hg38_primary.sh --data-dir /home/ken/roche_data --out ./dist
#
# 소요 시간: 압축 20~40분 (약 8GB → 3~4GB). CPU 코어를 모두 쓰려면 pigz 를 설치하세요.
#
set -Eeuo pipefail

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

DATA_DIR="${ROCHE_DATA_DIR:-/home/ken/roche_data}"
OUT_DIR="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --data-dir) DATA_DIR="$2"; shift 2 ;;
        --out)      OUT_DIR="$2";  shift 2 ;;
        -h|--help)  echo "Usage: $0 [--data-dir <path>] [--out <dir>]"; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

SRC="$DATA_DIR/refs/hg38_primary"
[[ -d "$SRC" ]] || die "hg38_primary 를 찾을 수 없습니다: $SRC"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

TARBALL="$OUT_DIR/hg38_primary.tar.gz"
SUMS="$OUT_DIR/hg38_primary.sha256"

h "원본 확인"
for f in ucsc.hg38.primary.fasta ucsc.hg38.primary.fasta.fai ucsc.hg38.primary.dict \
         genome_file.txt KAPA_HyperCap_DS_NHL_Panel_capture_targets_bait.interval_list; do
    [[ -s "$SRC/$f" ]] || die "필수 파일 누락: $SRC/$f"
done
for ext in amb ann bwt pac sa; do
    [[ -s "$SRC/ucsc.hg38.primary.fasta.$ext" ]] || die "BWA 인덱스 누락: .$ext"
done
N_FAI=$(wc -l < "$SRC/ucsc.hg38.primary.fasta.fai")
ALT_LEFT=$(cut -f1 "$SRC/ucsc.hg38.primary.fasta.fai" | grep -cE '_alt$|^HLA-' || true)
[[ "$ALT_LEFT" == "0" ]] || die "alt/HLA contig 가 $ALT_LEFT 개 남아 있습니다."
ok "필수 파일 확인 (contig $N_FAI, 원본 $(du -sh "$SRC" | cut -f1))"

AVAIL_KB=$(df -Pk "$OUT_DIR" | awk 'NR==2 {print $4}')
(( AVAIL_KB > 5 * 1024 * 1024 )) || die "출력 위치 여유 공간 부족: $(( AVAIL_KB / 1024 / 1024 ))GB (5GB 이상 필요)"
ok "출력 위치 여유 공간 $(( AVAIL_KB / 1024 / 1024 ))GB"

h "압축 (20~40분 소요)"
# 병원 서버에서 tar -xzf 로 refs/ 아래에 그대로 풀리도록 refs 를 기준으로 묶는다
if command -v pigz >/dev/null; then
    info "pigz 사용 (병렬 압축)"
    tar -C "$DATA_DIR/refs" -I 'pigz -1' -cf "$TARBALL" hg38_primary
else
    warn "pigz 가 없어 gzip 단일 스레드로 압축합니다. pigz 설치를 권장합니다."
    tar -C "$DATA_DIR/refs" -I 'gzip -1' -cf "$TARBALL" hg38_primary
fi
ok "압축 완료 ($(du -h "$TARBALL" | cut -f1))"

h "체크섬"
( cd "$OUT_DIR" && sha256sum "$(basename "$TARBALL")" > "$(basename "$SUMS")" )
ok "$(cat "$SUMS")"

h "복원 검증"
# 압축이 온전한지 실제로 풀어보되 디스크에 쓰지 않는다
tar -tzf "$TARBALL" > /dev/null || die "tarball 이 손상되었습니다."
N_ENTRIES=$(tar -tzf "$TARBALL" | wc -l)
ok "아카이브 정상 ($N_ENTRIES 개 항목)"

echo
echo "${C_BLD}${C_GRN}USB 페이로드 생성 완료!${C_RST}"
echo "  tarball : $TARBALL"
echo "  체크섬  : $SUMS"
echo "  크기    : $(du -h "$TARBALL" | cut -f1)"
echo
echo "  USB 에 두 파일을 함께 복사한 뒤 병원 서버에서:"
echo "    bash install_hg38_primary.sh --mode usb --payload /media/usb/hg38_primary.tar.gz"
echo
