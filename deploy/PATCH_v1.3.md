# Roche_nxt 패치 가이드 — v1.3.0

> **대상**: BSCH (분당차병원), EONE (이원의학연구소) — 기존 설치 서버  
> **패치 유형**: Web 이미지 교체 (레퍼런스 데이터·분석 이미지 변경 없음)

---

## v1.3.0 변경 내용

| 기능 | 설명 |
|------|------|
| **QC — Capture ±250bp** | PCT_SELECTED_BASES 지표를 상단 요약 및 KPI 카드로 표시 |
| **3-BED 시스템** | 오더 생성 시 Capture / Primary / Bait Interval List 개별 선택 |
| **QC만 재실행** | 기존 BAM 재사용, BED 변경 후 QC·HsMetrics만 빠르게 재계산 |
| **버튼 레이블 개선** | "변경 후 분석 재실행" / "변경 후 QC 재실행" 명확화 |
| **라이선스 시스템 제거** | 모든 기능(hg19, Longitudinal, IGV) 기본 활성화 |
| **버전** | Ver.1.3.0 |

> **레퍼런스 데이터 추가 설치 불필요.**  
> Web 이미지만 교체하면 됩니다.

---

## 방법 선택

### ✅ 방법 1 (권장) — GitHub 자동 업그레이드

병원 서버에서 GitHub 접속이 가능하므로 아래 스크립트 한 번으로 완료됩니다.

```bash
# 설치 디렉터리 확인
find /opt /home -name "docker-compose.prod.yml" 2>/dev/null | grep roche

# 업그레이드 스크립트 실행 (설치 경로를 실제 경로로 변경)
cd /opt/roche_nxt     # 실제 설치 경로
bash deploy/scripts/upgrade_from_github.sh --install-dir /opt/roche_nxt --tag v1.3.0
```

완료 후 웹 UI 사이드바에 `Ver.1.3.0` 표시 확인.

---

### 방법 2 — 이미지 파일 직접 교체 (오프라인)

GitHub 접속이 안 되는 경우에만 사용합니다.

#### 2-1. 개발자가 준비 (개발 서버)

```bash
cd /home/ken/Roche_nxt

# 패치 패키지 자동 생성 (Web 이미지 + 소스 + 적용 스크립트 일괄 생성)
bash deploy/scripts/save_patch.sh --web-only

# 생성 위치: deploy/patches/roche_patch_v1.3.0/
ls deploy/patches/roche_patch_v1.3.0/
```

#### 2-2. 병원 서버로 전송

```bash
# SCP로 전송
scp -r deploy/patches/roche_patch_v1.3.0/ user@hospital-server:/tmp/

# 또는 tar로 묶어서 USB 전달
tar -czf roche_patch_v1.3.0.tar.gz -C deploy/patches roche_patch_v1.3.0
```

#### 2-3. 병원 서버에서 패치 적용

```bash
cd /tmp/roche_patch_v1.3.0

# 자동 적용 (설치 경로 자동 탐색)
bash apply_patch.sh

# 또는 설치 경로 직접 지정
bash apply_patch.sh --install-dir /opt/roche_nxt
```

스크립트가 자동으로 수행합니다:
- 중요 파일 백업 (`orders.db`, `.env`, `nextflow.config`)
- 소스 파일 교체 (DB·환경설정 보존)
- Docker 이미지 로드
- 서비스 재시작 및 기동 확인

---

## 확인 사항

```bash
# 1. 컨테이너 상태
docker ps | grep roche_nxt_web

# 2. 버전 확인
curl -s http://localhost:8080/api/version | python3 -m json.tool
# {"version": "1.3.0", ...}

# 3. 웹 UI 접속
# 사이드바 하단: Ver.1.3.0
```

---

## 병원별 설치 경로 (참고)

| 병원 | 예상 설치 경로 | 포트 |
|------|--------------|------|
| BSCH | `/opt/roche_bsch` 또는 `/home/*/roche_nxt` | 8080 |
| EONE | `/opt/roche_eone` 또는 `/home/*/roche_nxt` | 8080 |

설치 경로를 모르는 경우:

```bash
find /opt /home -name "docker-compose.prod.yml" 2>/dev/null
# 또는
docker inspect roche_nxt_web --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

---

## 롤백

```bash
# 백업 이미지로 복원 (이전 이미지가 남아있는 경우)
cd /opt/roche_nxt
docker compose -f docker-compose.prod.yml up -d --no-deps --force-recreate roche-nxt-web

# DB 복원
cp web_ui/orders.db.bak_YYYYMMDD web_ui/orders.db
docker compose -f docker-compose.prod.yml restart roche-nxt-web
```

---

*EONE 이전 패치: [EONELAB_PATCH_v1.1.md](EONELAB_PATCH_v1.1.md)*  
*전체 업그레이드 가이드: [docs/UPGRADE.md](../docs/UPGRADE.md)*
