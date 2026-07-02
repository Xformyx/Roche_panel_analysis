#!/usr/bin/env python3
"""
roche_client.py — Roche_nxt 외부 연동 CLI 클라이언트

사용 예시:
  # 설정 저장 (최초 1회)
  python roche_client.py configure --url http://server:8080 --key rnxt-xxxx

  # Order 생성 + 분석 실행 + 완료 대기 + 결과 출력 (원스텝)
  python roche_client.py run \\
      --sample SAMPLE-001 \\
      --r1 SAMPLE-001_R1.fastq.gz \\
      --r2 SAMPLE-001_R2.fastq.gz \\
      --bed SNUH_bed/coords.cons.bed

  # Order 목록 조회
  python roche_client.py list

  # 특정 Order 상태 확인
  python roche_client.py status 20260626120000-abc123

  # QC 결과 조회
  python roche_client.py results 20260626120000-abc123

  # QC 리포트 다운로드
  python roche_client.py report 20260626120000-abc123 -o qc_report.txt

  # 실행 로그 출력
  python roche_client.py logs 20260626120000-abc123
"""

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import requests
except ImportError:
    print("[오류] requests 패키지가 필요합니다: pip install requests", file=sys.stderr)
    sys.exit(1)

# ── 설정 파일 경로 ─────────────────────────────────────────────────────────────
CONFIG_PATH = Path.home() / ".roche_client.json"

# ── ANSI 색상 (터미널 지원 여부 자동 감지) ────────────────────────────────────
USE_COLOR = sys.stdout.isatty()

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if USE_COLOR else text

def green(t):  return _c("32", t)
def red(t):    return _c("31", t)
def yellow(t): return _c("33", t)
def cyan(t):   return _c("36", t)
def bold(t):   return _c("1",  t)
def dim(t):    return _c("2",  t)


# ── 설정 로드/저장 ────────────────────────────────────────────────────────────
def load_config() -> dict:
    cfg = {}
    if CONFIG_PATH.exists():
        try:
            cfg = json.loads(CONFIG_PATH.read_text())
        except Exception:
            pass
    cfg.setdefault("url",     os.environ.get("ROCHE_BASE_URL", ""))
    cfg.setdefault("api_key", os.environ.get("ROCHE_API_KEY", ""))
    return cfg


def save_config(cfg: dict):
    CONFIG_PATH.write_text(json.dumps(cfg, indent=2, ensure_ascii=False))
    CONFIG_PATH.chmod(0o600)
    print(green(f"✓ 설정 저장됨: {CONFIG_PATH}"))


# ── HTTP 클라이언트 ────────────────────────────────────────────────────────────
class RocheClient:
    def __init__(self, base_url: str, api_key: str, timeout: int = 30):
        if not base_url or not api_key:
            print(red("오류: URL과 API Key가 필요합니다."), file=sys.stderr)
            print(dim("  python roche_client.py configure --url <URL> --key <KEY>"), file=sys.stderr)
            sys.exit(1)
        self.base = base_url.rstrip("/")
        self.headers = {"X-Api-Key": api_key, "Content-Type": "application/json"}
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update(self.headers)

    def _url(self, path: str) -> str:
        return f"{self.base}{path}"

    def get(self, path: str, **kwargs) -> dict:
        r = self.session.get(self._url(path), timeout=self.timeout, **kwargs)
        r.raise_for_status()
        return r.json()

    def post(self, path: str, data: dict = None, **kwargs) -> dict:
        r = self.session.post(self._url(path), json=data, timeout=self.timeout, **kwargs)
        r.raise_for_status()
        return r.json()

    def get_text(self, path: str) -> str:
        r = self.session.get(self._url(path), timeout=self.timeout)
        r.raise_for_status()
        return r.text


# ── 출력 헬퍼 ─────────────────────────────────────────────────────────────────
STATUS_COLORS = {
    "completed": green,
    "running":   cyan,
    "queued":    yellow,
    "starting":  yellow,
    "failed":    red,
    "cancelled": dim,
    "registered": dim,
}

