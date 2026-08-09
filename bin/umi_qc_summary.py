#!/usr/bin/env python3
"""Summarize fgbio UMI group + ClipBam metrics into JSON/TXT for QC UI."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


def parse_group_tsv(path: Path) -> dict:
    rows = []
    with path.open() as fh:
        reader = csv.DictReader(fh, delimiter="\t")
        for row in reader:
            rows.append(
                {
                    "family_size": int(row["family_size"]),
                    "count": int(row["count"]),
                    "fraction": float(row["fraction"]),
                    "fraction_gt_or_eq_family_size": float(
                        row.get("fraction_gt_or_eq_family_size", 0) or 0
                    ),
                }
            )
    if not rows:
        return {
            "total_families": 0,
            "singleton_families": 0,
            "singleton_fraction": None,
            "mean_family_size": None,
            "median_family_size": None,
            "pct_family_ge3": None,
            "pct_family_ge5": None,
            "family_size_histogram": [],
        }

    total = sum(r["count"] for r in rows)
    weighted = sum(r["family_size"] * r["count"] for r in rows)
    singleton = next((r["count"] for r in rows if r["family_size"] == 1), 0)

    # Weighted median family size
    half = total / 2.0
    cum = 0
    median = rows[-1]["family_size"]
    for r in rows:
        cum += r["count"]
        if cum >= half:
            median = r["family_size"]
            break

    ge3 = sum(r["count"] for r in rows if r["family_size"] >= 3) / total
    ge5 = sum(r["count"] for r in rows if r["family_size"] >= 5) / total

    # Cap histogram for UI (sizes 1..20, then 21+)
    hist = []
    for fs in range(1, 21):
        c = next((r["count"] for r in rows if r["family_size"] == fs), 0)
        hist.append({"family_size": fs, "count": c})
    tail = sum(r["count"] for r in rows if r["family_size"] > 20)
    if tail:
        hist.append({"family_size": 21, "count": tail, "label": "21+"})

    return {
        "total_families": total,
        "singleton_families": singleton,
        "singleton_fraction": singleton / total,
        "mean_family_size": weighted / total,
        "median_family_size": median,
        "pct_family_ge3": ge3,
        "pct_family_ge5": ge5,
        "family_size_histogram": hist,
    }


def parse_clipov(path: Path | None) -> dict:
    if path is None or not path.is_file():
        return {}
    with path.open() as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    # Prefer Pair / All row
    row = None
    for prefer in ("Pair", "All", "ReadOne"):
        row = next((r for r in rows if r.get("read_type") == prefer), None)
        if row:
            break
    if not row and rows:
        row = rows[0]
    if not row:
        return {}

    def num(key: str) -> float | None:
        v = row.get(key, "")
        if v in ("", None):
            return None
        try:
            return float(v)
        except ValueError:
            return None

    reads = num("reads") or 0.0
    clipped_ov = num("reads_clipped_overlapping") or 0.0
    bases = num("bases") or 0.0
    bases_ov = num("bases_clipped_overlapping") or 0.0
    return {
        "reads": int(reads),
        "reads_clipped_overlapping": int(clipped_ov),
        "pct_reads_clipped_overlapping": (clipped_ov / reads) if reads else None,
        "bases": int(bases),
        "bases_clipped_overlapping": int(bases_ov),
        "pct_bases_clipped_overlapping": (bases_ov / bases) if bases else None,
    }


def pf_reads_from_alignment_metrics(path: Path | None) -> int | None:
    """Picard CollectAlignmentSummaryMetrics PAIR TOTAL_READS or PF_READS."""
    if path is None or not path.is_file():
        return None
    with path.open() as fh:
        lines = fh.readlines()
    header = None
    for line in lines:
        if line.startswith("CATEGORY"):
            header = line.rstrip("\n").split("\t")
            continue
        if header and line.startswith("PAIR"):
            cols = line.rstrip("\n").split("\t")
            data = dict(zip(header, cols))
            for key in ("PF_READS", "TOTAL_READS"):
                if key in data and data[key] not in ("", "?"):
                    try:
                        return int(float(data[key]))
                    except ValueError:
                        pass
    return None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sample-id", required=True)
    ap.add_argument("--group-tsv", required=True, type=Path)
    ap.add_argument("--clipov-metrics", type=Path, default=None)
    ap.add_argument("--alignment-aligned", type=Path, default=None)
    ap.add_argument("--alignment-deduped", type=Path, default=None)
    ap.add_argument("--out-json", required=True, type=Path)
    ap.add_argument("--out-txt", required=True, type=Path)
    args = ap.parse_args()

    group = parse_group_tsv(args.group_tsv)
    clip = parse_clipov(args.clipov_metrics)
    pf_aln = pf_reads_from_alignment_metrics(args.alignment_aligned)
    pf_ded = pf_reads_from_alignment_metrics(args.alignment_deduped)

    umi_dup = None
    if pf_aln and pf_ded and pf_aln > 0:
        umi_dup = 1.0 - (pf_ded / pf_aln)

    payload = {
        "sample_id": args.sample_id,
        "umi_families": group,
        "clipov": clip,
        "reads": {
            "pf_reads_aligned": pf_aln,
            "pf_reads_umi_deduped": pf_ded,
            "umi_duplication_rate": umi_dup,
        },
    }

    args.out_json.write_text(json.dumps(payload, indent=2) + "\n")

    def pct(x):
        return f"{100.0 * x:.2f}%" if x is not None else "NA"

    lines = [
        f"UMI QC Summary — {args.sample_id}",
        "=" * 48,
        f"Total UMI families      : {group['total_families']:,}",
        f"Singleton families      : {group['singleton_families']:,} ({pct(group['singleton_fraction'])})",
        f"Mean family size        : {group['mean_family_size']:.3f}"
        if group["mean_family_size"] is not None
        else "Mean family size        : NA",
        f"Median family size      : {group['median_family_size']}",
        f"% families size ≥ 3     : {pct(group['pct_family_ge3'])}",
        f"% families size ≥ 5     : {pct(group['pct_family_ge5'])}",
        "",
        f"PF reads (aligned)      : {pf_aln if pf_aln is not None else 'NA'}",
        f"PF reads (UMI deduped)  : {pf_ded if pf_ded is not None else 'NA'}",
        f"UMI duplication rate    : {pct(umi_dup)}",
        "",
        f"Clip overlapping reads  : {clip.get('reads_clipped_overlapping', 'NA')} / {clip.get('reads', 'NA')} ({pct(clip.get('pct_reads_clipped_overlapping'))})",
        f"Clip overlapping bases  : {clip.get('bases_clipped_overlapping', 'NA')} / {clip.get('bases', 'NA')} ({pct(clip.get('pct_bases_clipped_overlapping'))})",
        "",
    ]
    args.out_txt.write_text("\n".join(lines))


if __name__ == "__main__":
    main()
