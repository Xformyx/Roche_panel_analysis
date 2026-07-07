# Roche_nxt 업그레이드 가이드

> **대상**: 기존에 Roche_nxt가 설치된 병원 서버 (BSCH, EONE 등)  
> **현재 버전**: v1.3.0

---

## 업그레이드 방법 선택

| 상황 | 권장 방법 | 스크립트 |
|------|-----------|----------|
| 병원 서버에서 GitHub 접속 가능 | **방법 A — GitHub 자동 업그레이드** | `upgrade_from_github.sh` |
| 인터넷 차단 / USB·SCP 전달 | **방법 B — 이미지 파일 교체** | `save_patch.sh` → `upgrade_from_image.sh` |

---

## 방법 A — GitHub 자동 업그레이드 (권장)

BSCH, EONE 서버는 GitHub에 접근 가능합니다.  
스크립트 하나로 소스 업데이트 → 이미지 재빌드 → 서비스 재시작을 자동으로 수행합니다.

### A-1. 스크립트 실행

```bash
# 설치 디렉터리로 이동 (모르면 아래 명령으로 찾기)
find /opt /home -name "docker-compose.prod.yml" 2>/dev/null | head -5

cd /opt/roche_nxt   # 실제 설치 경로로 변경

# 최신 버전으로 업그레이드
bash deploy/scripts/upgrade_from_github.sh --install-dir /opt/roche_nxt

# 특정 버전으로 업그레이드 (권장: 태그 지정)
bash deploy/scripts/upgrade_from_github.sh --install-dir /opt/roche_nxt --tag v1.3.0
```

### A-2. 스크립트가 수행하는 작업

1. ✅ 실행 중인 분석 확인 (중인 분석이 있으면 경고)
2. ✅ 중요 파일 자동 백업 (`orders.db`, `.env`, `nextflow.config`)
3. ✅ GitHub에서 최신 소스 pull
4. ✅ Web 이미지 재빌드 (~2분)
5. ✅ 서비스 재시작 (기존 분석 데이터 보존)
6. ✅ 기동 확인

### A-3. 확인

웹 브라우저에서 접속 후 사이드바 하단에 새 버전이 표시되면 완료.

```
http://<서버 IP>:8080
```

---

## 방법 B — 이미지 파일 교체 (오프라인)

GitHub 접속 불가 환경에서 개발자가 만든 패치 패키지를 USB/SCP로 전달받아 적용합니다.  
두 단계로 진행됩니다: **개발 서버에서 패키지 생성 → 병원 서버에서 적용**.

### B-1. 개발 서버 — 패치 패키지 생성

```bash
cd /home/ken/Roche_nxt

# Web 이미지만 포함 (패치용, 빠름)
bash deploy/scripts/save_patch.sh --web-only

# Web + Analysis 이미지 모두 포함 (전체 설치 대체 시)
bash deploy/scripts/save_patch.sh
```

`deploy/patches/roche_patch_v1.3.0/` 디렉터리에 다음 파일이 생성됩니다:

| 파일 | 크기 | 내용 |
|------|------|------|
| `roche_nxt_web_v1.3.0.tar.gz` | ~200 MB | Web Docker 이미지 |
| `Roche_nxt_v1.3.0.tar.gz` | ~50 MB | 소스 파일 |
| `apply_patch.sh` | — | 병원 서버 적용 스크립트 |
| `PATCH_NOTES.md` | — | 변경 내용 및 적용 방법 |

> 분석 이미지(`roche_nxt_analysis`)는 파이프라인 도구가 변경되지 않는 한 포함 불필요합니다.

### B-2. 패치 파일 전송

```bash
# SCP로 전송 (개발 서버 → 병원 서버)
scp -r deploy/patches/roche_patch_v1.3.0/ user@hospital-server:/tmp/

# 또는 tar로 묶어서 전송
tar -czf roche_patch_v1.3.0.tar.gz -C deploy/patches roche_patch_v1.3.0
scp roche_patch_v1.3.0.tar.gz user@hospital-server:/tmp/
```

### B-3. 병원 서버 — 패치 적용

```bash
# SCP 전송의 경우
cd /tmp/roche_patch_v1.3.0
bash apply_patch.sh

# tar로 묶어서 전송한 경우
cd /tmp
tar -xzf roche_patch_v1.3.0.tar.gz
cd roche_patch_v1.3.0
bash apply_patch.sh

# 설치 경로를 명시적으로 지정하는 경우
bash apply_patch.sh --install-dir /opt/roche_nxt
```

스크립트가 자동으로 수행하는 작업:
1. ✅ 실행 중인 분석 확인
2. ✅ 중요 파일 백업 (`orders.db`, `.env`, `nextflow.config`)
3. ✅ 소스 파일 교체 (DB·환경설정 보존)
4. ✅ Docker 이미지 로드
5. ✅ 서비스 재시작 및 기동 확인

---

## 업그레이드 시 주의사항

### ✅ 보존되는 데이터

- `orders.db` — 모든 오더, 분석 이력
- `results/` — 분석 결과 파일
- `log/` — 실행 로그
- `.env` — 서버별 환경 설정

### ⚠️ 실행 중인 분석이 있는 경우

```bash
# 실행 중인 분석 컨테이너 확인
docker ps --filter "name=nxt_"

# 분석이 완료될 때까지 대기 후 업그레이드하는 것을 권장합니다.
# 불가피한 경우: 강제 종료 후 업그레이드
# (해당 오더는 Web UI에서 "처음부터 재실행" 필요)
```

### ⚠️ DB 스키마 변경

새 버전에서 DB 컬럼이 추가된 경우, Web 컨테이너 시작 시 자동으로 마이그레이션됩니다.  
기존 데이터는 보존됩니다.

---

## 롤백 방법

업그레이드 후 문제가 발생한 경우:

```bash
# 백업에서 이전 이미지 태그 확인
BACKUP_DIR=/opt/roche_nxt/backup/YYYYMMDD_HHMMSS   # 실제 경로로 변경

# 방법 A: 이전 이미지 태그가 남아있는 경우
docker images | grep roche_nxt_web
# roche_nxt_web  v1.2.0  ...  (이전 태그가 있으면)
docker tag roche_nxt_web:v1.2.0 roche_nxt_web:latest
docker compose -f docker-compose.prod.yml up -d --no-deps --force-recreate roche-nxt-web

# 방법 B: DB를 백업 시점으로 복원
cp $BACKUP_DIR/orders.db web_ui/orders.db
docker compose -f docker-compose.prod.yml restart roche-nxt-web
```

---

## 버전별 변경 이력

| 버전 | 주요 변경 내용 | 레퍼런스 데이터 변경 | 분석 이미지 재빌드 필요 |
|------|---------------|---------------------|------------------------|
| **v1.3.0** | QC ±250bp 지표, QC 재실행, 3-BED 시스템 | ❌ 불필요 | ❌ 불필요 |
| v1.2.0 | 라이선스 시스템 제거, 전 기능 기본 활성화 | ❌ 불필요 | ❌ 불필요 |
| v1.1.0 | hg19 지원, API Key, API Explorer | ✅ hg19 추가 필요 | ❌ 불필요 |
| v1.0.0 | 초기 릴리스 | — | — |

---

*관련 문서: [INSTALL_IMAGE.md](INSTALL_IMAGE.md) | [INSTALL_BUILD.md](INSTALL_BUILD.md)*
