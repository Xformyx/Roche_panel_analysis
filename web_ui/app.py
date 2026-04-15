"""
Roche_nxt Web UI - Nextflow Pipeline Manager
Order-based workflow with Dashboard, Orders, and Setup.
"""

import os
import re
import json
import glob
import uuid
import csv
import sqlite3
import subprocess
import time
import psutil
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_file, g

app = Flask(__name__)
# Host-mounted templates (docker) must be picked up without restarting the process
app.config["TEMPLATES_AUTO_RELOAD"] = True

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
BASE_DIR = os.environ.get("ROCHE_NXT_DIR", "/roche_nxt")
DATA_DIR = os.path.join(BASE_DIR, "data")
FASTQ_DIR = os.path.join(BASE_DIR, "fastq")
FASTQ_SOURCE_DIR = "/fastq_source"
FASTQ_HOST_DIR = os.environ.get("FASTQ_HOST_DIR", "")
BED_SOURCE_DIR = "/bed_source"
BED_HOST_DIR = os.environ.get("BED_HOST_DIR", "")
RESULTS_DIR = os.path.join(BASE_DIR, "results")
LOG_DIR = os.path.join(BASE_DIR, "log")
DB_FILE = os.path.join(BASE_DIR, "log", "orders_nxt.db")

HOST_DIR = os.environ.get("HOST_DIR", "/home/ken/Roche_nxt")
ANALYSIS_IMAGE = os.environ.get("ANALYSIS_IMAGE", "roche_nxt_analysis:latest")
ENABLE_LONGITUDINAL = os.environ.get("ENABLE_LONGITUDINAL", "false").lower() in ("true", "1", "yes")

# ---------------------------------------------------------------------------
# Resource limits  (0 = auto-detect)
# ---------------------------------------------------------------------------
ESTIMATED_CPUS_PER_SAMPLE = 20
ESTIMATED_MEM_GB_PER_SAMPLE = 30

def detect_system_resources():
    """Return (total_cpus, total_memory_gb) of the host."""
    cpus = psutil.cpu_count(logical=True) or 4
    mem_gb = int(psutil.virtual_memory().total / (1024 ** 3))
    return cpus, mem_gb


def get_resource_limits():
    """Resolve effective max_cpus, max_memory, max_concurrent from env/settings/auto."""
    env_cpus = int(os.environ.get("MAX_CPUS", "0"))
    env_mem = int(os.environ.get("MAX_MEMORY", "0"))
    env_conc = int(os.environ.get("MAX_CONCURRENT_SAMPLES", "0"))

    sys_cpus, sys_mem = detect_system_resources()

    max_cpus = env_cpus if env_cpus > 0 else sys_cpus
    max_mem = env_mem if env_mem > 0 else sys_mem

    if env_conc > 0:
        max_conc = env_conc
    else:
        conc_by_cpu = max(1, max_cpus // ESTIMATED_CPUS_PER_SAMPLE)
        conc_by_mem = max(1, max_mem // ESTIMATED_MEM_GB_PER_SAMPLE)
        max_conc = min(conc_by_cpu, conc_by_mem)

    return max_cpus, max_mem, max_conc

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
def get_db():
    if "db" not in g:
        os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
        g.db = sqlite3.connect(DB_FILE)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA journal_mode=WAL")
    return g.db


@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    os.makedirs(os.path.dirname(DB_FILE), exist_ok=True)
    conn = sqlite3.connect(DB_FILE)
    conn.executescript("""
    CREATE TABLE IF NOT EXISTS orders (
        id              TEXT PRIMARY KEY,
        order_name      TEXT NOT NULL,
        patient_name    TEXT DEFAULT '',
        patient_dob     TEXT DEFAULT '',
        chart_number    TEXT DEFAULT '',
        department      TEXT DEFAULT '',
        doctor_name     TEXT DEFAULT '',
        diagnosis       TEXT DEFAULT '',
        doctor_comment  TEXT DEFAULT '',
        sample_name     TEXT NOT NULL,
        r1_fastq        TEXT NOT NULL,
        r2_fastq        TEXT NOT NULL,
        reference       TEXT DEFAULT 'hg38',
        profile         TEXT DEFAULT 'docker',
        af_threshold    REAL DEFAULT 0.005,
        bed_file        TEXT DEFAULT '',
        remove_bams     TEXT DEFAULT 'Y',
        delete_intermediate TEXT DEFAULT 'Y',
        order_type      TEXT DEFAULT 'baseline',
        baseline_order_id   TEXT DEFAULT '',
        germline_order_id   TEXT DEFAULT '',
        followup_order_ids  TEXT DEFAULT '',
        status          TEXT DEFAULT 'registered',
        nf_run_name     TEXT DEFAULT '',
        nf_work_dir     TEXT DEFAULT '',
        pid             INTEGER DEFAULT 0,
        error_message   TEXT DEFAULT '',
        created_at      TEXT,
        updated_at      TEXT,
        started_at      TEXT,
        completed_at    TEXT
    );
    CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT
    );
    """)
    for col, coldef in [
        ("order_type", "TEXT DEFAULT 'baseline'"),
        ("baseline_order_id", "TEXT DEFAULT ''"),
        ("germline_order_id", "TEXT DEFAULT ''"),
        ("followup_order_ids", "TEXT DEFAULT ''"),
    ]:
        try:
            conn.execute(f"ALTER TABLE orders ADD COLUMN {col} {coldef}")
        except sqlite3.OperationalError:
            pass

    cur = conn.execute("SELECT COUNT(*) FROM settings")
    if cur.fetchone()[0] == 0:
        defaults = {
            "max_concurrent_samples": "3",
            "default_af_threshold": "0.005",
            "default_reference": "hg38",
            "default_profile": "docker",
            "remove_bams": "Y",
            "delete_intermediate": "Y",
            "nf_resume": "Y",
            "clean_work_dir": "N",
            "fastq_base_dir": "",
        }
        conn.executemany(
            "INSERT INTO settings (key, value) VALUES (?, ?)",
            defaults.items(),
        )
    conn.commit()
    conn.close()


def dict_from_row(row):
    return dict(row) if row else None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def get_all_settings():
    db = get_db()
    rows = db.execute("SELECT key, value FROM settings").fetchall()
    return {r["key"]: r["value"] for r in rows}


def get_setting(key, default=""):
    db = get_db()
    row = db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return row["value"] if row else default


def docker_container_status(container_name, retries=3):
    """Check Docker container status. Returns 'running', 'exited', or None."""
    delay = 0.2
    for attempt in range(retries):
        try:
            r = subprocess.run(
                ["docker", "inspect", "-f", "{{.State.Status}}", container_name],
                capture_output=True, text=True, timeout=10,
            )
            if r.returncode == 0:
                return r.stdout.strip()
        except Exception:
            pass
        if attempt < retries - 1:
            time.sleep(delay)
    return None


def docker_container_exit_code(container_name):
    """Get container exit code. Returns int or None."""
    try:
        r = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.ExitCode}}", container_name],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0:
            return int(r.stdout.strip())
    except Exception:
        pass
    return None


