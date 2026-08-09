#!/usr/bin/env bash
#
# Low-AF locus recheck with VarDict (diagnostic helper).
#
# Use when a known variant is missing from the pipeline VCF but may sit
# just below the default AF threshold (0.5%). Does NOT change pipeline defaults.
#
# Example (TP53 chr17:7578406 on hg19):
#   bash tools/locus_vardict_check.sh \
#     --bam results/SAMPLE/output/bam/SAMPLE_clipped_sorted.bam \
#     --ref data/refs/hg19/hg19.fa \
#     --chrom chr17 --pos 7578406 \
#     --af 0.001 \
#     --sample SAMPLE \
#     --outdir /tmp/locus_check
#
set -euo pipefail

BAM="" REF="" CHROM="" POS="" SAMPLE="sample" AF="0.001" OUTDIR="/tmp/locus_vardict_check"
VARDICT_HOME="${VARDICT_HOME:-}"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \?//'
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bam) BAM="$2"; shift 2 ;;
        --ref) REF="$2"; shift 2 ;;
        --chrom) CHROM="$2"; shift 2 ;;
        --pos) POS="$2"; shift 2 ;;
        --af) AF="$2"; shift 2 ;;
        --sample) SAMPLE="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1"; usage ;;
    esac
done

[[ -n "$BAM" && -n "$REF" && -n "$CHROM" && -n "$POS" ]] || usage
[[ -f "$BAM" ]] || { echo "BAM not found: $BAM"; exit 1; }
[[ -f "$REF" ]] || { echo "REF not found: $REF"; exit 1; }

if [[ -z "$VARDICT_HOME" ]]; then
    if [[ -d /tools/vardict/VarDict-1.8.3 ]]; then
        VARDICT_HOME=/tools/vardict/VarDict-1.8.3
    else
        echo "Set VARDICT_HOME or run inside roche_nxt_analysis container"
        exit 1
    fi
fi

mkdir -p "$OUTDIR"
# BED is 0-based half-open
START=$((POS - 1))
BED="$OUTDIR/locus.bed"
printf '%s\t%s\t%s\tLOCUS\n' "$CHROM" "$START" "$POS" > "$BED"

VD="$VARDICT_HOME/bin"
RAW="$OUTDIR/${SAMPLE}_${CHROM}_${POS}_f${AF}.raw.tsv"
BIAS="$OUTDIR/${SAMPLE}_${CHROM}_${POS}_f${AF}.bias.tsv"
VCF="$OUTDIR/${SAMPLE}_${CHROM}_${POS}_f${AF}.vcf"

echo "Running VarDict -f ${AF} on ${CHROM}:${POS}"
"$VD/VarDict" -G "$REF" -f "$AF" -N "$SAMPLE" -b "$BAM" -c 1 -S 2 -E 3 -g 4 "$BED" > "$RAW"
Rscript "$VD/teststrandbias.R" < "$RAW" > "$BIAS"
perl "$VD/var2vcf_valid.pl" -N "$SAMPLE" -E -f "$AF" < "$BIAS" > "$VCF"

echo "--- raw ---"
cat "$RAW" || true
echo "--- vcf ---"
grep -v '^#' "$VCF" || echo "(no variants)"
echo "Wrote: $VCF"
