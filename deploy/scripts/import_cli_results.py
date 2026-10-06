#!/usr/bin/env python3
"""Register CLI Nextflow results as completed Web UI orders.

CLI runs write ``results/<sample_id>/`` and do not insert a row in
``log/orders_nxt.db``. The UI lists only that table, and already opens
``results/<sample_name>/`` when ``results/<order_id>/<sample_name>/`` is
absent. This script adds one completed order per sample directory so the
existing QC report and VCF show up. It does not copy or move result files.

Skip a sample when an order with that sample_name already exists.
Patient, chart, and diagnosis fields are left empty. Longitudinal links
are not inferred.

    python3 deploy/scripts/import_cli_results.py /opt/roche_nxt --dry-run

The argument is the existing install directory. Results are read from
``<install>/results`` and orders are written to ``<install>/log/orders_nxt.db``.
"""
import argparse
import csv
import datetime
import glob
import os
import re
import sqlite3
import uuid

ORDER_ID_RE = re.compile(r"^\d{14}-[0-9a-f]{6}$")
FASTA_RE = re.compile(r"(ucsc\.hg38\.primary\.fasta|ucsc\.hg38\.fasta|hg19\.fa)\b")
KNOWN_CONTIGS = {
    "ucsc.hg38.primary.fasta": 2580,
    "ucsc.hg38.fasta": 3366,
    "hg19.fa": 93,
}
SKIP_DIRS = {"pipeline_info", "work", ".nextflow"}