def sync_order_statuses():
    """Reconcile DB order statuses with Docker container states."""
    db = get_db()
    now = datetime.now().isoformat()
    running_orders = db.execute(
        "SELECT id, sample_name, nf_run_name FROM orders WHERE status IN ('running', 'queued')"
    ).fetchall()
    for order in running_orders:
        container_name = f"nxt_{order['sample_name']}_{order['id'][:8]}"
        status = docker_container_status(container_name)
        if status == "running":
            continue
        elif status == "exited":
            exit_code = docker_container_exit_code(container_name)
            if exit_code == 0:
                db.execute(
                    "UPDATE orders SET status='completed', completed_at=?, updated_at=? WHERE id=?",
                    (now, now, order["id"]),
                )
            else:
                db.execute(
                    "UPDATE orders SET status='failed', error_message=?, updated_at=? WHERE id=?",
                    (f"Container exited with code {exit_code}", now, order["id"]),
                )
        elif status is None:
            try:
                r = subprocess.run(
                    ["docker", "inspect", container_name],
                    capture_output=True, text=True, timeout=10,
                )
                err = (r.stderr or "") + (r.stdout or "")
                if r.returncode != 0 and "No such object" in err:
                    db.execute(
                        "UPDATE orders SET status='failed', error_message='Container not found', updated_at=? WHERE id=?",
                        (now, order["id"]),
                    )
            except Exception:
                pass

    # Recover false negatives: UI showed "Container not found" but container is still running
    recovered = db.execute(
        """SELECT id, sample_name FROM orders
           WHERE status='failed' AND error_message='Container not found'"""
    ).fetchall()
    for order in recovered:
        cn = f"nxt_{order['sample_name']}_{order['id'][:8]}"
        st = docker_container_status(cn)
        if st == "running":
            db.execute(
                "UPDATE orders SET status='running', error_message='', updated_at=? WHERE id=?",
                (now, order["id"]),
            )
        elif st == "exited":
            exit_code = docker_container_exit_code(cn)
            if exit_code == 0:
                db.execute(
                    "UPDATE orders SET status='completed', error_message='', completed_at=?, updated_at=? WHERE id=?",
                    (now, now, order["id"]),
                )
            else:
                db.execute(
                    "UPDATE orders SET status='failed', error_message=?, updated_at=? WHERE id=?",
                    (f"Container exited with code {exit_code}", now, order["id"]),
                )

    db.commit()


# ---------------------------------------------------------------------------
# Nextflow execution
# ---------------------------------------------------------------------------
def prepare_fastq_symlinks(order):
    """Create order-specific directory with symlinks to source FASTQ files."""
    order_id = order["id"]
    order_fastq_dir = os.path.join(FASTQ_DIR, order_id)
    os.makedirs(order_fastq_dir, exist_ok=True)

    source_base = FASTQ_SOURCE_DIR if os.path.isdir(FASTQ_SOURCE_DIR) else FASTQ_DIR
    r1_source = os.path.join(source_base, order["r1_fastq"])
    r2_source = os.path.join(source_base, order["r2_fastq"])
    r1_link = os.path.join(order_fastq_dir, os.path.basename(order["r1_fastq"]))
    r2_link = os.path.join(order_fastq_dir, os.path.basename(order["r2_fastq"]))

    for src, dst in [(r1_source, r1_link), (r2_source, r2_link)]:
        if os.path.lexists(dst):
            os.remove(dst)
        os.symlink(os.path.abspath(src), dst)

    return r1_link, r2_link


