# Roche_nxt — 운영 지침서

이 문서는 Roche_nxt를 **내부에서 개발·유지보수하는 담당자**(당신)와 **고객
서버에 배포·유지보수하는 담당자**가 일상적으로 수행하는 작업을 시나리오
단위로 정리한 런북입니다.

관련 문서:

- `LICENSE.md` — 라이선스 메커니즘 (왜 이렇게 설계했는지)
- `docs/INSTALL.md` — 단순 설치 매뉴얼 (고객에게 전달 가능)
- `docs/USER_GUIDE_WEB.md` / `docs/USER_GUIDE_CLI.md` — 최종 사용자용

## 목차

1. [아키텍처 & 구성요소 한눈에](#1-아키텍처--구성요소-한눈에)
2. [시나리오 A: 내부 개발·테스트](#2-시나리오-a-내부-개발테스트)
3. [시나리오 B: 고객 초기 배포 (폐쇄망 포함)](#3-시나리오-b-고객-초기-배포-폐쇄망-포함)
4. [시나리오 C: 기능 추가/연장 (라이선스 갱신)](#4-시나리오-c-기능-추가연장-라이선스-갱신)
5. [시나리오 D: 이미지/코드 업데이트 배포](#5-시나리오-d-이미지코드-업데이트-배포)
6. [시나리오 E: 일상 운영(시작·중지·로그·백업)](#6-시나리오-e-일상-운영시작중지로그백업)
7. [시나리오 F: 장애 대응 & 복구](#7-시나리오-f-장애-대응--복구)
8. [부록: 기능 플래그 레퍼런스](#부록-기능-플래그-레퍼런스)
9. [부록: 명령어 퀵 레퍼런스](#부록-명령어-퀵-레퍼런스)

---

## 1. 아키텍처 & 구성요소 한눈에

```
┌─────────────── 호스트 (Linux + Docker) ───────────────┐
│                                                        │
│   roche_nxt_web  ◄── 브라우저 (http://host:8080)       │
│      │                                                 │
│      ├─ Flask + IGV.js + license.py (Ed25519 검증)     │
│      ├─ /roche_nxt/license/license.json  (read-only)   │
│      ├─ /liftover/hg38ToHg19.over.chain.gz (read-only) │
│      └─ /var/run/docker.sock → 아래 이미지를 spawn     │
│                                                        │
│   roche_nxt_analysis  ◄── Nextflow 파이프라인 실행     │
│      └─ BWA, fgbio, VarDict, SnpEff, mosdepth ...      │
└────────────────────────────────────────────────────────┘
```

**주요 산출물**

| 파일/디렉터리                        | 역할                                                       |
|--------------------------------------|------------------------------------------------------------|
| `docker-compose.yml`                 | **개발용** — 소스 bind-mount + `DEV_MODE=1`                |
| `docker-compose.prod.yml`            | **프로덕션용** — bind-mount 없음, 라이선스 필수            |
| `.env` / `.env.example`              | 런타임 환경 변수 (포트, UID/GID, 호스트 경로 등)           |
| `web_ui/license.py`                  | 라이선스 로더. `DEV_MODE=1` 이면 우회, 아니면 서명 검증    |
| `web_ui/_vendor_keys/license_pubkey.b64` | 이미지에 박히는 공개키 (git-tracked)                   |
| `~/.roche_nxt_keys/license_signing_key.b64` | 개인 서명키 (절대 외부 반출 금지)                   |
| `tools/keygen.py`, `tools/issue_license.py` | 키 생성 / 라이선스 발급 CLI                         |
| `deploy/licenses/<고객>.json`        | 고객별 발급 라이선스 (git-ignored)                         |
| `deploy/images/*.tar.gz`             | 배포용 Docker 이미지 tarball                               |

**기능 플래그의 진실의 원천 (single source of truth)**

- 프로덕션: `license.json` 에 서명된 `features` 필드 → `web_ui/license.py::load()`
- 개발 모드 (`DEV_MODE=1`): `.env` 의 `ENABLE_*` 값을 fallback 으로 사용

→ **고객은 `.env` 수정으로 유료 기능을 켤 수 없음.**

---

## 2. 시나리오 A: 내부 개발·테스트

### 2.1 초기 1회 설정

```bash
# 리포지토리 클론 후
cp .env.example .env
vi .env    # 최소 항목: HOST_DIR, FASTQ_HOST_DIR, BED_HOST_DIR, LIFTOVER_HOST_DIR
           # DEV_MODE=1 유지
make build
```

### 2.2 매일 사용

```bash
make up          # 웹 UI 기동 (http://localhost:${WEB_PORT:-8080})
make logs        # 실시간 로그
make down        # 종료
make restart     # 템플릿/정적 자원 변경만 반영 (코드는 bind-mount 라 즉시)
```

`docker-compose.yml` 이 `web_ui/` 를 bind-mount 하므로 **Python 파일 수정은
`docker compose restart roche-nxt-web` 이면 반영**됩니다. `nextflow.config`,
`modules/*.nf`, `containers/*` 를 바꿨을 때만 분석 이미지 재빌드가 필요:

```bash
make build-analysis
```

### 2.3 개발 모드의 특징

- `DEV_MODE=1` → `license.py` 가 서명 검증을 **완전히 건너뜀**
- 기능 플래그는 `.env` 의 `ENABLE_LONGITUDINAL`, `ENABLE_IGV`,
  `ENABLE_HG19_VIEW` 로 개별 토글 가능
- 라이선스 파일 없어도 서버 기동됨
- 웹 UI 상단 또는 `/api/features` 응답에 `license.dev_mode: true` 가 노출됨

### 2.4 고객 동일 조건으로 로컬 재현이 필요할 때

내부에서 라이선스 기반 동작을 테스트하려면:

```bash
# 1) 개발용 라이선스 발급 (perpetual, 전 기능)
make license CUSTOMER="Internal Dev" EXPIRES=never \
             FEATURES=longitudinal,igv,hg19_view

# 2) license 디렉터리에 복사
mkdir -p license
cp deploy/licenses/internal_dev.json license/license.json

# 3) DEV_MODE 끄고 prod 컴포즈로 기동
sed -i 's/^DEV_MODE=.*/DEV_MODE=0/' .env
make prod-up
```

`make prod-down` 으로 정리. `DEV_MODE` 는 다시 `1` 로 되돌려두세요.

---

## 3. 시나리오 B: 고객 초기 배포 (폐쇄망 포함)

> **완전 오프라인(Docker 조차 없는) 서버에 USB 하나로 설치**하려면
> [`docs/OFFLINE_INSTALL.md`](OFFLINE_INSTALL.md) 의 자동화 플로우
> (`make usb-bundle` + 11단계 설치 스크립트) 를 사용하세요. 아래 내용은
> 고객 서버에 이미 Docker 가 있는 경우의 수동 절차입니다.

### 3.1 담당자 측 — 전달 번들 만들기

**사전 조건**: `make keygen` 이 한 번 실행되어 `web_ui/_vendor_keys/license_pubkey.b64`
가 이미지에 박혀 있어야 합니다. 키 쌍은 **프로젝트 전 생명주기에 걸쳐 1회**만
생성합니다.

```bash
# 1) 고객용 라이선스 발급
make license \
    CUSTOMER="ABC Hospital" \
    EXPIRES=2027-04-20 \
    FEATURES=longitudinal,igv
# → deploy/licenses/abc_hospital.json

# 2) 이미지 + 프로덕션 컴포즈 + .env.example 번들링
make prod-save
# → deploy/images/roche_nxt_web.tar.gz
# → deploy/images/roche_nxt_analysis.tar.gz
# → deploy/package/docker-compose.yml  (prod 버전)
# → deploy/package/.env.example
# → deploy/package/README.md           (LICENSE.md 사본)
```

고객에게 전달할 것들:

| 파일                                          | 크기 예시 | 전달 매체                |
|-----------------------------------------------|-----------|--------------------------|
| `deploy/images/roche_nxt_web.tar.gz`          | ~500 MB   | USB/SFTP/물리 매체       |
| `deploy/images/roche_nxt_analysis.tar.gz`     | ~3–5 GB   | USB/SFTP                 |
| `deploy/package/docker-compose.yml`           | ~1 KB     | 이메일/USB               |
| `deploy/package/.env.example`                 | ~1 KB     | 이메일/USB               |
| `deploy/licenses/abc_hospital.json`           | ~500 B    | **별도 채널** (이메일)   |

> **TIP**: 라이선스 파일은 이미지 번들과 **분리된 경로**로 보내는 것을
> 권장합니다. 이미지가 유출되어도 라이선스 없이는 기동되지 않으므로,
> 2중 잠금 효과가 있습니다.

필요하면 `data/` 하위의 레퍼런스 파일(BED/chain/BWA index 등)도 별도
tarball 로 만들어 전달합니다. 특히 hg19 뷰 기능을 넣은 경우
`hg38ToHg19.over.chain.gz` 를 반드시 포함하세요 (용량 ~200 MB).

### 3.2 고객 서버 측 — 설치

폐쇄망이라도 순서는 같습니다. 호스트에 Docker(CE 20+)와 Docker Compose v2
가 설치되어 있어야 합니다.

```bash
# 1) 이미지 로드
docker load < roche_nxt_web.tar.gz
docker load < roche_nxt_analysis.tar.gz

# 2) 작업 디렉터리 배치
mkdir -p /opt/roche_nxt && cd /opt/roche_nxt
cp /path/to/docker-compose.yml .            # 프로덕션 버전
cp /path/to/.env.example .env

# 3) 라이선스 설치
mkdir -p license
cp /path/to/abc_hospital.json license/license.json
chmod 0444 license/license.json             # 실수 편집 방지

# 4) 데이터/레퍼런스 디렉터리 배치
mkdir -p results work log
# FASTQ_HOST_DIR, BED_HOST_DIR, LIFTOVER_HOST_DIR 는 .env 에서 지정

# 5) .env 편집 — 필수 항목만
#   WEB_PORT=8080
#   UID=$(id -u)  /  GID=$(id -g)
#   FASTQ_HOST_DIR=/data/fastq
#   BED_HOST_DIR=/data/bed
#   LIFTOVER_HOST_DIR=/data/liftover      (hg19 뷰 사용 시만)
#   TZ=Asia/Seoul
# ※ DEV_MODE 와 ENABLE_* 은 넣지 않습니다 (prod compose 가 무시합니다).

# 6) 기동
docker compose -f docker-compose.yml up -d

# 7) 확인
docker compose logs roche-nxt-web | head -30
#   → "License OK: customer=ABC Hospital expires=2027-04-20 features=..."
curl -I http://localhost:8080/
```

라이선스 문제 발생 시 컨테이너는 exit 2 로 종료되고 stderr 에 명확한
메시지가 남습니다. 가능 원인:

- `license/license.json` 이 없음
- 이미지 공개키와 매칭되지 않는 서명 (잘못 전달된 라이선스)
- `expires` 가 과거 시각
- JSON 자체가 손상됨 (예: Windows 로 옮기면서 CRLF 변환)

### 3.3 에어갭 팁

- **시간 동기화**: 폐쇄망에서는 외부 NTP 가 없어 시계가 틀어지면 라이선스
  `expires` 검증이 실패할 수 있습니다. 사내 NTP 를 지정하거나, perpetual
  라이선스(`EXPIRES=never`)를 발급해 이 리스크를 제거하세요.
- **Nextflow 프로파일**: 호스트 쪽에서 수동 실행할 일이 있다면 `-profile docker`
  를 사용합니다 (`docker.offline=true` 가 이미 기본 설정되어 있어
  이미지 pull 시도를 하지 않음).
- **이미지 갱신**: 이 페이지의 "시나리오 D" 절차와 동일합니다.

---

## 4. 시나리오 C: 기능 추가/연장 (라이선스 갱신)

고객이 "IGV 기능 추가해 주세요" / "1년 연장해 주세요" 라고 요청해 왔을 때,
**이미지 재빌드나 재배포 없이** 라이선스 파일만 교체하면 끝납니다.

### 4.1 담당자 측

```bash
make license \
    CUSTOMER="ABC Hospital" \
    EXPIRES=2028-04-20 \
    FEATURES=longitudinal,igv,hg19_view
# → deploy/licenses/abc_hospital.json (덮어씀)
```

`CUSTOMER` 문자열은 기존과 동일하게 유지해야 파일명이 같은 slug 로
생성되어 관리가 쉽습니다.

### 4.2 고객 서버 측

```bash
cd /opt/roche_nxt
cp /path/to/abc_hospital.json license/license.json
chmod 0444 license/license.json
docker compose -f docker-compose.yml restart roche-nxt-web
```

30초 이내에 새 기능이 활성화됩니다. 웹 UI 재로드 시 Variant Review 상단의
hg38/hg19 토글이 나타나는 등 즉시 체감됩니다.

### 4.3 기능 회수 (다운그레이드)

같은 절차로, `FEATURES` 리스트에서 해당 키를 제외한 라이선스를 발급 →
교체 → restart. 다음 시작부터 해당 기능은 UI에서 사라집니다.

---

## 5. 시나리오 D: 이미지/코드 업데이트 배포

버그 픽스나 기능 추가로 `roche_nxt_web` 이미지를 새로 만들어 고객에
배포해야 할 때.

### 5.1 담당자 측

```bash
git pull                        # 또는 원하는 브랜치로 체크아웃
make build-web                  # 웹 이미지만 리빌드
make prod-save                  # tar.gz 재생성
```

> 공개키(`web_ui/_vendor_keys/license_pubkey.b64`)는 그대로이므로
> **기존 고객 라이선스는 여전히 유효**합니다. 키 교체가 필요한 경우는
> 시나리오 F.3 참고.

### 5.2 고객 서버 측

```bash
cd /opt/roche_nxt
docker compose -f docker-compose.yml down

# 기존 이미지 제거(선택; 디스크 공간 확보)
docker image rm roche_nxt_web:latest || true

docker load < /path/to/roche_nxt_web.tar.gz

docker compose -f docker-compose.yml up -d
docker compose -f docker-compose.yml logs --tail=40 roche-nxt-web
```

분석 이미지(`roche_nxt_analysis`)는 파이프라인 코드를 바꿨을 때만 갱신
합니다. 용량이 크므로 불필요하게 재배포하지 마세요.

---

## 6. 시나리오 E: 일상 운영(시작·중지·로그·백업)

### 6.1 명령 요약

| 작업           | 개발 환경              | 프로덕션                                    |
|----------------|------------------------|---------------------------------------------|
| 시작           | `make up`              | `make prod-up`                              |
| 중지           | `make down`            | `make prod-down`                            |
| 재시작         | `make restart`         | `docker compose -f docker-compose.prod.yml restart roche-nxt-web` |
| 로그(follow)   | `make logs`            | `make prod-logs`                            |
| 상태 확인      | `make status`          | `docker compose -f docker-compose.prod.yml ps` |

### 6.2 데이터 디렉터리 이해

컨테이너 내부 경로는 고정(`/roche_nxt/results`, `/roche_nxt/work`,
`/roche_nxt/log`). 호스트 측 실제 경로는 `.env` 에서 바꿉니다.

| 컨테이너 경로             | .env 변수            | 내용                                 |
|---------------------------|----------------------|--------------------------------------|
| `/roche_nxt/results`      | `RESULTS_HOST_DIR`   | 분석 최종 산출물 (BAM, VCF, HTML)    |
| `/roche_nxt/work`         | `WORK_HOST_DIR`      | Nextflow work 디렉터리 (중간 파일)   |
| `/roche_nxt/log`          | `LOG_HOST_DIR`       | 웹 UI 및 파이프라인 로그             |
| `/fastq_source` (ro)      | `FASTQ_HOST_DIR`     | 입력 FASTQ 소스                      |
| `/bed_source` (ro)        | `BED_HOST_DIR`       | 타겟 BED 파일                        |
| `/liftover` (ro)          | `LIFTOVER_HOST_DIR`  | hg38→hg19 chain 파일 (hg19 뷰 시만)  |
| `/roche_nxt/license` (ro) | `LICENSE_HOST_DIR`   | `license.json` (prod 전용)           |

### 6.3 백업

- `results/`, `log/` 는 장기 보존 가치가 있으므로 정기 스냅샷 권장.
- `work/` 는 `delete_intermediate=Y` 옵션을 켜면 Nextflow 가 자동 정리.
  수동 정리: `rm -rf work/<order_id>`.
- DB: `log/roche_nxt.db` (SQLite). 간단히 파일 복사로 백업 가능.
  복사 중 쓰기 일관성이 신경 쓰인다면 `sqlite3 log/roche_nxt.db ".backup ..."`.
- 라이선스: `license/license.json` 은 원본을 담당자 측에서 보관 중이므로
  고객 서버의 사본이 손상되어도 재전송만으로 복구됩니다.

### 6.4 리소스 튜닝

`.env` 에서 조정. `0` 은 자동(호스트 전체 사용):

```
MAX_CPUS=16
MAX_MEMORY=64
MAX_CONCURRENT_SAMPLES=3
```

`MAX_CONCURRENT_SAMPLES` 는 웹 UI 큐에서 **동시 실행되는 오더 수**의 상한.
`MAX_CPUS`, `MAX_MEMORY` 는 각 Nextflow 런이 쓸 수 있는 총량.

---

## 7. 시나리오 F: 장애 대응 & 복구

### 7.1 웹 컨테이너가 기동 안 될 때

```bash
docker compose -f docker-compose.prod.yml logs --tail=60 roche-nxt-web
```

흔한 원인:

- `LicenseError: license file not found` → `license/license.json` 경로 확인
- `LicenseError: signature verification failed` → 잘못된 라이선스 또는
  공개키가 다른 이미지. 고객에게 재발급한 라이선스를 다시 전달하거나,
  최신 이미지(공개키 포함)로 업데이트.
- `LicenseError: license expired (2026-..)` → 갱신 라이선스 발급 (시나리오 C)
- 포트 충돌(`WEB_PORT` 이미 사용 중) → `.env` 에서 다른 포트로 변경

### 7.2 분석이 끊기거나 실패할 때

```bash
docker exec -it roche_nxt_web bash
tail -n 200 /roche_nxt/log/nextflow_<order_id>.log
ls /roche_nxt/work/<order_id>
```

- **Nextflow 재시작**: 웹 UI에서 해당 오더 → "재시작"/"Resume" 버튼. 내부적으로
  `-resume` 이 전달되어 이미 완료된 단계는 캐시 사용.
- **work 디렉터리 꼬였을 때**: 해당 오더의 `work/<id>` 를 통째로 삭제 후
  웹 UI 에서 재시작. Longitudinal 재사용 오더는 원본 work 를 공유하므로
  삭제에 주의 (UI 가 "force re-run" 을 차단함).

### 7.3 서명키 유출/손실 (비상시)

영향 범위: **모든 고객 라이선스를 재발급해야 함** + **모든 고객 이미지를 재배포해야 함.**

```bash
# 1) 새 키 쌍 생성
make keygen    # 기존 web_ui/_vendor_keys/license_pubkey.b64 가 덮어쓰기됨

# 2) 이미지 재빌드 (새 공개키 baked in)
make build-web

# 3) 모든 고객 라이선스 재발급
for CUST in "ABC Hospital" "XYZ Lab" ...; do
    make license CUSTOMER="$CUST" EXPIRES=... FEATURES=...
done

# 4) 각 고객 사이트에 새 이미지 + 새 라이선스 배포
make prod-save
```

유출 대응은 **운영 체계 전체가 흔들리는** 이벤트이므로, `~/.roche_nxt_keys/`
는 오프라인 USB + 암호화된 클라우드에 2중 백업하세요.

### 7.4 시계 후퇴로 인한 라이선스 거부

드물지만 폐쇄망에서 가능한 시나리오. 단기 대응:

- 고객 서버의 시계를 올바르게 맞추게 안내 (`timedatectl`, 사내 NTP)
- 재발급이 더 빠르면 perpetual 라이선스로 임시 교체 (보안적으로는 후퇴이므로
  문서화 후 다음 계약 갱신 시 정상 만기로 복귀)

---

## 부록: 기능 플래그 레퍼런스

| 키             | 설명                                              | UI에 미치는 영향                                    |
|----------------|---------------------------------------------------|-----------------------------------------------------|
| `longitudinal` | Baseline/Followup 시계열 분석                     | 오더 생성 화면의 오더 타입 선택 + Longitudinal 탭   |
| `igv`          | Variant Review 안에 IGV.js 뷰어 임베드            | Variant Review 우측 IGV 패널, BAM/BAI 서빙 엔드포인트 |
| `hg19_view`    | Variant Review 의 hg38/hg19 좌표 토글 (표시 전용) | 필터 바 좌상단의 `Assembly [hg38|hg19]` 토글        |

- 이 표에 없는 모든 "기능 같은 것"은 flag-free 입니다. 새로운 유료 기능을 추가할 때는 `web_ui/license.py::ALL_FEATURES` 에 키를 등록하고 이 문서에 반영합니다.
- `.env` 의 `ENABLE_*` 는 **개발 모드에서만** 의미가 있습니다. 고객 환경에서는 무시됩니다.

---

## 부록: 명령어 퀵 레퍼런스

```bash
# === 개발 ===
make build                   # 전체 이미지 빌드
make build-web               # 웹만 재빌드
make build-analysis          # 분석만 재빌드
make up / down / restart     # 개발 스택
make logs / status           # 관측

# === 라이선스 ===
make keygen                  # 최초 1회. 개인키는 ~/.roche_nxt_keys/
make license CUSTOMER="..." EXPIRES=YYYY-MM-DD FEATURES=...
make license CUSTOMER="..." EXPIRES=never      FEATURES=...
make license CUSTOMER="..." NO_EXPIRY=1        FEATURES=...

# === 프로덕션 ===
make prod-up / prod-down / prod-logs
make prod-save               # 고객 배포 번들 생성 → deploy/images + deploy/package

# === 라이선스 상태 확인 (서버 내부에서) ===
curl -s http://localhost:8080/api/features | jq
#   "license": { "customer": "...", "expires": "...", "dev_mode": false }

# === 고객 사이트 빠른 리스타트 ===
docker compose -f docker-compose.yml restart roche-nxt-web
```

---

## 체크리스트

**새 고객 배포 시**

- [ ] `make keygen` 이 과거에 1회 이상 실행되어 있는가?
- [ ] `web_ui/_vendor_keys/license_pubkey.b64` 가 커밋되어 있고 이미지에 포함되는가?
- [ ] `make license CUSTOMER=... EXPIRES=... FEATURES=...` 실행 완료
- [ ] `make prod-save` 로 번들 생성 완료
- [ ] 라이선스는 이미지와 **별도 채널**로 전달하는가?
- [ ] `docker-compose.prod.yml` 을 보냈는가 (dev 버전이 아닌)?
- [ ] 고객에게 `DEV_MODE` 와 `ENABLE_*` 는 설정하지 않는다고 고지했는가?

**라이선스 갱신 시**

- [ ] `CUSTOMER` 문자열을 이전과 동일하게 맞췄는가? (파일명 slug 동일)
- [ ] `FEATURES` 에서 기존 기능을 실수로 빠뜨리지 않았는가?
- [ ] 고객이 교체 후 `restart` 를 수행했는가?
- [ ] `/api/features` 응답의 `license.expires`, `features.*` 가 기대대로인가?
