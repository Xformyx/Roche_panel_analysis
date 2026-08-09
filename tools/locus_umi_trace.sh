#!/usr/bin/env bash
#
# Trace allele counts / VAF at one locus across UMI pipeline BAM stages.
#
# Discovers BAMs under work/<order_id>/ and results/<sample>/ by filename
# suffix — you only need order id and/or sample id + region.
#
# Requires: samtools; intermediate BAMs still present in work/ (delete_intermediate=false).
#
# Examples:
#   bash tools/locus_umi_trace.sh --order 20260805170301-0352b9 \
#       --chrom chr17 --pos 7578406 --alt T
#
#   bash tools/locus_umi_trace.sh --sample 26NHL901-02_78-260721-0002_T \
#       --region chr17:7578406 --alt T
#
#   bash tools/locus_umi_trace.sh --order 20260805170301-0352b9 \
#       --sample 26NHL901-02_78-260721-0002_T --chrom chr17 --pos 7578406
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORDER=""
SAMPLE=""
CHROM=""
POS=""
REGION=""
ALT=""
WORK_ROOT="${ROOT}/work"
RESULTS_ROOT="${ROOT}/results"

usage() {
    sed -n '2,22p' "$0" | sed 's/^# \?//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --order)   ORDER="$2"; shift 2 ;;
        --sample)  SAMPLE="$2"; shift 2 ;;
        --chrom)   CHROM="$2"; shift 2 ;;
        --pos)     POS="$2"; shift 2 ;;
        --region)  REGION="$2"; shift 2 ;;
        --alt)     ALT="$2"; shift 2 ;;
        --work)    WORK_ROOT="$2"; shift 2 ;;
        --results) RESULTS_ROOT="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1"; usage ;;
    esac
done

if [[ -n "$REGION" ]]; then
    CHROM="${REGION%%:*}"
    POS="${REGION##*:}"
    POS="${POS%%-*}"
fi

[[ -n "$CHROM" && -n "$POS" ]] || usage
[[ -n "$ORDER" || -n "$SAMPLE" ]] || {
    echo "Need --order and/or --sample"
    usage
}

REGION_1="${CHROM}:${POS}-${POS}"
ALT_U=$(printf '%s' "$ALT" | tr '[:lower:]' '[:upper:]')

# Stages that normally support indexed region queries (coordinate / published).
# queryname / unmapped stages are listed but usually skipped with a note.
STAGES=(
    "aligned_sorted|1st BWA (coord)|yes"
    "sorted_rmdups|QC MarkDuplicates|yes"
    "merged|MergeBamAlignment (QN)|no"
    "umi_grouped|GroupReadsByUmi (QN)|no"
    "consensus_unmapped|CallMolecularConsensus|no"
    "consensus_filtered|FilterConsensusReads|no"
    "consensus_mapped|2nd BWA|maybe"
    "umi_deduped_sorted|Merge consensus (coord)|yes"
    "clipped|ClipBam|maybe"
    "clipped_sorted|Final calling BAM|yes"
)