def generate_samplesheet(order, r1_path, r2_path):
    """Create a single-sample CSV samplesheet for Nextflow."""
    ss_dir = os.path.join(LOG_DIR, "samplesheets")
    os.makedirs(ss_dir, exist_ok=True)
    ss_path = os.path.join(ss_dir, f"{order['sample_name']}_{order['id']}.csv")
    with open(ss_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_id", "fastq_1", "fastq_2"])
        writer.writerow([order["sample_name"], r1_path, r2_path])
    return ss_path


def start_analysis(order, force=False, resume=True):
    """Start a Nextflow analysis via docker run roche_nxt_analysis."""
    db = get_db()
    now = datetime.now().isoformat()
    sample = order["sample_name"]
    order_id = order["id"]

    max_cpus, max_mem, max_conc = get_resource_limits()

    running_count = db.execute(
        "SELECT COUNT(*) c FROM orders WHERE status IN ('running', 'queued')"
    ).fetchone()["c"]
    if running_count >= max_conc and not force:
        raise RuntimeError(
            f"동시 실행 제한 초과: 현재 {running_count}개 실행 중 (최대 {max_conc}개). "
            f"서버 리소스: {max_cpus} CPU, {max_mem} GB 메모리"
        )

    cpus_per_sample = max_cpus // max(1, max_conc)
    mem_per_sample = max_mem // max(1, max_conc)

    container_name = f"nxt_{sample}_{order_id[:8]}"

    if force:
        subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, timeout=10)
    else:
        existing = subprocess.run(
            ["docker", "ps", "-a", "-q", "-f", f"name=^{container_name}$"],
            capture_output=True, text=True, timeout=10,
        )
        if existing.stdout.strip():
            subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, timeout=10)

    host_root = HOST_DIR
    fastq_host_dir = FASTQ_HOST_DIR or os.path.join(host_root, "fastq")
    data_host_dir = os.path.join(host_root, "data")
    bed_host_dir = BED_HOST_DIR or os.path.join(data_host_dir, "bed")

    host_samplesheet_dir = os.path.join(host_root, "log", "samplesheets")
    os.makedirs(os.path.join(LOG_DIR, "samplesheets"), exist_ok=True)
    ss_name = f"{sample}_{order_id}.csv"
    ss_container_path = f"/work_nxt/log/samplesheets/{ss_name}"
    ss_host_path = os.path.join(LOG_DIR, "samplesheets", ss_name)

    r1_container = f"/work_nxt_fastq_source/{order['r1_fastq']}"
    r2_container = f"/work_nxt_fastq_source/{order['r2_fastq']}"
    with open(ss_host_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sample_id", "fastq_1", "fastq_2"])
        writer.writerow([sample, r1_container, r2_container])

    run_name = f"run_{sample}_{order_id}_{int(time.time())}"
    work_dir_rel = f"work/{run_name}"
    nxf_home_rel = f"work/.nxf_home/{order_id}"

    os.makedirs(os.path.join(BASE_DIR, work_dir_rel), exist_ok=True)
    os.makedirs(os.path.join(BASE_DIR, nxf_home_rel), exist_ok=True)
    os.makedirs(os.path.join(RESULTS_DIR, sample), exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)

    af = order.get("af_threshold") or 0.005
    ref = order.get("reference") or "hg38"

    uid_gid = subprocess.run(["id", "-u"], capture_output=True, text=True).stdout.strip()
    gid = subprocess.run(["id", "-g"], capture_output=True, text=True).stdout.strip()

    nf_cmd = [
        "nextflow", "run", "/work_nxt/main.nf",
        "-profile", "local",
        "-name", run_name,
        "-work-dir", f"/work_nxt/{work_dir_rel}",
        "--input", ss_container_path,
        "--outdir", f"/work_nxt/results/{sample}",
        "--reference", ref,
        "--af_threshold", str(af),
        "--data_dir", "/work_nxt_data",
    ]

    if resume and not force:
        nf_cmd.append("-resume")

    if order.get("bed_file"):
        nf_cmd.extend(["--target_bed", f"/work_nxt_bed/{order['bed_file']}"])
    if order.get("remove_bams") == "Y":
        nf_cmd.append("--remove_bams")
    if order.get("delete_intermediate") == "Y":
        nf_cmd.append("--delete_intermediate")

    nf_cmd.extend(["--max_cpus", str(cpus_per_sample), "--max_memory", str(mem_per_sample)])

    if order.get("order_type") == "longitudinal":
        nf_cmd.extend(["--run_select_reporter", "true", "--run_longitudinal", "true"])

    docker_cmd = [
        "docker", "run", "-d",
        "--user", f"{uid_gid}:{gid}",
        "-e", f"HOME=/work_nxt/{nxf_home_rel}",
        "-e", f"NXF_HOME=/work_nxt/{nxf_home_rel}",
        "-e", "NXF_ANSI_LOG=false",
        "-w", f"/work_nxt/{nxf_home_rel}",
        "-v", f"{host_root}:/work_nxt",
        "-v", f"{fastq_host_dir}:/work_nxt_fastq_source:ro",
        "-v", f"{data_host_dir}:/work_nxt_data:ro",
        "-v", f"{bed_host_dir}:/work_nxt_bed:ro",
        "--name", container_name,
        ANALYSIS_IMAGE,
    ] + nf_cmd

    log_path = os.path.join(LOG_DIR, f"{sample}_{order_id}_nf.log")
    with open(log_path, "w") as lf:
        lf.write(f"# Docker command:\n# {' '.join(docker_cmd)}\n\n")

    result = subprocess.run(docker_cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Docker run failed")

    container_id = result.stdout.strip()[:12]

    db.execute(
        "UPDATE orders SET status='running', nf_run_name=?, nf_work_dir=?, pid=0, started_at=?, updated_at=? WHERE id=?",
        (run_name, os.path.join(BASE_DIR, work_dir_rel), now, now, order_id),
    )
    db.commit()
    return container_id


# ---------------------------------------------------------------------------
# FASTQ / BED file browsing
# ---------------------------------------------------------------------------
def browse_fastq(subdir=""):
    base = FASTQ_SOURCE_DIR if os.path.isdir(FASTQ_SOURCE_DIR) else FASTQ_DIR
    target = os.path.join(base, subdir) if subdir else base
    target = os.path.abspath(target)
    if not target.startswith(os.path.abspath(base)):
        target, subdir = base, ""

    dirs, samples = [], {}
    if not os.path.exists(target):
        return {"directories": dirs, "samples": [], "current_path": subdir, "parent_path": None}

    for item in sorted(os.listdir(target)):
        full = os.path.join(target, item)
        if item.startswith("."):
            continue
        if os.path.isdir(full):
            dirs.append({"name": item, "path": os.path.join(subdir, item) if subdir else item})

    patterns = [
        r"(.+)_R([12])_\d+\.fastq[-\d]*\.gz$",
        r"(.+)_R([12])_\d+\.(fastq|fq)\.gz$",
        r"(.+)_R([12])_\d+\.(fastq|fq)$",
        r"(.+)_R([12])\.(fastq|fq)\.gz$",
        r"(.+)_R([12])\.(fastq|fq)$",
        r"(.+)_([12])\.(fastq|fq)\.gz$",
        r"(.+)_([12])\.(fastq|fq)$",
    ]

    fq_files = []
    for ext in ("*.fastq*.gz", "*.fq*.gz", "*.fastq", "*.fq"):
        fq_files.extend(glob.glob(os.path.join(target, ext)))

    for f in fq_files:
        bn = os.path.basename(f)
        for pat in patterns:
            m = re.match(pat, bn)
            if m:
                sname, rnum = m.group(1), m.group(2)
                samples.setdefault(sname, {})
                key = "r1" if rnum == "1" else "r2"
                samples[sname][key] = bn
                break

    pairs = []
    for sname, files in samples.items():
        if "r1" in files and "r2" in files:
            r1p = os.path.join(subdir, files["r1"]) if subdir else files["r1"]
            r2p = os.path.join(subdir, files["r2"]) if subdir else files["r2"]
            try:
                sz1 = os.path.getsize(os.path.join(target, files["r1"]))
                sz2 = os.path.getsize(os.path.join(target, files["r2"]))
            except OSError:
                sz1 = sz2 = 0
            pairs.append({"name": sname, "r1": r1p, "r2": r2p, "size_r1": sz1, "size_r2": sz2})

    return {
        "directories": dirs,
        "samples": sorted(pairs, key=lambda x: x["name"]),
        "current_path": subdir,
        "parent_path": os.path.dirname(subdir) if subdir else None,
    }


def browse_bed(subdir=""):
    base = BED_SOURCE_DIR if os.path.isdir(BED_SOURCE_DIR) else os.path.join(DATA_DIR, "bed")
    target = os.path.join(base, subdir) if subdir else base
    target = os.path.abspath(target)
    if not target.startswith(os.path.abspath(base)):
        target, subdir = base, ""

    dirs, files = [], []
    if os.path.exists(target):
        for item in sorted(os.listdir(target)):
            if item.startswith("."):
                continue
            full = os.path.join(target, item)
            rel = os.path.join(subdir, item) if subdir else item
            if os.path.isdir(full):
                dirs.append({"name": item, "path": rel})
            elif item.endswith(".bed"):
                files.append({"name": item, "path": rel, "size": os.path.getsize(full)})

    return {
        "directories": dirs,
        "files": files,
        "current_path": subdir,
        "parent_path": os.path.dirname(subdir) if subdir else None,
    }


# ---------------------------------------------------------------------------
# Routes — Pages
# ---------------------------------------------------------------------------
@app.route("/favicon.ico")
def favicon():
    """Browsers request /favicon.ico by default; PNG is fine for modern clients."""
    path = os.path.join(app.static_folder, "roche-logo.png")
    if not os.path.isfile(path):
        return ("", 404)
    return send_file(path, mimetype="image/png", max_age=0)


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/features")
def api_features():
    return jsonify({"longitudinal": ENABLE_LONGITUDINAL})


@app.route("/api/system_resources")
def api_system_resources():
    """Return detected system resources and current effective limits."""
    sys_cpus, sys_mem = detect_system_resources()
    max_cpus, max_mem, max_conc = get_resource_limits()
    cpus_per_sample = max_cpus // max(1, max_conc)
    mem_per_sample = max_mem // max(1, max_conc)
    db = get_db()
    running = db.execute(
        "SELECT COUNT(*) c FROM orders WHERE status IN ('running', 'queued')"
    ).fetchone()["c"]
    return jsonify({
        "system_cpus": sys_cpus,
        "system_memory_gb": sys_mem,
        "max_cpus": max_cpus,
        "max_memory_gb": max_mem,
        "max_concurrent_samples": max_conc,
        "cpus_per_sample": cpus_per_sample,
        "memory_per_sample_gb": mem_per_sample,
        "currently_running": running,
        "estimated_cpus_per_sample": ESTIMATED_CPUS_PER_SAMPLE,
        "estimated_mem_per_sample": ESTIMATED_MEM_GB_PER_SAMPLE,
    })


# ---------------------------------------------------------------------------
# Routes — Dashboard API
# ---------------------------------------------------------------------------
@app.route("/api/dashboard")
def api_dashboard():
    db = get_db()
    sync_order_statuses()
    total = db.execute("SELECT COUNT(*) c FROM orders").fetchone()["c"]
    running = db.execute("SELECT COUNT(*) c FROM orders WHERE status='running'").fetchone()["c"]
    completed = db.execute("SELECT COUNT(*) c FROM orders WHERE status='completed'").fetchone()["c"]
    failed = db.execute("SELECT COUNT(*) c FROM orders WHERE status='failed'").fetchone()["c"]
    queued = db.execute("SELECT COUNT(*) c FROM orders WHERE status='queued'").fetchone()["c"]
    registered = db.execute("SELECT COUNT(*) c FROM orders WHERE status='registered'").fetchone()["c"]

    recent = db.execute(
        "SELECT id, order_name, sample_name, status, updated_at FROM orders ORDER BY updated_at DESC LIMIT 10"
    ).fetchall()

    return jsonify({
        "total": total, "running": running, "completed": completed,
        "failed": failed, "queued": queued, "registered": registered,
        "recent": [dict_from_row(r) for r in recent],
    })


@app.route("/api/resources")
def api_resources():
    cpu = psutil.cpu_percent(interval=0.5)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage(BASE_DIR if os.path.exists(BASE_DIR) else "/")
    return jsonify({
        "cpu_percent": cpu,
        "cpu_count": psutil.cpu_count(),
        "mem_total_gb": round(mem.total / 1e9, 1),
        "mem_used_gb": round(mem.used / 1e9, 1),
        "mem_percent": mem.percent,
        "disk_total_gb": round(disk.total / 1e9, 1),
        "disk_used_gb": round(disk.used / 1e9, 1),
        "disk_percent": disk.percent,
    })


# ---------------------------------------------------------------------------
# Routes — Orders API
# ---------------------------------------------------------------------------
@app.route("/api/orders")
def api_orders():
    db = get_db()
    sync_order_statuses()
    status_filter = request.args.get("status")
    if status_filter:
        rows = db.execute("SELECT * FROM orders WHERE status=? ORDER BY created_at DESC", (status_filter,)).fetchall()
    else:
        rows = db.execute("SELECT * FROM orders ORDER BY created_at DESC").fetchall()

    result = []
    for r in rows:
        o = dict_from_row(r)
        sample = o.get("sample_name", "")
        o["has_vcf"] = bool(glob.glob(os.path.join(RESULTS_DIR, sample, "**", f"{sample}*.vcf"), recursive=True))
        o["has_log"] = bool(glob.glob(os.path.join(LOG_DIR, f"{sample}_*_nf.log")))
        qc_dir = os.path.join(RESULTS_DIR, sample, sample, "QC_report")
        o["has_qc"] = os.path.isdir(qc_dir) and bool(os.listdir(qc_dir))
        result.append(o)
    return jsonify(result)


@app.route("/api/orders/completed_list")
def api_completed_list():
    """Return completed orders that can serve as Baseline/Germline/Followup references."""
    db = get_db()
    rows = db.execute(
        "SELECT id, order_name, patient_name, sample_name, chart_number, order_type, status, created_at "
        "FROM orders WHERE status='completed' ORDER BY created_at DESC"
    ).fetchall()
    return jsonify([dict_from_row(r) for r in rows])


@app.route("/api/orders", methods=["POST"])
def api_create_order():
    data = request.json
    if not data.get("sample_name") or not data.get("r1_fastq") or not data.get("r2_fastq"):
        return jsonify({"success": False, "error": "sample_name, r1_fastq, r2_fastq are required"}), 400

    order_id = datetime.now().strftime("%Y%m%d%H%M%S") + "-" + uuid.uuid4().hex[:6]
    now = datetime.now().isoformat()

    order_type = data.get("order_type", "baseline")
    if order_type == "longitudinal" and ENABLE_LONGITUDINAL:
        if not data.get("baseline_order_id") or not data.get("germline_order_id"):
            return jsonify({"success": False, "error": "Longitudinal requires baseline and germline order selection"}), 400

    followup_ids = ",".join(data.get("followup_order_ids", [])) if isinstance(data.get("followup_order_ids"), list) else data.get("followup_order_ids", "")

    db = get_db()
    db.execute("""
        INSERT INTO orders (id, order_name, patient_name, patient_dob, chart_number,
            department, doctor_name, diagnosis, doctor_comment,
            sample_name, r1_fastq, r2_fastq, reference, profile,
            af_threshold, bed_file, remove_bams, delete_intermediate,
            order_type, baseline_order_id, germline_order_id, followup_order_ids,
            status, created_at, updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
    """, (
        order_id,
        data.get("order_name", data["sample_name"]),
        data.get("patient_name", ""),
        data.get("patient_dob", ""),
        data.get("chart_number", ""),
        data.get("department", ""),
        data.get("doctor_name", ""),
        data.get("diagnosis", ""),
        data.get("doctor_comment", ""),
        data["sample_name"],
        data["r1_fastq"],
        data["r2_fastq"],
        data.get("reference", "hg38"),
        data.get("profile", "docker"),
        float(data.get("af_threshold", 0.005)),
        data.get("bed_file", ""),
        data.get("remove_bams", "Y"),
        data.get("delete_intermediate", "Y"),
        order_type,
        data.get("baseline_order_id", ""),
        data.get("germline_order_id", ""),
        followup_ids,
        "registered", now, now,
    ))
    db.commit()
    return jsonify({"success": True, "order_id": order_id})


@app.route("/api/orders/<order_id>")
def api_get_order(order_id):
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"error": "Not found"}), 404
    return jsonify(dict_from_row(row))


