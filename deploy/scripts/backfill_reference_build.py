#!/usr/bin/env python3
"""Fill in orders.reference_build for orders analysed before the column existed.

The 'reference' label alone cannot identify the build: 'hg38' meant the full
3,366-contig UCSC FASTA before 2026-08-26 and the 2,580-contig primary-only
FASTA after. Nextflow records the resolved FASTA path in its HTML report, so
past runs can still be attributed.

Run inside the web container after upgrading:

    docker exec roche_nxt_web python3 \\
        /roche_nxt/deploy/scripts/backfill_reference_build.py

Add --dry-run to preview without writing.
"""
import argparse
import os
import sqlite3
import sys

sys.path.insert(0, "/app")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="판별 결과만 출력하고 DB에는 쓰지 않습니다.")
    ap.add_argument("--db", default=None,
                    help="orders DB 경로 (기본: app.py 의 DB_FILE)")
    args = ap.parse_args()

    try:
        import app as A
    except ImportError:
        sys.exit("app.py 를 import 할 수 없습니다. 웹 컨테이너 안에서 실행하세요.")

    db_path = args.db or A.DB_FILE
    if not os.path.isfile(db_path):
        sys.exit(f"orders DB 를 찾을 수 없습니다: {db_path}")

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row

    cols = {r[1] for r in conn.execute("PRAGMA table_info(orders)")}
    if "reference_build" not in cols:
        sys.exit("reference_build 컬럼이 없습니다. 먼저 웹 서비스를 새 버전으로 기동하세요.")

    rows = conn.execute(
        "SELECT * FROM orders "
        "WHERE status='completed' AND (reference_build IS NULL OR reference_build='')"
    ).fetchall()

    print(f"대상 오더: {len(rows)}건 (완료 상태 + 빌드 미기록)")
    if not rows:
        return

    resolved, unknown = 0, []
    with A.app.app_context():
        for row in rows:
            order = dict(row)
            # _order_reference_build reads the pipeline's reference_build.txt
            # first, then falls back to pipeline_info/report.html.
            build = A._order_reference_build(order, conn if not args.dry_run else None)
            if build:
                resolved += 1
                print(f"  {order['id']}  {order.get('reference','?'):<6} -> {build}")
            else:
                unknown.append(order["id"])

    if not args.dry_run:
        conn.commit()

    print()
    print(f"판별 완료 : {resolved}건")
    print(f"판별 불가 : {len(unknown)}건")
    if unknown:
        print("  (결과 디렉터리나 pipeline_info/report.html 이 없는 오래된 오더입니다.")
        print("   빌드를 알 수 없으므로 Longitudinal 검증에서는 라벨 비교로만 처리됩니다.)")
        for oid in unknown:
            print(f"  - {oid}")
    if args.dry_run:
        print()
        print("--dry-run 이므로 DB 에는 반영하지 않았습니다.")


if __name__ == "__main__":
    main()
