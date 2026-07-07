# Roche_nxt 설치 가이드 — 방법 A: Docker 이미지 오프라인 설치

> **대상**: 인터넷이 차단된 폐쇄망 서버 또는 사전 빌드된 이미지를 USB/SCP로 전달받는 경우  
> **해당 병원**: BSCH, EONE (초기 설치 시)  
> **버전**: v1.3.0

---

## 개요

개발자가 Docker 이미지를 미리 빌드하여 압축 파일로 전달합니다.  
병원 서버에서는 코드 빌드 없이 이미지 로드 + 설정 파일 편집만으로 설치 완료됩니다.

```
[개발 서버]                      [병원 서버]
  ↓ docker save                    ↓ docker load
roche_nxt_web.tar.gz  ─── USB ──▶ roche_nxt_web:latest
roche_nxt_analysis.tar.gz        roche_nxt_analysis:latest
  ↓ tar                            ↓ tar
roche_data_hg38.tar  ──── FTP ──▶ /data/roche_data/
roche_data_hg19.tar
```

---

## 전달 파일 목록

| 파일 | 크기 (예상) | 전달 방법 |
|------|------------|-----------|
| `roche_nxt_web.tar.gz` | ~200 MB | USB |
| `roche_nxt_analysis.tar.gz` | ~8 GB | USB 또는 SCP |
| `roche_data_hg38.tar` | ~60 GB | FTP 또는 외장 HDD |
| `roche_data_hg19.tar` | ~20 GB | FTP 또는 외장 HDD (hg19 필요 시) |
| `Roche_nxt/` (소스 디렉터리) | ~50 MB | USB |

> 레퍼런스 데이터(roche_data_*.tar)는 한 번만 설치하면 이후 업그레이드 시 불필요합니다.

---

## 사전 요구사항

```bash
# Docker Engine 설치 확인
docker --version       # Docker Engine 24.x 이상
docker compose version # Docker Compose v2.x 이상

# 디스크 여유 공간 확인 (hg38 단독: 최소 120 GB, hg19 포함: 최소 150 GB)
df -h /opt
```

---

## 설치 절차

### Step 1 — 소스 디렉터리 배치

```bash
# 설치 위치 결정 (예: /opt/roche_nxt)
INSTALL_DIR=/opt/roche_nxt
sudo mkdir -p $INSTALL_DIR
sudo cp -r /mnt/usb/Roche_nxt/* $INSTALL_DIR/
sudo chown -R $USER:$USER $INSTALL_DIR
cd $INSTALL_DIR
```

### Step 2 — Docker 이미지 로드

```bash
# 웹 이미지 로드 (~200 MB, 30초 내)
docker load < /mnt/usb/roche_nxt_web.tar.gz

# 분석 이미지 로드 (~8 GB, 5~10분)
docker load < /mnt/usb/roche_nxt_analysis.tar.gz

# 로드 확인
docker images | grep roche_nxt
# roche_nxt_web      latest   ...
# roche_nxt_analysis latest   ...
```

### Step 3 — 레퍼런스 데이터 압축 해제

```bash
DATA_DIR=/data/roche_data   # 레퍼런스 데이터를 놓을 경로 (충분한 디스크 공간 필요)
sudo mkdir -p $DATA_DIR

# hg38 데이터 (필수)
echo "hg38 압축 해제 중 (약 20~40분)..."
tar -xf /mnt/usb_data/roche_data_hg38.tar -C $DATA_DIR

# hg19 데이터 (선택, hg19 분석이 필요한 경우)
echo "hg19 압축 해제 중 (약 10~20분)..."
tar -xf /mnt/usb_data/roche_data_hg19.tar -C $DATA_DIR

# 확인
ls $DATA_DIR/refs/hg38/
```

### Step 4 — 환경 설정 파일 작성

```bash
cd $INSTALL_DIR
cp .env.example .env
nano .env   # 또는 vi .env
```

`.env` 필수 설정:

```bash
# ─── 서버별 설정 ─────────────────────────────────────
HOST_DIR=/opt/roche_nxt          # 이 설치 디렉터리의 절대 경로
DATA_HOST_DIR=/data/roche_data   # Step 3에서 압축 해제한 레퍼런스 데이터 경로
FASTQ_HOST_DIR=/data/fastq       # FASTQ 파일이 놓이는 디렉터리
BED_HOST_DIR=/data/roche_data/bed/hg38  # BED 파일 디렉터리

# ─── 포트 ─────────────────────────────────────────────
WEB_PORT=8080                    # 웹 UI 접속 포트 (방화벽 오픈 필요)

# ─── 옵션 ─────────────────────────────────────────────
TZ=Asia/Seoul
UID=1000                         # id -u 결과값
GID=1000                         # id -g 결과값
DOCKER_GID=                      # getent group docker | cut -d: -f3 결과값
```

UID/GID/DOCKER_GID 확인 방법:

```bash
id -u; id -g
getent group docker | cut -d: -f3
```

### Step 5 — 서비스 시작

```bash
cd $INSTALL_DIR
docker compose -f docker-compose.prod.yml up -d

# 상태 확인
docker compose -f docker-compose.prod.yml ps
docker logs roche_nxt_web --tail=20
```

### Step 6 — 접속 확인

```
http://<서버 IP>:8080
```

사이드바 하단에 `Ver.1.3.0` 이 표시되면 설치 완료.

---

## 서비스 관리

```bash
cd /opt/roche_nxt

# 시작
docker compose -f docker-compose.prod.yml up -d

# 중지
docker compose -f docker-compose.prod.yml down

# 로그 확인
docker logs roche_nxt_web -f

# 재시작
docker compose -f docker-compose.prod.yml restart
```

---

## 디렉터리 구조 (설치 후)

```
/opt/roche_nxt/          ← INSTALL_DIR (소스 + 런타임)
  docker-compose.prod.yml
  .env
  nextflow.config
  main.nf
  web_ui/
  modules/
  workflows/
  log/                   ← 분석 로그 (자동 생성)
  results/               ← 분석 결과 (자동 생성)

/data/roche_data/        ← DATA_HOST_DIR (레퍼런스)
  refs/hg38/
  refs/hg19/
  bed/
  blocklist/
  dbsnp/

/data/fastq/             ← FASTQ_HOST_DIR (입력 파일)
```

---

## 문제 해결

| 증상 | 확인 사항 |
|------|-----------|
| 웹 UI 접속 불가 | `docker ps`로 컨테이너 상태 확인, 방화벽 포트 오픈 여부 |
| 분석 시작 안 됨 | `docker logs roche_nxt_web` 에러 메시지 확인 |
| 레퍼런스 파일 없음 | `DATA_HOST_DIR` 경로와 `ls $DATA_HOST_DIR/refs/hg38/` 확인 |
| 이미지 없음 오류 | `docker images | grep roche` 로 이미지 로드 여부 확인 |

---

*다음 단계: 업그레이드 방법은 [UPGRADE.md](UPGRADE.md) 참조*