@app.route("/api/orders/<order_id>", methods=["PUT"])
def api_update_order(order_id):
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    if row["status"] not in ("registered", "failed", "cancelled"):
        return jsonify({"success": False, "error": "Only registered/failed/cancelled orders can be edited"}), 400

    data = request.json
    now = datetime.now().isoformat()

    editable = [
        "order_name", "patient_name", "patient_dob", "chart_number",
        "department", "doctor_name", "diagnosis", "doctor_comment",
        "sample_name", "r1_fastq", "r2_fastq", "reference", "profile",
        "bed_file", "remove_bams", "delete_intermediate",
        "order_type", "baseline_order_id", "germline_order_id", "followup_order_ids",
    ]
    sets = ["updated_at=?"]
    params = [now]
    for col in editable:
        if col in data:
            val = data[col]
            if col == "followup_order_ids" and isinstance(val, list):
                val = ",".join(val)
            sets.append(f"{col}=?")
            params.append(val)

    if "af_threshold" in data:
        sets.append("af_threshold=?")
        params.append(float(data["af_threshold"]))

    params.append(order_id)
    db.execute(f"UPDATE orders SET {', '.join(sets)} WHERE id=?", params)
    db.commit()
    return jsonify({"success": True})


@app.route("/api/orders/<order_id>/start", methods=["POST"])
def api_start_order(order_id):
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    order = dict_from_row(row)
    nf_resume = get_setting("nf_resume", "Y") == "Y"
    try:
        cid = start_analysis(order, force=False, resume=nf_resume)
        return jsonify({"success": True, "container_id": cid})
    except Exception as e:
        now = datetime.now().isoformat()
        db.execute("UPDATE orders SET status='failed', error_message=?, updated_at=? WHERE id=?",
                   (str(e), now, order_id))
        db.commit()
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/orders/<order_id>/stop", methods=["POST"])
def api_stop_order(order_id):
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    now = datetime.now().isoformat()
    container_name = f"nxt_{row['sample_name']}_{order_id[:8]}"
    subprocess.run(["docker", "stop", container_name], capture_output=True, timeout=30)
    subprocess.run(["docker", "rm", container_name], capture_output=True, timeout=10)
    db.execute("UPDATE orders SET status='cancelled', updated_at=? WHERE id=?", (now, order_id))
    db.commit()
    return jsonify({"success": True})