# Newest match under search roots
find_bam() {
    local suffix="$1"
    local roots=()
    [[ -n "$ORDER" && -d "${WORK_ROOT}/${ORDER}" ]] && roots+=("${WORK_ROOT}/${ORDER}")
    [[ -n "$SAMPLE" && -d "${RESULTS_ROOT}/${SAMPLE}" ]] && roots+=("${RESULTS_ROOT}/${SAMPLE}")
    # sample-only: scan all work dirs (can be slow on huge work trees)
    if [[ -z "$ORDER" && -n "$SAMPLE" && -d "$WORK_ROOT" ]]; then
        roots+=("$WORK_ROOT")
    fi
    [[ ${#roots[@]} -eq 0 ]] && return 1

    local pattern
    if [[ -n "$SAMPLE" ]]; then
        pattern="${SAMPLE}_${suffix}.bam"
    else
        pattern="*_${suffix}.bam"
    fi

    local hit
    hit=$(find "${roots[@]}" -type f -name "$pattern" 2>/dev/null \
        | xargs -r ls -t 2>/dev/null | head -1 || true)
    [[ -n "$hit" ]] || return 1
    printf '%s' "$hit"
}

# Infer sample from order work dir when --sample omitted
if [[ -z "$SAMPLE" && -n "$ORDER" ]]; then
    SAMPLE=$(find "${WORK_ROOT}/${ORDER}" -type f -name '*_clipped_sorted.bam' 2>/dev/null \
        | head -1 | xargs -r basename | sed 's/_clipped_sorted\.bam$//' || true)
    if [[ -z "$SAMPLE" ]]; then
        SAMPLE=$(find "${WORK_ROOT}/${ORDER}" -type f -name '*_umi_deduped_sorted.bam' 2>/dev/null \
            | head -1 | xargs -r basename | sed 's/_umi_deduped_sorted\.bam$//' || true)
    fi
    [[ -n "$SAMPLE" ]] || {
        echo "Could not infer sample from work/${ORDER}"
        exit 1
    }
fi

echo "Sample : ${SAMPLE}"
[[ -n "$ORDER" ]] && echo "Order  : ${ORDER}"
echo "Locus  : ${REGION_1}"
[[ -n "$ALT_U" ]] && echo "ALT    : ${ALT_U}"
echo

printf '%-22s %-8s %-6s %-6s %-6s %-6s %-8s %-8s %s\n' \
    "STAGE" "DEPTH" "A" "T" "G" "C" "ALT_N" "VAF%" "BAM"
printf '%s\n' "--------------------------------------------------------------------------------------------------------------"

count_bases() {
    local bam="$1"
    # -Q0 -A: raw base counts (diagnostic)
    samtools mpileup -Q0 -A -r "$REGION_1" "$bam" 2>/dev/null | awk -v ALT="$ALT_U" '
        NF < 5 { next }
        {
            s = toupper($5)
            gsub(/[^ACGT]/, "", s)
            a = gsub(/A/, "", s); c = gsub(/C/, "", s)
            g = gsub(/G/, "", s); t = gsub(/T/, "", s)
            depth = a + t + g + c
            alt_n = 0
            if (ALT == "A") alt_n = a
            else if (ALT == "T") alt_n = t
            else if (ALT == "G") alt_n = g
            else if (ALT == "C") alt_n = c
            vaf = (depth > 0 && ALT != "") ? sprintf("%.4f", 100.0 * alt_n / depth) : "NA"
            printf "%d %d %d %d %d %d %s\n", depth, a, t, g, c, alt_n, vaf
            found = 1
        }
        END { if (!found) print "0 0 0 0 0 0 NA" }
    '
}

for entry in "${STAGES[@]}"; do
    IFS='|' read -r suffix label regionable <<<"$entry"
    bam=$(find_bam "$suffix" || true)
    if [[ -z "${bam:-}" ]]; then
        printf '%-22s %-8s %-6s %-6s %-6s %-6s %-8s %-8s %s\n' \
            "$suffix" "-" "-" "-" "-" "-" "-" "-" "MISSING"
        continue
    fi

    # Prefer indexed BAMs for -r; otherwise try and report empty
    if [[ "$regionable" == "no" ]]; then
        printf '%-22s %-8s %-6s %-6s %-6s %-6s %-8s %-8s %s\n' \
            "$suffix" "-" "-" "-" "-" "-" "-" "-" "SKIP(qn/unmapped) $(basename "$bam")"
        continue
    fi

    read -r depth a t g c alt_n vaf <<<"$(count_bases "$bam")"
    printf '%-22s %-8s %-6s %-6s %-6s %-6s %-8s %-8s %s\n' \
        "$suffix" "$depth" "$a" "$t" "$g" "$c" "$alt_n" "$vaf" "$(basename "$bam")"
done

echo
echo "Notes:"
echo "  - MISSING: not under work/${ORDER:-*} or results/${SAMPLE} (re-run with delete_intermediate=false)."
echo "  - SKIP(qn/unmapped): queryname/unmapped BAM — region pileup needs coordinate+index."
echo "  - VAF% uses --alt / depth; omit --alt to leave VAF as NA."
echo "  - For ALT-read RX/family collapse, extend with a locus family tracer (next step)."