def _read_text(path, limit=2_000_000):
    try:
        with open(path, errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def _tsv_value(path, key):
    try:
        with open(path, errors="replace") as fh:
            for line in fh:
                name, _, val = line.rstrip("\n").partition("\t")
                if name == key and val.strip():
                    return val.strip()
    except OSError:
        pass
    return ""


def _is_result_dir(path):
    return any(os.path.isdir(os.path.join(path, name)) for name in ("QC_report", "output", "expression_plots"))


def _is_ui_order_tree(path, name):
    """results/<order_id>/<sample>/ is already owned by a UI order."""
    if not ORDER_ID_RE.match(name):
        return False
    try:
        children = os.listdir(path)
    except OSError:
        return False
    for child in children:
        if _is_result_dir(os.path.join(path, child)):
            return True
    return False


def iter_cli_samples(results_dir):
    try:
        names = sorted(os.listdir(results_dir))
    except OSError as exc:
        raise SystemExit(f"results 디렉터리를 읽을 수 없습니다: {results_dir} ({exc})")
    for name in names:
        if name in SKIP_DIRS or name.startswith("."):
            continue
        path = os.path.join(results_dir, name)
        if not os.path.isdir(path):
            continue
        if _is_ui_order_tree(path, name):
            continue
        if not _is_result_dir(path):
            continue
        yield name, path


def _report_texts(sample_dir, results_dir):
    paths = [
        os.path.join(sample_dir, "pipeline_info", "report.html"),
        os.path.join(results_dir, "pipeline_info", "report.html"),
    ]
    return [text for text in (_read_text(p) for p in paths) if text]


def _flag(text, name):
    match = re.search(r"--%s(?:\s+|=)(\S+)" % re.escape(name), text)
    return match.group(1) if match else ""


def _bed_rel(path):
    """Store the BED path the UI can prefix with /work_nxt_bed/."""
    if not path:
        return ""
    path = path.strip("'\"")
    for prefix in ("/work_nxt_bed/",):
        if path.startswith(prefix):
            return path[len(prefix):]
    marker = "/bed/"
    idx = path.find(marker)
    if idx >= 0:
        return path[idx + len(marker):]
    if not path.startswith("/"):
        return path
    return ""


def _reference_from_fasta(name):
    if name == "hg19.fa":
        return "hg19"
    if name in ("ucsc.hg38.primary.fasta", "ucsc.hg38.fasta"):
        return "hg38"
    return ""


def describe_sample(sample, sample_dir, results_dir):
    qc_dir = os.path.join(sample_dir, "QC_report")
    build = _tsv_value(os.path.join(qc_dir, f"{sample}_reference_build.txt"), "build_tag")
    label = _tsv_value(os.path.join(qc_dir, f"{sample}_reference_build.txt"), "reference_label")
    reports = _report_texts(sample_dir, results_dir)
    command = ""
    for text in reports:
        match = re.search(r"nextflow run .*", text)
        if match:
            command = match.group(0)
            break
    if not label:
        label = _flag(command, "reference")
    if label not in ("hg38", "hg19"):
        label = ""
    if not build:
        for text in reports:
            found = FASTA_RE.search(text)
            if not found:
                continue
            fasta = found.group(1)
            contigs = KNOWN_CONTIGS.get(fasta)
            build = f"{fasta}:{contigs}" if contigs else fasta
            if not label:
                label = _reference_from_fasta(fasta)
            break
    af = _flag(command, "af_threshold")
    try:
        af_value = float(af) if af else 0.005
    except ValueError:
        af_value = 0.005
    umi_flag = _flag(command, "use_umi").lower()
    if umi_flag in ("true", "y"):
        use_umi = "Y"
    elif umi_flag in ("false", "n"):
        use_umi = "N"
    elif glob.glob(os.path.join(qc_dir, "*umi_deduped*")):
        use_umi = "Y"
    else:
        use_umi = ""
    panel = "exome"
    if os.path.isdir(os.path.join(sample_dir, "expression_plots")) or os.path.isdir(os.path.join(sample_dir, "featureCounts")):
        panel = "rna"
    return {
        "reference": label or "hg38",
        "reference_known": bool(label),
        "reference_build": build,
        "af_threshold": af_value,
        "use_umi": use_umi,
        "panel_type": panel,
        "bed_file": _bed_rel(_flag(command, "target_bed")),
        "bed_primary_file": _bed_rel(_flag(command, "primary_bed")),
        "bed_bait_file": _bed_rel(_flag(command, "bait_intervals")),
    }


def load_samplesheets(directories):
    """sample_id -> (r1, r2). Later files do not replace an earlier hit."""
    found = {}
    for directory in directories:
        if not directory or not os.path.isdir(directory):
            continue
        for path in sorted(glob.glob(os.path.join(directory, "**", "*.csv"), recursive=True)):
            try:
                with open(path, newline="", errors="replace") as fh:
                    reader = csv.DictReader(fh)
                    if not reader.fieldnames:
                        continue
                    fields = {name.strip(): name for name in reader.fieldnames if name}
                    if "sample_id" not in fields or "fastq_1" not in fields or "fastq_2" not in fields:
                        continue
                    for row in reader:
                        sample = (row.get(fields["sample_id"]) or "").strip()
                        r1 = (row.get(fields["fastq_1"]) or "").strip()
                        r2 = (row.get(fields["fastq_2"]) or "").strip()
                        if sample and r1 and r2 and sample not in found:
                            found[sample] = (r1, r2)
            except OSError:
                continue
    return found


def _ensure_column(conn, name, typedef):
    cols = {row[1] for row in conn.execute("PRAGMA table_info(orders)")}
    if name not in cols:
        conn.execute(f"ALTER TABLE orders ADD COLUMN {name} {typedef}")


def _new_id(when, conn):
    stamp = when.strftime("%Y%m%d%H%M%S")
    for _ in range(5):
        order_id = stamp + "-" + uuid.uuid4().hex[:6]
        row = conn.execute("SELECT 1 FROM orders WHERE id=?", (order_id,)).fetchone()
        if row is None:
            return order_id
    raise SystemExit("오더 ID를 만들지 못했습니다.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("install_dir", help="기존 설치 디렉터리. results/ 와 log/orders_nxt.db 가 이 아래에 있어야 합니다.")
    parser.add_argument("--results", default=None, help="결과 루트. 기본값은 <install_dir>/results")
    parser.add_argument("--db", default=None, help="orders DB. 기본값은 <install_dir>/log/orders_nxt.db")
    parser.add_argument("--samplesheets", action="append", default=[], help="샘플시트 디렉터리. 여러 번 지정할 수 있습니다.")
    parser.add_argument("--dry-run", action="store_true", help="DB에 쓰지 않고 대상만 출력합니다.")
    args = parser.parse_args()

    install_dir = os.path.abspath(args.install_dir)
    if not os.path.isdir(install_dir):
        raise SystemExit(f"설치 디렉터리가 없습니다: {install_dir}")
    results_dir = os.path.abspath(args.results or os.path.join(install_dir, "results"))
    db_path = os.path.abspath(args.db or os.path.join(install_dir, "log", "orders_nxt.db"))

    if not os.path.isdir(results_dir):
        raise SystemExit(f"results 디렉터리가 없습니다: {results_dir}")
    if not os.path.isfile(db_path):
        raise SystemExit(f"orders DB가 없습니다. UI를 한 번 실행한 뒤 다시 실행하세요: {db_path}")

    sheet_dirs = list(args.samplesheets)
    default_sheets = os.path.join(install_dir, "log", "samplesheets")
    if default_sheets not in sheet_dirs:
        sheet_dirs.append(default_sheets)
    fastqs = load_samplesheets(sheet_dirs)

    conn = sqlite3.connect(db_path)
    try:
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        if "orders" not in tables:
            raise SystemExit(f"orders 테이블이 없습니다: {db_path}")
        _ensure_column(conn, "reference_build", "TEXT DEFAULT ''")
        _ensure_column(conn, "use_umi", "TEXT DEFAULT ''")
        _ensure_column(conn, "panel_type", "TEXT DEFAULT 'exome'")
        _ensure_column(conn, "bed_primary_file", "TEXT DEFAULT ''")
        _ensure_column(conn, "bed_bait_file", "TEXT DEFAULT ''")
        existing = {
            row[0]
            for row in conn.execute("SELECT sample_name FROM orders")
            if row[0]
        }
        inserted = 0
        skipped = 0
        for sample, path in iter_cli_samples(results_dir):
            if sample in existing:
                print(f"SKIP  {sample}  (이미 오더가 있음)")
                skipped += 1
                continue
            info = describe_sample(sample, path, results_dir)
            r1, r2 = fastqs.get(sample, ("", ""))
            mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path))
            now = datetime.datetime.now().isoformat(timespec="seconds")
            completed = mtime.isoformat(timespec="seconds")
            order_id = _new_id(mtime, conn)
            ref_note = "" if info["reference_known"] else "  reference는 결과에서 확인하지 못해 hg38로 기록"
            fastq_note = "" if r1 else "  FASTQ 경로 없음"
            print(
                f"ADD   {sample}  id={order_id}  {info['reference']}"
                f"  build={info['reference_build'] or '-'}  panel={info['panel_type']}"
                f"{ref_note}{fastq_note}"
            )
            if args.dry_run:
                inserted += 1
                existing.add(sample)
                continue
            conn.execute(
                """
                INSERT INTO orders (
                    id, order_name, patient_name, patient_dob, chart_number,
                    department, doctor_name, diagnosis, doctor_comment,
                    sample_name, r1_fastq, r2_fastq, reference, profile,
                    af_threshold, bed_file, bed_primary_file, bed_bait_file, delete_intermediate,
                    order_type, baseline_order_id, germline_order_id, followup_order_ids,
                    status, error_message, created_at, updated_at, started_at, completed_at,
                    created_by_user_id, analysis_by_user_id, use_umi, panel_type, reference_build
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """,
                (
                    order_id, sample, "", "", "",
                    "", "", "", "CLI 결과에서 가져옴",
                    sample, r1, r2, info["reference"], "docker",
                    info["af_threshold"], info["bed_file"], info["bed_primary_file"], info["bed_bait_file"], "N",
                    "baseline", "", "", "",
                    "completed", "", completed, now, completed, completed,
                    "cli-migration", "", info["use_umi"], info["panel_type"], info["reference_build"],
                ),
            )
            existing.add(sample)
            inserted += 1
        if not args.dry_run:
            conn.commit()
    finally:
        conn.close()

    mode = "미리보기" if args.dry_run else "등록"
    print(f"{mode}: {inserted}건, 건너뜀: {skipped}건")


if __name__ == "__main__":
    main()