@app.route("/api/orders/<order_id>/rerun", methods=["POST"])
def api_rerun_order(order_id):
    """Rerun with Nextflow resume — leverages cached results."""
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    order = dict_from_row(row)
    container_name = f"nxt_{order['sample_name']}_{order_id[:8]}"
    subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, timeout=10)
    try:
        cid = start_analysis(order, force=False, resume=True)
        return jsonify({"success": True, "container_id": cid})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/orders/<order_id>/force", methods=["POST"])
def api_force_order(order_id):
    """Force run from the beginning — wipe work dir and results."""
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    order = dict_from_row(row)
    container_name = f"nxt_{order['sample_name']}_{order_id[:8]}"
    subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, timeout=10)
    import shutil
    if order.get("nf_work_dir") and os.path.isdir(order["nf_work_dir"]):
        shutil.rmtree(order["nf_work_dir"], ignore_errors=True)
    result_dir = os.path.join(RESULTS_DIR, order["sample_name"])
    if os.path.isdir(result_dir):
        shutil.rmtree(result_dir, ignore_errors=True)
    try:
        cid = start_analysis(order, force=True, resume=False)
        return jsonify({"success": True, "container_id": cid})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)})


@app.route("/api/orders/<order_id>/delete", methods=["DELETE"])
def api_delete_order(order_id):
    db = get_db()
    row = db.execute("SELECT sample_name, status FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404
    if row["status"] == "running":
        container_name = f"nxt_{row['sample_name']}_{order_id[:8]}"
        subprocess.run(["docker", "rm", "-f", container_name], capture_output=True, timeout=10)
    db.execute("DELETE FROM orders WHERE id=?", (order_id,))
    db.commit()
    return jsonify({"success": True})


# ---------------------------------------------------------------------------
# Routes — Logs
# ---------------------------------------------------------------------------
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\r")


def _clean_nf_log(raw: str) -> str:
    """Strip ANSI escapes and collapse repeated Nextflow progress blocks."""
    text = _ANSI_RE.sub("", raw)
    lines = text.split("\n")

    messages = []
    progress = {}
    last_executor_line = ""

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("executor >"):
            last_executor_line = stripped
            continue
        if stripped.startswith("[") and ("|" in stripped) and ("of" in stripped or "cached" in stripped):
            key = stripped.split("]")[0] + "]"
            progress[key] = stripped
            continue
        if stripped.startswith("Plus ") and "more processes waiting" in stripped:
            progress["__plus__"] = stripped
            continue
        messages.append(line)

    result_lines = []
    for line in messages:
        result_lines.append(line)

    if progress:
        result_lines.append("")
        if last_executor_line:
            result_lines.append(last_executor_line)
        for key in sorted(progress.keys()):
            if key != "__plus__":
                result_lines.append(progress[key])
        if "__plus__" in progress:
            result_lines.append(progress["__plus__"])

    return "\n".join(result_lines)


@app.route("/api/orders/<order_id>/logs")
def api_order_logs(order_id):
    db = get_db()
    row = db.execute("SELECT sample_name FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"success": False, "error": "Order not found"}), 404

    sample = row["sample_name"]
    tail = int(request.args.get("tail", "500"))

    container_name = f"nxt_{sample}_{order_id[:8]}"
    raw = ""
    try:
        r = subprocess.run(
            ["docker", "logs", "--tail", str(tail), container_name],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0 and (r.stdout or r.stderr):
            raw = r.stdout + r.stderr
    except Exception:
        pass

    if not raw:
        log_candidates = [
            os.path.join(LOG_DIR, f"{sample}_{order_id}_nf.log"),
            os.path.join(LOG_DIR, f"{sample}.log"),
        ]
        for lf in log_candidates:
            if os.path.isfile(lf):
                try:
                    with open(lf, "r", errors="replace") as f:
                        raw = f.read()
                except Exception:
                    pass
                break

    if not raw:
        return jsonify({"success": True, "logs": "No logs available yet."})

    return jsonify({"success": True, "logs": _clean_nf_log(raw)})


# ---------------------------------------------------------------------------
# Routes — Files
# ---------------------------------------------------------------------------
@app.route("/api/fastq_files")
def api_fastq_files():
    return jsonify(browse_fastq(request.args.get("path", "")))


@app.route("/api/bed_files")
def api_bed_files():
    return jsonify(browse_bed(request.args.get("path", "")))


@app.route("/api/download/<sample_name>/<file_type>")
def api_download(sample_name, file_type):
    try:
        if file_type == "vcf":
            fp = glob.glob(os.path.join(RESULTS_DIR, sample_name, "**", f"{sample_name}*.vcf"), recursive=True)
            fp = fp[0] if fp else ""
        elif file_type == "txt":
            fp = glob.glob(os.path.join(RESULTS_DIR, sample_name, "**", f"{sample_name}*annotated*.txt"), recursive=True)
            fp = fp[0] if fp else ""
        elif file_type == "log":
            candidates = glob.glob(os.path.join(LOG_DIR, f"{sample_name}_*_nf.log"))
            fp = candidates[0] if candidates else ""
        else:
            return jsonify({"error": "Invalid file type"}), 400
        if fp and os.path.isfile(fp):
            return send_file(fp, as_attachment=True)
        return jsonify({"error": "File not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/orders/<order_id>/qc_data")
def api_qc_data(order_id):
    """Collect all QC metrics for the given order."""
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"error": "Order not found"}), 404
    order = dict_from_row(row)
    sample = order["sample_name"]

    qc_dir = os.path.join(RESULTS_DIR, sample, sample, "QC_report")
    trim_dir = os.path.join(RESULTS_DIR, sample, sample, "trimming")

    def _parse_picard(filepath):
        """Parse a Picard-style metrics file: return list of dicts (one per data row)."""
        if not os.path.isfile(filepath):
            return None
        rows = []
        header = None
        in_metrics = False
        with open(filepath, "r", errors="replace") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("## METRICS CLASS"):
                    in_metrics = True
                    continue
                if line.startswith("## HISTOGRAM"):
                    break
                if in_metrics:
                    if header is None:
                        header = line.split("\t")
                    elif line.strip():
                        vals = line.split("\t")
                        rows.append(dict(zip(header, vals)))
                    else:
                        break
        return rows if rows else None

    def _read_count(filepath):
        if not os.path.isfile(filepath):
            return None
        with open(filepath, "r") as fh:
            text = fh.read().strip()
        for line in text.split("\n"):
            line = line.strip()
            if not line:
                continue
            if line.startswith("Tool returned:"):
                val = line.split(":", 1)[1].strip()
                if val:
                    try:
                        return int(val)
                    except ValueError:
                        continue
            else:
                try:
                    return int(line)
                except ValueError:
                    continue
        return None

    result = {"success": True, "sample_name": sample, "order_name": order.get("order_name", "")}

    # 1. fastp
    fastp_path = os.path.join(trim_dir, "fastp.json")
    if os.path.isfile(fastp_path):
        try:
            with open(fastp_path, "r") as fh:
                fj = json.load(fh)
            s_before = fj.get("summary", {}).get("before_filtering", {})
            s_after = fj.get("summary", {}).get("after_filtering", {})
            result["fastp"] = {
                "before_total_reads": s_before.get("total_reads", 0),
                "before_total_bases": s_before.get("total_bases", 0),
                "before_q20_rate": s_before.get("q20_rate", 0),
                "before_q30_rate": s_before.get("q30_rate", 0),
                "before_gc_content": s_before.get("gc_content", 0),
                "after_total_reads": s_after.get("total_reads", 0),
                "after_total_bases": s_after.get("total_bases", 0),
                "after_q20_rate": s_after.get("q20_rate", 0),
                "after_q30_rate": s_after.get("q30_rate", 0),
                "after_gc_content": s_after.get("gc_content", 0),
                "after_read1_mean_length": s_after.get("read1_mean_length", 0),
                "after_read2_mean_length": s_after.get("read2_mean_length", 0),
            }
            fc = fj.get("filtering_result", {})
            if fc:
                result["fastp"]["passed_filter_reads"] = fc.get("passed_filter_reads", 0)
                result["fastp"]["low_quality_reads"] = fc.get("low_quality_reads", 0)
                result["fastp"]["too_short_reads"] = fc.get("too_short_reads", 0)
                result["fastp"]["adapter_trimmed_reads"] = fj.get("adapter_cutting", {}).get("adapter_trimmed_reads", 0)
        except Exception:
            pass

    # 2. Alignment summary (umi_deduped and aligned)
    for label in ["umi_deduped", "aligned"]:
        fp = os.path.join(qc_dir, f"{sample}_alignment_metrics_{label}.txt")
        rows = _parse_picard(fp)
        if rows:
            pair_row = next((r for r in rows if r.get("CATEGORY") == "PAIR"), rows[-1])
            result[f"alignment_{label}"] = {
                "total_reads": pair_row.get("TOTAL_READS", ""),
                "pf_reads_aligned": pair_row.get("PF_READS_ALIGNED", ""),
                "pct_pf_reads_aligned": pair_row.get("PCT_PF_READS_ALIGNED", ""),
                "pf_mismatch_rate": pair_row.get("PF_MISMATCH_RATE", ""),
                "pct_chimeras": pair_row.get("PCT_CHIMERAS", ""),
                "pct_adapter": pair_row.get("PCT_ADAPTER", ""),
                "mean_read_length": pair_row.get("MEAN_READ_LENGTH", ""),
                "pct_reads_aligned_in_pairs": pair_row.get("PCT_READS_ALIGNED_IN_PAIRS", ""),
                "strand_balance": pair_row.get("STRAND_BALANCE", ""),
            }

    # 3. Insert size
    for label in ["umi_deduped", "aligned"]:
        fp = os.path.join(qc_dir, f"{sample}_insert_size_metrics_{label}.txt")
        rows = _parse_picard(fp)
        if rows:
            r0 = rows[0]
            result[f"insert_size_{label}"] = {
                "median_insert_size": r0.get("MEDIAN_INSERT_SIZE", ""),
                "mean_insert_size": r0.get("MEAN_INSERT_SIZE", ""),
                "standard_deviation": r0.get("STANDARD_DEVIATION", ""),
                "min_insert_size": r0.get("MIN_INSERT_SIZE", ""),
                "max_insert_size": r0.get("MAX_INSERT_SIZE", ""),
                "mode_insert_size": r0.get("MODE_INSERT_SIZE", ""),
                "read_pairs": r0.get("READ_PAIRS", ""),
            }

    # 4. MarkDuplicates
    fp = os.path.join(qc_dir, f"{sample}_markduplicates_metrics_gatk.txt")
    rows = _parse_picard(fp)
    if rows:
        r0 = rows[0]
        result["duplicates"] = {
            "read_pairs_examined": r0.get("READ_PAIRS_EXAMINED", ""),
            "read_pair_duplicates": r0.get("READ_PAIR_DUPLICATES", ""),
            "read_pair_optical_duplicates": r0.get("READ_PAIR_OPTICAL_DUPLICATES", ""),
            "percent_duplication": r0.get("PERCENT_DUPLICATION", ""),
            "estimated_library_size": r0.get("ESTIMATED_LIBRARY_SIZE", ""),
        }

    # 5. On-target reads
    for label in ["umi_deduped", "aligned"]:
        fp = os.path.join(qc_dir, f"{sample}_ontarget_reads_{label}.txt")
        count = _read_count(fp)
        if count is not None:
            result[f"ontarget_{label}"] = count

    # 6. HS metrics
    for label in ["umi_deduped", "aligned"]:
        fp = os.path.join(qc_dir, f"{sample}_hs_metrics_{label}.txt")
        rows = _parse_picard(fp)
        if rows:
            r0 = rows[0]
            result[f"hs_metrics_{label}"] = {
                "mean_target_coverage": r0.get("MEAN_TARGET_COVERAGE", ""),
                "median_target_coverage": r0.get("MEDIAN_TARGET_COVERAGE", ""),
                "max_target_coverage": r0.get("MAX_TARGET_COVERAGE", ""),
                "pct_selected_bases": r0.get("PCT_SELECTED_BASES", ""),
                "fold_enrichment": r0.get("FOLD_ENRICHMENT", ""),
                "zero_cvg_targets_pct": r0.get("ZERO_CVG_TARGETS_PCT", ""),
                "fold_80_base_penalty": r0.get("FOLD_80_BASE_PENALTY", ""),
                "pct_target_bases_1x": r0.get("PCT_TARGET_BASES_1X", ""),
                "pct_target_bases_10x": r0.get("PCT_TARGET_BASES_10X", ""),
                "pct_target_bases_20x": r0.get("PCT_TARGET_BASES_20X", ""),
                "pct_target_bases_30x": r0.get("PCT_TARGET_BASES_30X", ""),
                "pct_target_bases_50x": r0.get("PCT_TARGET_BASES_50X", ""),
                "pct_target_bases_100x": r0.get("PCT_TARGET_BASES_100X", ""),
                "pct_target_bases_250x": r0.get("PCT_TARGET_BASES_250X", ""),
                "pct_target_bases_500x": r0.get("PCT_TARGET_BASES_500X", ""),
                "pct_target_bases_1000x": r0.get("PCT_TARGET_BASES_1000X", ""),
                "total_reads": r0.get("TOTAL_READS", ""),
                "pf_unique_reads": r0.get("PF_UNIQUE_READS", ""),
                "on_target_bases": r0.get("ON_TARGET_BASES", ""),
                "pf_bases_aligned": r0.get("PF_BASES_ALIGNED", ""),
                "target_territory": r0.get("TARGET_TERRITORY", ""),
                "bait_territory": r0.get("BAIT_TERRITORY", ""),
                "on_bait_bases": r0.get("ON_BAIT_BASES", ""),
                "pct_usable_bases_on_target": r0.get("PCT_USABLE_BASES_ON_TARGET", ""),
            }

    # 7. Mismatch rate
    fp = os.path.join(qc_dir, f"{sample}_mismatch_rate.csv")
    if os.path.isfile(fp):
        try:
            with open(fp, "r") as fh:
                reader = csv.DictReader(fh)
                for row in reader:
                    result["mismatch_rate"] = {k: v for k, v in row.items()}
                    break
        except Exception:
            pass

    # Check which QC files exist
    result["has_qc"] = os.path.isdir(qc_dir) and bool(os.listdir(qc_dir))

    return jsonify(result)


@app.route("/api/orders/<order_id>/vcf_data")
def api_vcf_data(order_id):
    """Parse the VariantsToTable annotated txt and return JSON for the review table."""
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"error": "Order not found"}), 404
    order = dict_from_row(row)
    sample = order["sample_name"]

    candidates = glob.glob(
        os.path.join(RESULTS_DIR, sample, "**", f"{sample}*annotated*vcf.txt"),
        recursive=True,
    )
    if not candidates:
        return jsonify({"error": "No annotated VCF table found"}), 404
    fp = candidates[0]

    display_cols = [
        "CHROM", "POS", "REF", "ALT", "GENE", "EFFECT", "AF", "DP", "VD",
        "FILTER", "TYPE", "QUAL", "ID", "DBSNP_COMMON",
    ]

    def parse_ann(ann_str):
        """Extract gene and effect from the first SnpEff ANN entry."""
        if not ann_str or ann_str == "NA" or ann_str == ".":
            return "", ""
        first = ann_str.split(",")[0]
        parts = first.split("|")
        effect = parts[1] if len(parts) > 1 else ""
        gene = parts[3] if len(parts) > 3 else ""
        return gene, effect

    try:
        rows_out = []
        with open(fp, "r") as fh:
            header = fh.readline().rstrip("\n").split("\t")
            col_idx = {c: i for i, c in enumerate(header)}
            for line in fh:
                vals = line.rstrip("\n").split("\t")
                gene, effect = parse_ann(vals[col_idx["ANN"]] if "ANN" in col_idx else "")
                rec = {}
                for c in display_cols:
                    if c == "GENE":
                        rec[c] = gene
                    elif c == "EFFECT":
                        rec[c] = effect
                    elif c in col_idx:
                        rec[c] = vals[col_idx[c]]
                    else:
                        rec[c] = ""
                rows_out.append(rec)
        return jsonify({
            "success": True,
            "columns": display_cols,
            "data": rows_out,
            "sample_name": sample,
            "order_name": order.get("order_name", ""),
            "total": len(rows_out),
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ---------------------------------------------------------------------------
# Routes — Longitudinal VAF comparison
# ---------------------------------------------------------------------------
@app.route("/api/orders/<order_id>/longitudinal_data")
def api_longitudinal_data(order_id):
    """Build a VAF comparison table across the current followup + any prior followups."""
    db = get_db()
    row = db.execute("SELECT * FROM orders WHERE id=?", (order_id,)).fetchone()
    if not row:
        return jsonify({"error": "Order not found"}), 404
    order = dict_from_row(row)
    if order.get("order_type") != "longitudinal":
        return jsonify({"error": "Not a longitudinal order"}), 400

    def _parse_longit_csv(filepath):
        if not os.path.isfile(filepath):
            return None
        rows = []
        with open(filepath, "r", errors="replace") as fh:
            reader = csv.DictReader(fh)
            for r in reader:
                rows.append(r)
        return rows

    sample = order["sample_name"]
    longit_candidates = glob.glob(
        os.path.join(RESULTS_DIR, sample, "**", f"{sample}_longitudinal_analysis.csv"),
        recursive=True,
    )
    current_data = _parse_longit_csv(longit_candidates[0]) if longit_candidates else None

    followup_ids = [fid.strip() for fid in (order.get("followup_order_ids") or "").split(",") if fid.strip()]
    prior_followups = []
    for fid in followup_ids:
        frow = db.execute("SELECT sample_name, order_name, created_at FROM orders WHERE id=?", (fid,)).fetchone()
        if not frow:
            continue
        fsample = frow["sample_name"]
        fc = glob.glob(
            os.path.join(RESULTS_DIR, fsample, "**", f"{fsample}_longitudinal_analysis.csv"),
            recursive=True,
        )
        fdata = _parse_longit_csv(fc[0]) if fc else None
        if fdata:
            prior_followups.append({
                "order_id": fid,
                "order_name": frow["order_name"],
                "sample_name": fsample,
                "created_at": frow["created_at"],
                "data": fdata,
            })

    baseline_id = order.get("baseline_order_id", "")
    baseline_info = None
    if baseline_id:
        brow = db.execute("SELECT order_name, sample_name FROM orders WHERE id=?", (baseline_id,)).fetchone()
        if brow:
            baseline_info = {"order_id": baseline_id, "order_name": brow["order_name"], "sample_name": brow["sample_name"]}

    return jsonify({
        "success": True,
        "order_id": order_id,
        "order_name": order.get("order_name", ""),
        "sample_name": sample,
        "baseline": baseline_info,
        "current_followup": {
            "order_id": order_id,
            "order_name": order.get("order_name", ""),
            "sample_name": sample,
            "created_at": order.get("created_at", ""),
            "data": current_data,
        },
        "prior_followups": prior_followups,
    })


# ---------------------------------------------------------------------------
# .env file helpers
# ---------------------------------------------------------------------------
ENV_FILE = os.path.join(BASE_DIR, ".env")


def read_env_file():
    """Read .env file into a dict."""
    env = {}
    if os.path.isfile(ENV_FILE):
        with open(ENV_FILE, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip()
    return env


def write_env_file(env):
    """Write dict back to .env file, preserving key order."""
    with open(ENV_FILE, "w") as f:
        for k, v in env.items():
            f.write(f"{k}={v}\n")


# ---------------------------------------------------------------------------
# Routes — Settings API
# ---------------------------------------------------------------------------
@app.route("/api/settings")
def api_get_settings():
    settings = get_all_settings()
    env = read_env_file()
    settings["fastq_host_dir"] = env.get("FASTQ_HOST_DIR", FASTQ_HOST_DIR)
    settings["bed_host_dir"] = env.get("BED_HOST_DIR", BED_HOST_DIR)
    settings["max_cpus"] = env.get("MAX_CPUS", "0")
    settings["max_memory"] = env.get("MAX_MEMORY", "0")
    settings["max_concurrent_samples"] = env.get("MAX_CONCURRENT_SAMPLES", "0")
    return jsonify(settings)


@app.route("/api/settings", methods=["POST"])
def api_save_settings():
    data = request.json
    db = get_db()

    restart_needed = False
    env = None

    if "fastq_host_dir" in data:
        new_dir = data.pop("fastq_host_dir").strip()
        if new_dir:
            env = env or read_env_file()
            env["FASTQ_HOST_DIR"] = new_dir
            restart_needed = True

    if "bed_host_dir" in data:
        new_dir = data.pop("bed_host_dir").strip()
        if new_dir:
            env = env or read_env_file()
            env["BED_HOST_DIR"] = new_dir
            restart_needed = True

    for env_key in ["max_cpus", "max_memory", "max_concurrent_samples"]:
        if env_key in data:
            val = str(data.pop(env_key)).strip()
            env = env or read_env_file()
            env[env_key.upper()] = val
            os.environ[env_key.upper()] = val
            restart_needed = True

    if env is not None:
        write_env_file(env)

    for k, v in data.items():
        db.execute("INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)", (k, str(v)))
    db.commit()
    return jsonify({"success": True, "restart_needed": restart_needed})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
init_db()

if __name__ == "__main__":
    for d in [FASTQ_DIR, RESULTS_DIR, LOG_DIR]:
        os.makedirs(d, exist_ok=True)
    app.run(host="0.0.0.0", port=5000, debug=False)