def fmt_status(s: str) -> str:
    fn = STATUS_COLORS.get(s, str)
    return fn(s)


def table(rows: list[list], headers: list[str], col_widths: list[int] = None):
    """간단한 ASCII 테이블 출력."""
    if not rows:
        print(dim("  (데이터 없음)"))
        return
    if col_widths is None:
        col_widths = [max(len(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]

    sep = "+" + "+".join("-" * (w + 2) for w in col_widths) + "+"
    def row_line(cells):
        return "|" + "|".join(f" {str(c):<{w}} " for c, w in zip(cells, col_widths)) + "|"

    print(sep)
    print(bold(row_line(headers)))
    print(sep)
    for r in rows:
        print(row_line(r))
    print(sep)


def spinner_wait(label: str, stop_fn, interval: int = 10, max_minutes: int = 180):
    """완료 조건이 될 때까지 spinner를 표시하며 대기."""
    chars = ["|", "/", "-", "\\"]
    i = 0
    start = time.time()
    while True:
        elapsed = int(time.time() - start)
        elapsed_str = f"{elapsed // 60}m {elapsed % 60:02d}s"
        status, done = stop_fn()
        line = f"\r  {chars[i % 4]}  {label} ({elapsed_str}) [{fmt_status(status)}]   "
        print(line, end="", flush=True)
        if done:
            print()
            return status
        if elapsed > max_minutes * 60:
            print(f"\n{red('타임아웃')}: {max_minutes}분 초과", file=sys.stderr)
            sys.exit(1)
        time.sleep(interval)
        i += 1


# ── 커맨드 구현 ────────────────────────────────────────────────────────────────

def cmd_configure(args):
    cfg = load_config()
    if args.url:
        cfg["url"] = args.url.rstrip("/")
    if args.key:
        cfg["api_key"] = args.key
    save_config(cfg)
    print(f"  URL    : {cfg['url']}")
    print(f"  API Key: {cfg['api_key'][:12]}{'*' * max(0, len(cfg['api_key']) - 12)}")


def cmd_login(args):
    """ID/비밀번호로 로그인하여 API Key를 자동 발급·저장한다."""
    import getpass

    cfg = load_config()

    # URL 결정
    url = (args.url or cfg.get("url", "")).rstrip("/")
    if not url:
        url = input("서버 URL (예: http://server:8080): ").strip().rstrip("/")
    if not url:
        print(red("오류: 서버 URL이 필요합니다."), file=sys.stderr)
        sys.exit(1)

    # 계정 정보
    user_id  = args.user or input("사용자 ID: ").strip()
    password = args.password or getpass.getpass("비밀번호: ")

    sess = requests.Session()

    # 1. 로그인
    print(f"\n{cyan('● 로그인 중...')} ({url})")
    try:
        r = sess.post(
            f"{url}/api/auth/login",
            json={"user_id": user_id, "password": password},
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
    except requests.ConnectionError:
        print(red(f"연결 실패: {url}"), file=sys.stderr)
        sys.exit(1)
    except requests.HTTPError as e:
        print(red(f"HTTP 오류: {e}"), file=sys.stderr)
        sys.exit(1)

    if not data.get("success"):
        print(red(f"로그인 실패: {data.get('error', '아이디 또는 비밀번호를 확인하세요.')}"), file=sys.stderr)
        sys.exit(1)
    print(green(f"✓ 로그인 성공 ({data.get('user_id', user_id)})"))

    # 2. API Key 조회 (세션 쿠키 사용)
    r2 = sess.get(f"{url}/api/auth/api_key", timeout=15)
    r2.raise_for_status()
    api_key = r2.json().get("api_key", "")
    if not api_key:
        print(red("API Key를 받아오지 못했습니다."), file=sys.stderr)
        sys.exit(1)

    # 3. 설정 저장
    cfg["url"]     = url
    cfg["api_key"] = api_key
    save_config(cfg)
    masked = api_key[:12] + "*" * max(0, len(api_key) - 12)
    print(f"  URL    : {url}")
    print(f"  API Key: {masked}")
    print(dim(f"  설정 파일: {CONFIG_PATH}"))


def cmd_list(args):
    c = _make_client()
    orders = c.get("/api/orders")
    if not isinstance(orders, list):
        print(red("오류: 예상치 못한 응답"))
        return

    # 최신순 정렬
    orders.sort(key=lambda o: o.get("created_at", ""), reverse=True)
    limit = args.limit or len(orders)
    orders = orders[:limit]

    if args.status:
        orders = [o for o in orders if o.get("status") == args.status]

    rows = []
    for o in orders:
        created = (o.get("created_at") or "")[:16].replace("T", " ")
        rows.append([
            o.get("id", "")[:22],
            o.get("sample_name", "")[:28],
            o.get("reference", "hg38"),
            fmt_status(o.get("status", "")),
            created,
        ])

    print(f"\n{bold('Order 목록')} ({len(rows)}건)\n")
    table(rows, ["Order ID", "Sample", "Ref", "Status", "Created"])
    print()


def cmd_create(args):
    c = _make_client()
    payload = _build_order_payload(args)
    resp = c.post("/api/orders", payload)
    if not resp.get("success"):
        print(red(f"오류: {resp.get('error', '알 수 없는 오류')}"), file=sys.stderr)
        sys.exit(1)
    order_id = resp["order_id"]
    print(green(f"✓ Order 생성됨"))
    print(f"  Order ID : {bold(order_id)}")
    print(f"  Sample   : {args.sample}")
    return order_id


def cmd_start(args):
    c = _make_client()
    order_id = args.order_id
    resp = c.post(f"/api/orders/{order_id}/start")
    if not resp.get("success"):
        print(red(f"오류: {resp.get('error', '알 수 없는 오류')}"), file=sys.stderr)
        sys.exit(1)
    print(green(f"✓ 분석 시작됨: {order_id}"))


def cmd_run(args):
    """Order 생성 → 분석 실행 → 완료 대기 → 결과 출력 (원스텝)."""
    c = _make_client()

    # 1. Order 생성
    payload = _build_order_payload(args)
    resp = c.post("/api/orders", payload)
    if not resp.get("success"):
        print(red(f"Order 생성 실패: {resp.get('error')}"), file=sys.stderr)
        sys.exit(1)
    order_id = resp["order_id"]
    print(green(f"✓ Order 생성: {bold(order_id)}"))
    print(f"  Sample  : {args.sample}")
    print(f"  R1      : {args.r1}")
    print(f"  R2      : {args.r2}")
    print(f"  BED     : {args.bed or '(기본값)'}")
    print(f"  Ref     : {args.reference}")

    # 2. 분석 실행
    print(f"\n{cyan('▶ 분석 시작 중...')}")
    resp = c.post(f"/api/orders/{order_id}/start")
    if not resp.get("success"):
        print(red(f"분석 시작 실패: {resp.get('error')}"), file=sys.stderr)
        sys.exit(1)
    print(green("✓ 분석 컨테이너 실행됨"))

    # 3. 완료까지 대기
    print(f"\n{cyan('⏳ 분석 완료 대기 중...')} (Ctrl+C로 중단 가능, 오더는 계속 실행됨)\n")

    def check_done():
        try:
            o = c.get(f"/api/orders/{order_id}")
            st = o.get("status", "")
            return st, st in ("completed", "failed", "cancelled")
        except Exception:
            return "polling...", False

    final_status = spinner_wait(
        label=f"실행 중 [{args.sample}]",
        stop_fn=check_done,
        interval=args.poll_interval,
    )

    # 4. 결과 또는 오류
    if final_status == "completed":
        print(green(f"\n✓ 분석 완료!\n"))
        _print_results(c, order_id)
    else:
        order_detail = c.get(f"/api/orders/{order_id}")
        err = order_detail.get("error_message", "")
        print(red(f"\n✗ 분석 {final_status}"))
        if err:
            print(f"  {err}")
        sys.exit(1)


def cmd_status(args):
    c = _make_client()
    o = c.get(f"/api/orders/{args.order_id}")
    print(f"\n{bold('Order 상세')}")
    print(f"  ID       : {o.get('id')}")
    print(f"  Sample   : {o.get('sample_name')}")
    print(f"  Status   : {fmt_status(o.get('status', ''))}")
    print(f"  Reference: {o.get('reference', 'hg38')}")
    print(f"  BED      : {o.get('bed_file', '')}")
    print(f"  Created  : {(o.get('created_at') or '')[:19].replace('T', ' ')}")
    if o.get('completed_at'):
        print(f"  Completed: {o['completed_at'][:19].replace('T', ' ')}")
    if o.get('error_message'):
        print(f"  Error    : {red(o['error_message'])}")
    print()


def cmd_results(args):
    c = _make_client()
    _print_results(c, args.order_id)


def cmd_report(args):
    c = _make_client()
    text = c.get_text(f"/api/orders/{args.order_id}/qc_report.txt")
    out_path = args.output or f"qc_report_{args.order_id[:14]}.txt"
    Path(out_path).write_text(text, encoding="utf-8")
    print(green(f"✓ QC 리포트 저장: {out_path}"))
    if args.print:
        print("\n" + text)


def cmd_logs(args):
    c = _make_client()
    try:
        text = c.get_text(f"/api/orders/{args.order_id}/logs")
    except requests.HTTPError as e:
        print(red(f"로그 조회 실패: {e}"), file=sys.stderr)
        sys.exit(1)
    lines = text.splitlines()
    if args.tail:
        lines = lines[-args.tail:]
    print("\n".join(lines))


# ── 결과 출력 내부 함수 ────────────────────────────────────────────────────────
def _print_results(c: RocheClient, order_id: str):
    try:
        qc = c.get(f"/api/orders/{order_id}/qc_data")
    except requests.HTTPError as e:
        print(red(f"결과 조회 실패: {e}"), file=sys.stderr)
        return

    summary = qc.get("qc_summary", {})
    if not summary:
        print(yellow("  결과 데이터가 아직 없습니다. (분석 진행 중이거나 결과 파일 없음)"))
        return

    print(bold("  [핵심 QC 지표 - 6종]"))
    print()

    metrics = [
        ("Throughput",        summary.get("throughput_mb"),         "Mb",  None),
        ("Q30 Trimmed",       summary.get("q30_trimmed_pct"),        "%",   None),
        ("Mapped",            summary.get("mapped_pct"),             "%",   80.0),
        ("Duplicated",        summary.get("duplicated_pct"),         "%",   None),
        ("On-Target",         summary.get("ontarget_pct"),           "%",   80.0),
        ("On-Target Coverage",summary.get("ontarget_coverage_x"),    "x",   100.0),
    ]

    col_w = [22, 12, 4]
    sep = "+" + "+".join("-" * (w + 2) for w in col_w) + "+"
    h0 = f" {'지표':<{col_w[0]}} "
    h1 = f" {'값':<{col_w[1]}} "
    h2 = f" {'단위':<{col_w[2]}} "
    print(f"  {sep}")
    print(f"  |{bold(h0)}|{bold(h1)}|{bold(h2)}|")
    print(f"  {sep}")
    for name, val, unit, threshold in metrics:
        if val is None:
            val_str = dim("N/A")
        else:
            val_f = float(val)
            val_str = f"{val_f:.2f}"
            if threshold is not None:
                val_str = green(val_str) if val_f >= threshold else red(val_str)
        print(f"  | {name:<{col_w[0]}} | {val_str:<{col_w[1]}} | {unit:<{col_w[2]}} |")
    print(f"  {sep}")
    print()

    # 변이 통계
    try:
        vcf = c.get(f"/api/orders/{order_id}/vcf_data")
        variants = vcf if isinstance(vcf, list) else vcf.get("variants", [])
        if variants:
            total   = len(variants)
            wl_cnt  = sum(1 for v in variants if v.get("whitelist_status") == "whitelist")
            bl_cnt  = sum(1 for v in variants if v.get("whitelist_status") == "blacklist")
            print(bold("  [변이 요약]"))
            print(f"  총 변이   : {bold(str(total))} 개")
            print(f"  Whitelist : {green(str(wl_cnt))} 개")
            print(f"  Blacklist : {red(str(bl_cnt))} 개")
            print()
    except Exception:
        pass


# ── 공통 헬퍼 ─────────────────────────────────────────────────────────────────
def _make_client() -> RocheClient:
    cfg = load_config()
    return RocheClient(cfg.get("url", ""), cfg.get("api_key", ""))


def _build_order_payload(args) -> dict:
    return {
        "sample_name":   args.sample,
        "r1_fastq":      args.r1,
        "r2_fastq":      args.r2,
        "bed_file":      args.bed or "",
        "reference":     args.reference,
        "af_threshold":  args.af_threshold,
        "use_umi":       args.use_umi,
        "order_name":    args.order_name or args.sample,
        "patient_name":  args.patient or "",
        "chart_number":  args.chart or "",
        "department":    args.department or "",
        "doctor_name":   args.doctor or "",
    }


# ── 엔트리포인트 ───────────────────────────────────────────────────────────────
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="roche_client",
        description="Roche_nxt 외부 연동 CLI 클라이언트",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예시:
  # 방법 1: ID/비밀번호로 로그인 (API Key 자동 저장)
  python roche_client.py login --url http://server:8080 --user admin

  # 방법 2: API Key 직접 설정
  python roche_client.py configure --url http://server:8080 --key rnxt-xxxx

  # 분석 실행
  python roche_client.py run --sample S001 --r1 S001_R1.fastq.gz --r2 S001_R2.fastq.gz

  # 조회
  python roche_client.py list
  python roche_client.py results 20260626120000-abc123
  python roche_client.py report  20260626120000-abc123 -o report.txt
""",
    )
    parser.add_argument("--url", help="Roche_nxt 서버 URL (환경변수 ROCHE_BASE_URL 우선)")
    parser.add_argument("--key", help="API Key (환경변수 ROCHE_API_KEY 우선)")

    sub = parser.add_subparsers(dest="command", metavar="command")

    # login
    p = sub.add_parser("login", help="ID/비밀번호로 로그인하여 API Key 자동 저장")
    p.add_argument("--url",      help="서버 URL (예: http://server:8080)")
    p.add_argument("--user",     help="사용자 ID")
    p.add_argument("--password", help="비밀번호 (생략 시 안전하게 프롬프트 입력)")

    # configure
    p = sub.add_parser("configure", help="서버 URL과 API Key 직접 저장")
    p.add_argument("--url", required=False, help="서버 URL (예: http://server:8080)")
    p.add_argument("--key", required=False, help="API Key (rnxt-xxxx...)")

    # list
    p = sub.add_parser("list", help="Order 목록 조회")
    p.add_argument("--status", help="상태 필터 (registered|running|completed|failed)")
    p.add_argument("-n", "--limit", type=int, default=20, help="최대 출력 건수 (기본 20)")

    # create
    p = sub.add_parser("create", help="Order 생성 (분석 실행 없음)")
    _add_order_args(p)

    # start
    p = sub.add_parser("start", help="기존 Order 분석 실행")
    p.add_argument("order_id", help="Order ID")

    # run (create + start + wait + results)
    p = sub.add_parser("run", help="Order 생성 → 분석 실행 → 완료 대기 → 결과 출력 (원스텝)")
    _add_order_args(p)
    p.add_argument("--poll-interval", type=int, default=15, dest="poll_interval",
                   help="상태 확인 주기 (초, 기본 15)")

    # status
    p = sub.add_parser("status", help="Order 상태 확인")
    p.add_argument("order_id", help="Order ID")

    # results
    p = sub.add_parser("results", help="QC 결과 조회")
    p.add_argument("order_id", help="Order ID")

    # report
    p = sub.add_parser("report", help="QC 리포트 텍스트 다운로드")
    p.add_argument("order_id", help="Order ID")
    p.add_argument("-o", "--output", help="저장 파일명 (기본: qc_report_<id>.txt)")
    p.add_argument("--print", action="store_true", help="파일 저장 후 화면에도 출력")

    # logs
    p = sub.add_parser("logs", help="분석 로그 출력")
    p.add_argument("order_id", help="Order ID")
    p.add_argument("-n", "--tail", type=int, default=100, help="마지막 N줄만 출력 (기본 100)")

    return parser


def _add_order_args(p: argparse.ArgumentParser):
    p.add_argument("--sample",     required=True,  help="Sample ID (예: SAMPLE-001)")
    p.add_argument("--r1",         required=True,  help="R1 FASTQ 파일명 (fastq 디렉토리 기준)")
    p.add_argument("--r2",         required=True,  help="R2 FASTQ 파일명")
    p.add_argument("--bed",        default="",     help="BED 파일 경로 (상대)")
    p.add_argument("--reference",  default="hg38", choices=["hg38", "hg19"], help="레퍼런스 게놈")
    p.add_argument("--af",         type=float, default=0.005, dest="af_threshold", help="AF threshold (기본 0.005)")
    p.add_argument("--umi",        default="Y",    choices=["Y", "N", ""], dest="use_umi", help="UMI 사용 여부")
    p.add_argument("--order-name", dest="order_name", help="Order 이름 (기본: sample_name)")
    p.add_argument("--patient",    help="환자 이름")
    p.add_argument("--chart",      help="차트 번호")
    p.add_argument("--department", help="진료과")
    p.add_argument("--doctor",     help="담당 의사")


COMMANDS = {
    "login":     cmd_login,
    "configure": cmd_configure,
    "list":      cmd_list,
    "create":    cmd_create,
    "start":     cmd_start,
    "run":       cmd_run,
    "status":    cmd_status,
    "results":   cmd_results,
    "report":    cmd_report,
    "logs":      cmd_logs,
}


def main():
    parser = build_parser()
    args = parser.parse_args()

    # 전역 --url / --key 오버라이드: 설정파일보다 우선
    cfg = load_config()
    if args.url:
        cfg["url"] = args.url
    if getattr(args, "key", None) and args.key:
        cfg["api_key"] = args.key
    # configure 커맨드도 args.url/key를 갖지만 자체적으로 처리
    os.environ.setdefault("ROCHE_BASE_URL", cfg.get("url", ""))
    os.environ.setdefault("ROCHE_API_KEY",  cfg.get("api_key", ""))
    # RocheClient는 load_config()를 다시 부르므로 환경변수 세팅으로 전달

    if not args.command:
        parser.print_help()
        sys.exit(0)

    fn = COMMANDS.get(args.command)
    if fn is None:
        parser.print_help()
        sys.exit(1)

    try:
        fn(args)
    except requests.ConnectionError:
        print(red(f"\n연결 실패: {cfg.get('url', '(URL 미설정)')}"), file=sys.stderr)
        print(dim("  서버가 실행 중인지, URL이 올바른지 확인하세요."), file=sys.stderr)
        sys.exit(1)
    except requests.HTTPError as e:
        print(red(f"\nHTTP 오류: {e}"), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print(yellow("\n\n중단됨. (Order는 서버에서 계속 실행 중입니다)"))
        sys.exit(0)


if __name__ == "__main__":
    main()
