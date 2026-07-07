# Roche_nxt 설치 가이드 — 방법 B: GitHub 소스 빌드 설치

> **대상**: GitHub 접속 가능한 서버에서 소스를 직접 빌드하여 설치하는 경우  
> **해당 병원**: SNUH (서울대학교병원) 및 이후 신규 설치 기관  
> **버전**: v1.3.0

---

## 개요

GitHub에서 소스를 내려받아 Docker 이미지를 직접 빌드합니다.  
레퍼런스 데이터(hg38/hg19)는 FTP에서 별도로 다운로드합니다.  
이미지를 USB로 전달받을 필요 없이 최신 버전을 항상 직접 빌드 가능합니다.

```
GitHub (소스코드)  ──git clone──▶  병원 서버
                                    ↓ docker build
                               roche_nxt_web:latest
                               roche_nxt_analysis:latest

FTP (레퍼런스 데이터) ──wget──▶  /data/roche_data/
```

---

## 사전 요구사항

| 항목 | 요구 사양 |
|------|----------|
| OS | Ubuntu 20.04/22.04/24.04, Rocky Linux 8/9, CentOS 8+ |
| CPU | 16코어 이상 권장 |
| RAM | 64 GB 이상 권장 |
| 디스크 | 200 GB 이상 여유 (hg38+hg19 포함) |
| 인터넷 | GitHub, FTP 접근 가능 |
| Docker | Engine 24.x+, Compose v2.x+ |
| Git | 2.x+ |

```bash
# 요구사항 확인
docker --version && docker compose version && git --version
```

---

## Step 1 — Docker Engine 설치 (미설치 시)

```bash
# Ubuntu
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker   # 또는 로그아웃 후 재로그인

# Rocky Linux / CentOS
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

---

## Step 2 — 소스코드 클론

```bash
INSTALL_DIR=/opt/roche_nxt
sudo mkdir -p $INSTALL_DIR
sudo chown $USER:$USER $INSTALL_DIR

git clone https://github.com/Xformyx/Roche_panel_analysis.git $INSTALL_DIR
cd $INSTALL_DIR
git checkout v1.3.0   # 특정 버전 고정 (권장)
```

---

## Step 3 — Docker 이미지 빌드

### 3-1. Web 이미지 (빠름, ~2분)

```bash
cd $INSTALL_DIR
docker build -f web_ui/Dockerfile web_ui/ -t roche_nxt_web:latest
```

### 3-2. Analysis 이미지 (느림, 30분~2시간)

분석 파이프라인에 필요한 모든 바이오인포매틱스 도구를 빌드합니다.  
**한 번만 실행하면 이후 업그레이드 시 재빌드 불필요합니다.**

```bash
docker build -f containers/Dockerfile.all containers/ -t roche_nxt_analysis:latest
```

> **팁**: 빌드 중 실패하면 `--no-cache` 없이 다시 실행하면 중간부터 재개됩니다.

#### Analysis 이미지를 FTP에서 직접 받는 경우 (빌드 생략 가능)

개발자로부터 사전 빌드된 이미지 파일이 FTP에 제공된 경우:

```bash
# FTP에서 분석 이미지 다운로드
wget ftp://[FTP_SERVER]/roche_nxt/images/roche_nxt_analysis.tar.gz -O /tmp/roche_nxt_analysis.tar.gz

# 로드
docker load < /tmp/roche_nxt_analysis.tar.gz
```

### 3-3. 빌드 확인

```bash
docker images | grep roche_nxt
# roche_nxt_web      latest   ...
# roche_nxt_analysis latest   ...
```

---

## Step 4 — 레퍼런스 데이터 다운로드

```bash
DATA_DIR=/data/roche_data
sudo mkdir -p $DATA_DIR
sudo chown $USER:$USER $DATA_DIR
```

### hg38 데이터 (필수)

```bash
cd /tmp
wget ftp://[FTP_SERVER]/roche_nxt/data/roche_data_hg38.tar

echo "hg38 압축 해제 중 (~20~40분)..."
tar -xf roche_data_hg38.tar -C $DATA_DIR
```

### hg19 데이터 (SNUH 등 hg19 분석 필요 시)

```bash
wget ftp://[FTP_SERVER]/roche_nxt/data/roche_data_hg19.tar

