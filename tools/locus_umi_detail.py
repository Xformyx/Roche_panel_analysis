#!/usr/bin/env python3
"""
Locus-level UMI detail: stage AF + per-family REF/ALT at one variant position.

Discovers BAMs under work/<order>/ and results/<sample>/ from --order / --sample.
Needs intermediate BAMs (delete_intermediate=false) for pre-consensus family view.

Examples:
  python3 tools/locus_umi_detail.py \\
      --order 20260805170301-0352b9 \\
      --chrom chr17 --pos 7578406 --alt T

  python3 tools/locus_umi_detail.py \\
      --sample 26NHL901-02_78-260721-0002_T \\
      --region chr17:7578406 --alt T --ref C \\
      --outdir /tmp/locus_umi_detail
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# suffix -> (label, prefer_index)
STAGES = [
    ("aligned_sorted", "1st BWA coord", True),
    ("sorted_rmdups", "QC MarkDuplicates", True),
    ("umi_grouped", "GroupReadsByUmi (pre-consensus)", False),
    ("umi_deduped_sorted", "UMI consensus coord", True),
    ("clipped_sorted", "Final calling BAM", True),
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--order", default="")
    p.add_argument("--sample", default="")
    p.add_argument("--chrom", default="")
    p.add_argument("--pos", type=int, default=0)
    p.add_argument("--region", default="", help="chr:pos or chr:pos-pos")
    p.add_argument("--alt", default="", help="ALT allele for VAF / family classification")
    p.add_argument("--ref", default="", help="optional REF allele (else majority non-ALT)")
    p.add_argument("--min-mapq", type=int, default=20)
    p.add_argument("--work", type=Path, default=ROOT / "work")
    p.add_argument("--results", type=Path, default=ROOT / "results")
    p.add_argument("--outdir", type=Path, default=None, help="write TSV summaries")
    p.add_argument("--max-families-print", type=int, default=40)
    return p.parse_args()


def resolve_locus(args: argparse.Namespace) -> tuple[str, int]:
    chrom, pos = args.chrom, args.pos
    if args.region:
        m = re.match(r"^([^:]+):(\d+)(?:-(\d+))?$", args.region)
        if not m:
            sys.exit(f"Bad --region: {args.region}")
        chrom = m.group(1)
        pos = int(m.group(2))
    if not chrom or not pos:
        sys.exit("Need --chrom/--pos or --region")
    return chrom, pos


def find_newest(paths: list[Path]) -> Path | None:
    existing = [p for p in paths if p.is_file()]
    if not existing:
        return None
    return max(existing, key=lambda p: p.stat().st_mtime)


def discover_sample(order: str, work: Path) -> str:
    order_dir = work / order
    if not order_dir.is_dir():
        sys.exit(f"work order dir not found: {order_dir}")
    for suf in ("_clipped_sorted.bam", "_umi_deduped_sorted.bam", "_umi_grouped.bam"):
        hits = sorted(order_dir.rglob(f"*{suf}"))
        if hits:
            return hits[0].name[: -len(suf)]
    sys.exit(f"Could not infer sample from {order_dir}")


def find_bam(sample: str, suffix: str, order: str, work: Path, results: Path) -> Path | None:
    name = f"{sample}_{suffix}.bam"
    candidates: list[Path] = []
    if order:
        odir = work / order
        if odir.is_dir():
            candidates.extend(odir.rglob(name))
    rdir = results / sample
    if rdir.is_dir():
        candidates.extend(rdir.rglob(name))
    if not order and work.is_dir():
        # narrower: only top-level order dirs, still can be heavy
        for child in work.iterdir():
            if child.is_dir() and not child.name.startswith("."):
                candidates.extend(child.rglob(name))
    return find_newest(candidates)


def has_index(bam: Path) -> bool:
    return (bam.parent / (bam.name + ".bai")).is_file() or Path(str(bam) + ".bai").is_file() or Path(str(bam).replace(".bam", ".bai")).is_file()


def base_at_ref(pos0: int, cigar: str, seq: str, ref_pos_1based: int) -> str | None:
    """Return read base covering 1-based ref position, or None if deleted/softclipped past."""
    if not cigar or cigar == "*" or not seq or seq == "*":
        return None
    ref_pos = pos0  # 0-based current ref
    qpos = 0
    target = ref_pos_1based - 1
    # groups: (length, op) — e.g. ("145", "M")
    for length_s, op in re.findall(r"(\d+)([MIDNSHP=X])", cigar):
        n = int(length_s)
        if op in ("M", "=", "X"):
            if ref_pos <= target < ref_pos + n:
                return seq[qpos + (target - ref_pos)].upper()
            ref_pos += n
            qpos += n
        elif op == "I":
            qpos += n
        elif op == "D":
            if ref_pos <= target < ref_pos + n:
                return "-"  # deletion spanning site
            ref_pos += n
        elif op == "N":
            if ref_pos <= target < ref_pos + n:
                return None
            ref_pos += n
        elif op == "S":
            qpos += n
        elif op == "H":
            pass
        elif op == "P":
            pass
    return None


def parse_tags(tag_fields: list[str]) -> dict[str, str]:
    tags = {}
    for t in tag_fields:
        if ":" not in t:
            continue
        parts = t.split(":", 2)
        if len(parts) >= 3:
            tags[parts[0]] = parts[2]
    return tags


def iter_locus_reads(
    bam: Path,
    chrom: str,
    pos: int,
    min_mapq: int,
    use_region: bool,
) -> list[dict]:
    """Return dicts: base, mapq, rx, mi, cd, flag, qname."""
    cmd = ["samtools", "view", "-F", "0x904"]  # unmapped, secondary, supplementary off
    if use_region and has_index(bam):
        cmd += [str(bam), f"{chrom}:{pos}-{pos}"]
    else:
        cmd += [str(bam)]

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    out: list[dict] = []
    assert proc.stdout is not None
    for line in proc.stdout:
        fields = line.rstrip("\n").split("\t")
        if len(fields) < 11:
            continue
        rname = fields[2]
        if rname != chrom:
            continue
        try:
            rpos = int(fields[3])
            mapq = int(fields[4])
            flag = int(fields[1])
        except ValueError:
            continue
        if mapq < min_mapq:
            continue
        cigar = fields[5]
        seq = fields[9]
        # quick window: alignment start beyond pos and no chance — still need CIGAR for long reads
        # skip if start > pos and not covering (cheap reject when start way past)
        if rpos > pos:
            continue
        base = base_at_ref(rpos - 1, cigar, seq, pos)
        if base is None:
            continue
        tags = parse_tags(fields[11:])
        out.append(
            {
                "qname": fields[0],
                "flag": flag,
                "base": base,
                "mapq": mapq,
                "rx": tags.get("RX", ""),
                "mi": tags.get("MI", ""),
                "cd": tags.get("cD", tags.get("cd", "")),
                "tags": tags,
            }
        )
    proc.wait()
    return out


def pileup_counts(reads: list[dict]) -> Counter:
    return Counter(r["base"] for r in reads if r["base"] in "ACGT")


def family_key(r: dict) -> str:
    if r["mi"]:
        return f"MI:{r['mi']}"
    if r["rx"]:
        return f"RX:{r['rx']}"
    return f"QNAME:{r['qname']}"


def summarize_families(reads: list[dict], alt: str, ref: str) -> list[dict]:
    fam: dict[str, Counter] = defaultdict(Counter)
    fam_meta: dict[str, dict] = {}
    for r in reads:
        if r["base"] not in "ACGT-":
            continue
        k = family_key(r)
        fam[k][r["base"]] += 1
        meta = fam_meta.setdefault(k, {"rx": r["rx"], "mi": r["mi"], "cd": r["cd"]})
        if r["cd"] and not meta["cd"]:
            meta["cd"] = r["cd"]

    rows = []
    for k, ctr in fam.items():
        total = sum(ctr[b] for b in "ACGT")
        alt_n = ctr[alt] if alt else 0
        if ref:
            ref_n = ctr[ref]
        else:
            # majority among non-alt
            ref_n = max((ctr[b] for b in "ACGT" if b != alt), default=0)
        call = alt if alt and alt_n > ref_n else (ref if ref and ref_n >= alt_n else (ctr.most_common(1)[0][0] if ctr else "?"))
        if alt and alt_n == ref_n and alt_n > 0:
            call = "het/tie"
        rows.append(
            {
                "family": k,
                "rx": fam_meta[k]["rx"],
                "mi": fam_meta[k]["mi"],
                "cd": fam_meta[k]["cd"],
                "n_reads": total,
                "A": ctr["A"],
                "C": ctr["C"],
                "G": ctr["G"],
                "T": ctr["T"],
                "alt_n": alt_n,
                "ref_n": ref_n,
                "family_call": call,
                "alt_frac": (alt_n / total) if total else 0.0,
            }
        )
    rows.sort(key=lambda r: (-r["alt_n"], -r["n_reads"], r["family"]))
    return rows


def print_stage_table(rows: list[tuple]) -> None:
    hdr = f"{'STAGE':<22} {'DEPTH':>7} {'A':>6} {'T':>6} {'G':>6} {'C':>6} {'ALT':>6} {'VAF%':>8}  BAM"
    print(hdr)
    print("-" * len(hdr))
    for stage, depth, a, t, g, c, alt_n, vaf, bam in rows:
        print(f"{stage:<22} {depth:>7} {a:>6} {t:>6} {g:>6} {c:>6} {alt_n:>6} {vaf:>8}  {bam}")


def main() -> None:
    args = parse_args()
    chrom, pos = resolve_locus(args)
    alt = args.alt.upper()
    ref = args.ref.upper()
    if alt and alt not in "ACGT":
        sys.exit("--alt must be A/C/G/T")
    if ref and ref not in "ACGT":
        sys.exit("--ref must be A/C/G/T")

    sample = args.sample
    order = args.order
    if not sample and not order:
        sys.exit("Need --order and/or --sample")
    if not sample:
        sample = discover_sample(order, args.work)

    print(f"Sample : {sample}")
    if order:
        print(f"Order  : {order}")
    print(f"Locus  : {chrom}:{pos}")
    if alt:
        print(f"ALT    : {alt}" + (f"  REF: {ref}" if ref else ""))
    print(f"MAPQ  >= {args.min_mapq}")
    print()

    stage_rows = []
    stage_reads: dict[str, list[dict]] = {}

    for suffix, label, prefer_idx in STAGES:
        bam = find_bam(sample, suffix, order, args.work, args.results)
        if bam is None:
            stage_rows.append((suffix, "-", "-", "-", "-", "-", "-", "-", "MISSING"))
            continue
        use_region = prefer_idx and has_index(bam)
        print(f"[scan] {suffix}: {bam} ({'region' if use_region else 'stream'})", file=sys.stderr)
        reads = iter_locus_reads(bam, chrom, pos, args.min_mapq, use_region=use_region or has_index(bam))
        stage_reads[suffix] = reads
        ctr = pileup_counts(reads)
        depth = sum(ctr.values())
        alt_n = ctr[alt] if alt else 0
        vaf = f"{100.0 * alt_n / depth:.4f}" if depth and alt else "NA"
        stage_rows.append(
            (
                suffix,
                depth,
                ctr["A"],
                ctr["T"],
                ctr["G"],
                ctr["C"],
                alt_n if alt else 0,
                vaf,
                bam.name,
            )
        )

    print("=== Stage allele counts ===")
    print_stage_table(stage_rows)
    print()

    # Pre-consensus families
    pre = stage_reads.get("umi_grouped") or []
    if pre:
        fams = summarize_families(pre, alt, ref)
        alt_fams = [f for f in fams if alt and f["alt_n"] > 0]
        ref_only = [f for f in fams if alt and f["alt_n"] == 0 and f["n_reads"] > 0]
        print("=== Pre-consensus families (umi_grouped) covering locus ===")
        print(f"Families at locus : {len(fams)}")
        if alt:
            print(f"Families with ALT : {len(alt_fams)}")
            print(f"Families REF-only : {len(ref_only)}")
            print(
                f"ALT raw reads     : {sum(f['alt_n'] for f in alt_fams)}  "
                f"in families (size min/med/max): "
                f"{min((f['n_reads'] for f in alt_fams), default=0)}/"
                f"{sorted(f['n_reads'] for f in alt_fams)[len(alt_fams)//2] if alt_fams else 0}/"
                f"{max((f['n_reads'] for f in alt_fams), default=0)}"
            )
        print()
        print(
            f"{'FAMILY':<28} {'N':>4} {'A':>4} {'C':>4} {'G':>4} {'T':>4} "
            f"{'ALT':>4} {'CALL':<8} {'ALT_FRAC':>8} RX/MI"
        )
        print("-" * 100)
        show = alt_fams if alt else fams
        for f in show[: args.max_families_print]:
            print(
                f"{f['family'][:28]:<28} {f['n_reads']:>4} {f['A']:>4} {f['C']:>4} "
                f"{f['G']:>4} {f['T']:>4} {f['alt_n']:>4} {f['family_call']:<8} "
                f"{f['alt_frac']:>8.3f} {f['rx'] or f['mi']}"
            )
        if len(show) > args.max_families_print:
            print(f"... ({len(show) - args.max_families_print} more)")
        print()
    else:
        print("=== Pre-consensus families ===")
        print("umi_grouped.bam MISSING — re-run with intermediates kept.\n")

    # Post-consensus
    for suffix, title in (
        ("umi_deduped_sorted", "Post-consensus (umi_deduped_sorted)"),
        ("clipped_sorted", "Final (clipped_sorted)"),
    ):
        reads = stage_reads.get(suffix) or []
        if not reads:
            print(f"=== {title} ===\nMISSING or no covering reads\n")
            continue
        fams = summarize_families(reads, alt, ref)
        alt_fams = [f for f in fams if alt and f["alt_n"] > 0]
        print(f"=== {title} ===")
        print(f"Consensus molecules at locus : {len(fams)}")
        if alt:
            print(f"ALT-supporting molecules     : {len(alt_fams)}")
        print(
            f"{'FAMILY':<28} {'N':>4} {'A':>4} {'C':>4} {'G':>4} {'T':>4} "
            f"{'ALT':>4} {'cD':>6} {'CALL':<8} RX"
        )
        print("-" * 100)
        show = alt_fams if alt else fams
        for f in show[: args.max_families_print]:
            print(
                f"{f['family'][:28]:<28} {f['n_reads']:>4} {f['A']:>4} {f['C']:>4} "
                f"{f['G']:>4} {f['T']:>4} {f['alt_n']:>4} {str(f['cd'])[:6]:>6} "
                f"{f['family_call']:<8} {f['rx']}"
            )
        if len(show) > args.max_families_print:
            print(f"... ({len(show) - args.max_families_print} more)")
        print()

    # Survival: pre ALT RX/MI vs post
    if alt and pre and stage_reads.get("umi_deduped_sorted"):
        pre_alt_rx = {f["rx"] or f["mi"] for f in summarize_families(pre, alt, ref) if f["alt_n"] > 0}
        post_fams = summarize_families(stage_reads["umi_deduped_sorted"], alt, ref)
        post_alt = {f["rx"] or f["mi"] for f in post_fams if f["alt_n"] > 0}
        post_all = {f["rx"] or f["mi"] for f in post_fams}
        survived = pre_alt_rx & post_alt
        lost = pre_alt_rx - post_all
        flipped = (pre_alt_rx & post_all) - post_alt
        print("=== ALT family survival (pre umi_grouped → umi_deduped) ===")
        print(f"Pre ALT families     : {len(pre_alt_rx)}")
        print(f"Survived as ALT      : {len(survived)}")
        print(f"Present but not ALT  : {len(flipped)}  (consensus flipped to REF/other)")
        print(f"Absent after consensus: {len(lost)}  (filtered / failed min-reads / not mapped)")
        if lost:
            print("Lost examples:", ", ".join(sorted(list(lost))[:15]))
        if flipped:
            print("Flipped examples:", ", ".join(sorted(list(flipped))[:15]))
        print()

    if args.outdir:
        args.outdir.mkdir(parents=True, exist_ok=True)
        stage_path = args.outdir / f"{sample}_{chrom}_{pos}_stages.tsv"
        with stage_path.open("w", newline="") as fh:
            w = csv.writer(fh, delimiter="\t")
            w.writerow(["stage", "depth", "A", "T", "G", "C", "alt_n", "vaf_pct", "bam"])
            for row in stage_rows:
                w.writerow(row)
        if pre:
            fam_path = args.outdir / f"{sample}_{chrom}_{pos}_pre_families.tsv"
            with fam_path.open("w", newline="") as fh:
                fields = [
                    "family", "rx", "mi", "n_reads", "A", "C", "G", "T",
                    "alt_n", "ref_n", "family_call", "alt_frac",
                ]
                w = csv.DictWriter(fh, fieldnames=fields, delimiter="\t", extrasaction="ignore")
                w.writeheader()
                for f in summarize_families(pre, alt, ref):
                    w.writerow(f)
            print(f"Wrote {stage_path}")
            print(f"Wrote {fam_path}")


if __name__ == "__main__":
    main()