echo "hg19 압축 해제 중 (~10~20분)..."
tar -xf roche_data_hg19.tar -C $DATA_DIR
```

### 데이터 확인

```bash
ls $DATA_DIR/refs/hg38/    # ucsc.hg38.fasta 등 확인
ls $DATA_DIR/refs/hg19/    # ucsc.hg19.fasta 등 확인 (hg19 사용 시)
ls $DATA_DIR/bed/hg38/     # NHL_bed/ 확인
```

> **FTP 서버 접속 정보**: 별도 제공된 FTP 접속 정보를 사용하세요.  
> 접속 정보 문의: 개발팀 (Xformyx)

---

## Step 5 — 환경 설정

```bash
cd $INSTALL_DIR
cp .env.example .env
nano .env
```

`.env` 설정:

```bash
# ─── 필수 경로 설정 ──────────────────────────────────
HOST_DIR=/opt/roche_nxt
DATA_HOST_DIR=/data/roche_data
FASTQ_HOST_DIR=/data/fastq          # FASTQ 파일 경로 (실제 경로로 변경)
BED_HOST_DIR=/data/roche_data/bed/hg38

# ─── 포트 ─────────────────────────────────────────────
WEB_PORT=8080

# ─── 사용자/그룹 ID ────────────────────────────────────
TZ=Asia/Seoul
UID=1000                             # echo $(id -u)
GID=1000                             # echo $(id -g)
DOCKER_GID=                          # getent group docker | cut -d: -f3
```

```bash
# ID 확인 명령어
echo "UID=$(id -u)  GID=$(id -g)  DOCKER_GID=$(getent group docker | cut -d: -f3)"
```

---

## Step 6 — FASTQ 디렉터리 생성

```bash
sudo mkdir -p /data/fastq
sudo chown $USER:$USER /data/fastq
# FASTQ 파일은 이 디렉터리에 넣으면 Web UI에서 자동으로 인식됩니다.
```

---

## Step 7 — 서비스 시작

```bash
cd $INSTALL_DIR
docker compose -f docker-compose.prod.yml up -d

# 상태 확인
docker compose -f docker-compose.prod.yml ps
docker logs roche_nxt_web --tail=30
```

---

## Step 8 — 접속 및 초기 설정

```
http://<서버 IP>:8080
```

1. 우측 사이드바 **설정** → Fastq 디렉터리 경로 확인
2. **설정** → 외부 연동 API Key 발급 (외부 프로그램 연동 필요 시)
3. **새 오더 생성** → 테스트 분석 실행

---

## SNUH 전용 — BED 파일 설정

SNUH는 자체 패널 BED 파일(`coords.cons.bed`)을 사용합니다.  
오더 생성 시 BED 필드 설정 방법은 [`SNUH_DEPLOY.md`](../deploy/SNUH_DEPLOY.md)를 참조하세요.

---

## 업그레이드 방법

### 코드만 업그레이드 (레퍼런스 데이터 변경 없음)

```bash
cd $INSTALL_DIR
git pull origin main
git checkout v1.x.x   # 최신 태그로 변경

# Web 이미지만 재빌드 (2분)
docker build -f web_ui/Dockerfile web_ui/ -t roche_nxt_web:latest

# 서비스 재시작
docker compose -f docker-compose.prod.yml up -d --no-deps --force-recreate roche-nxt-web
```

> 분석 이미지(`roche_nxt_analysis`)는 파이프라인 도구가 변경되지 않는 한 재빌드 불필요합니다.

---

## 서비스 관리

```bash
cd /opt/roche_nxt

# 시작
docker compose -f docker-compose.prod.yml up -d

# 중지
docker compose -f docker-compose.prod.yml down

# 재시작 (Web만)
docker compose -f docker-compose.prod.yml restart roche-nxt-web

# 로그
docker logs roche_nxt_web -f
```

---

## 문제 해결

| 증상 | 확인 사항 |
|------|-----------|
| `docker build` 실패 | 인터넷 연결 확인, `docker build --no-cache` 재시도 |
| FTP 다운로드 실패 | FTP 접속 정보 확인, `wget -c` 로 이어받기 |
| 레퍼런스 파일 없음 | `DATA_HOST_DIR` 경로와 hg38/hg19 디렉터리 구조 확인 |
| 포트 접근 불가 | 방화벽 설정 (`firewall-cmd --add-port=8080/tcp --permanent`) |
| Rocky Linux docker 권한 | `sudo usermod -aG docker $USER` 후 재로그인 |

---

*관련 문서: [UPGRADE.md](UPGRADE.md) | [SNUH_DEPLOY.md](../deploy/SNUH_DEPLOY.md) | [OPERATIONS.md](OPERATIONS.md)*
