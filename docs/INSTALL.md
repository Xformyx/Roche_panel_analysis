# Roche Panel Analysis - 설치 매뉴얼

## 목차

1. [시스템 요구사항](#1-시스템-요구사항)
2. [온라인 환경 설치](#2-온라인-환경-설치)
3. [폐쇄망(오프라인) 환경 설치](#3-폐쇄망오프라인-환경-설치)
4. [설치 검증](#4-설치-검증)
5. [업데이트](#5-업데이트)
6. [삭제](#6-삭제)
7. [트러블슈팅](#7-트러블슈팅)

---

## 1. 시스템 요구사항

### 하드웨어

| 항목 | 최소 | 권장 |
|------|------|------|
| CPU | 8 코어 | 20+ 코어 |
| RAM | 32 GB | 64+ GB |
| 디스크 | 500 GB | 1 TB+ |

> **참고**: 샘플 1개 분석 시 약 20 CPU 코어, 30 GB 메모리를 사용합니다.
> 동시 실행 수는 서버 리소스에 따라 자동으로 계산되며, Web UI 설정에서 조절할 수 있습니다.

### 디스크 공간 상세

| 항목 | 크기 |
|------|------|
| 파이프라인 코드 | ~50 MB |
| Docker 이미지 (analysis + web) | ~5 GB |
| 레퍼런스 데이터 (hg38 + dbSNP + BED) | ~140 GB |
| 분석 결과 (샘플당) | ~500 MB |
| 작업 디렉토리 (샘플당, 분석 중) | ~50-100 GB |

### 소프트웨어

| 소프트웨어 | 버전 | 필수 |
|-----------|------|------|
| Linux (Ubuntu/CentOS/RHEL) | 18.04+ / 7+ | O |
| Docker | 20.10+ | O |
| Docker Compose | v2.0+ | O |
| Git | 2.0+ | 온라인만 |

### Docker 설치 확인

```bash
docker --version          # Docker version 20.10+
docker compose version    # Docker Compose version v2.0+
```

Docker가 없으면:
```bash
# Ubuntu
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# 현재 사용자를 docker 그룹에 추가 (재로그인 필요)
sudo usermod -aG docker $USER
```

---

## 2. 온라인 환경 설치

### 2.1 소스 코드 다운로드

```bash
cd /home/$USER
git clone https://github.com/Xformyx/Roche_panel_analysis.git Roche_nxt
cd Roche_nxt
```

### 2.2 레퍼런스 데이터 준비

레퍼런스 데이터를 별도 디렉토리에 준비하고 symlink를 생성합니다:

```bash
# 레퍼런스 데이터 디렉토리 구조
# roche_data/
# ├── refs/
# │   └── hg38/
# │       ├── ucsc.hg38.fasta
# │       ├── ucsc.hg38.fasta.fai
# │       ├── ucsc.hg38.dict
# │       ├── ucsc.hg38.fasta.amb
# │       ├── ucsc.hg38.fasta.ann
# │       ├── ucsc.hg38.fasta.bwt
# │       ├── ucsc.hg38.fasta.pac
# │       ├── ucsc.hg38.fasta.sa
# │       └── genome_file.txt
# ├── dbsnp/
# │   └── All_20180418.vcf
# ├── bed/
# │   └── hg38/
# │       └── NHL_bed/
# │           ├── KAPA_HyperCap_DS_NHL_Panel_capture_targets.bed
# │           ├── KAPA_HyperCap_DS_NHL_Panel_primary_targets.bed
# │           └── KAPA_HyperCap_DS_NHL_Panel_capture_targets_for_longitudinal.bed
# ├── snpeff/
# │   └── (SnpEff 데이터베이스)
# └── blocklist/
#     └── panel_blocklist_hg38ucsc_65_5.txt

# symlink 생성
ln -s /path/to/roche_data data
```

### 2.3 Docker 이미지 빌드

```bash
# 전체 빌드 (analysis + web)
make build

# 또는 개별 빌드
make build-analysis    # 분석 이미지 (~30분 소요)
make build-web         # Web UI 이미지 (~1분 소요)
```

### 2.4 환경 설정

```bash
# .env 파일 생성
cp .env.example .env

# 편집 (.env)
vi .env
```

`.env` 파일 설정:

```bash
HOST_DIR=/home/사용자/Roche_nxt    # 프로젝트 절대 경로
FASTQ_HOST_DIR=/path/to/fastq      # FASTQ 파일 경로
BED_HOST_DIR=/path/to/bed/hg38     # BED 파일 경로
WEB_PORT=8080                       # Web UI 포트
UID=1000                            # 현재 사용자 UID (id -u 로 확인)
GID=1000                            # 현재 사용자 GID (id -g 로 확인)
TZ=Asia/Seoul                       # 시간대
ENABLE_LONGITUDINAL=true            # Longitudinal 분석 활성화

# 리소스 설정 (0 = 자동감지)
MAX_CPUS=0
MAX_MEMORY=0
MAX_CONCURRENT_SAMPLES=0
```

### 2.5 서비스 시작

```bash
make up
# 또는
docker compose up -d
```

### 2.6 접속 확인

브라우저에서 `http://서버IP:8080` 접속

---

## 3. 폐쇄망(오프라인) 환경 설치

### 3.1 온라인 서버에서 패키지 준비

```bash
cd /home/$USER/Roche_nxt

# 1. Docker 이미지 빌드
make build

# 2. 배포 패키지 생성 (한 번에 모두)
bash deploy/package.sh
```

`deploy/package.sh`가 생성하는 파일:

| 파일 | 크기 (예상) | 내용 |
|------|-----------|------|
| `roche_panel_analysis_code.tar.gz` | ~5 MB | 파이프라인 코드 |
| `roche_panel_analysis_images.tar.gz` | ~3 GB | Docker 이미지 |
| `roche_data.tar.gz` | ~140 GB | 레퍼런스 데이터 (최초 1회) |

### 3.2 파일 전송

USB, 외장 하드, 또는 내부 네트워크를 통해 대상 서버로 복사합니다.

```bash
# 예시: USB로 복사
cp roche_panel_analysis_code.tar.gz /media/usb/
cp roche_panel_analysis_images.tar.gz /media/usb/
cp roche_data.tar.gz /media/usb/         # 최초 1회만
```

### 3.3 대상 서버에서 설치

```bash
# 1. 압축 해제
cd /home/$USER
tar xzf roche_panel_analysis_code.tar.gz
tar xzf roche_data.tar.gz                # 최초 1회만

# 2. data symlink 생성
cd Roche_nxt
ln -s ../roche_data data

# 3. Docker 이미지 로드 + 자동 설정
bash deploy/install.sh

# 또는 이미지만 로드
bash build.sh load
```

`install.sh`가 자동으로 수행하는 작업:
1. Docker 이미지 로드
2. `.env` 파일 생성/업데이트 (경로, UID/GID 자동 설정)
3. 필요 디렉토리 생성 (fastq, results, log, work)
4. 레퍼런스 데이터 symlink 확인
5. Web UI 시작

### 3.4 FASTQ 파일 준비

분석할 FASTQ 파일을 지정된 디렉토리에 배치합니다:

```bash
# .env의 FASTQ_HOST_DIR에 지정된 경로에 FASTQ 파일 배치
# 또는 Web UI 설정에서 경로 변경 가능
cp /path/to/Sample_R1.fastq.gz /home/$USER/fastq/
cp /path/to/Sample_R2.fastq.gz /home/$USER/fastq/
```

---

## 4. 설치 검증

### 4.1 Docker 이미지 확인

```bash
docker images | grep roche_nxt
# roche_nxt_analysis   latest   ...   ~5GB
# roche_nxt_web        latest   ...   ~200MB
```

### 4.2 서비스 상태 확인

```bash
make status
# 또는
docker compose ps
```

### 4.3 Web UI 접속

```
http://서버IP:8080
```

대시보드에서 시스템 리소스(CPU, 메모리, 디스크)가 표시되면 정상입니다.

### 4.4 레퍼런스 데이터 확인

```bash
ls -la data/refs/hg38/ucsc.hg38.fasta
ls -la data/dbsnp/All_20180418.vcf
ls -la data/bed/hg38/NHL_bed/
```

---

## 5. 업데이트

### 온라인 환경

```bash
cd Roche_nxt
git pull origin main
make rebuild       # Docker 이미지 재빌드
```

### 폐쇄망 환경

1. 온라인 서버에서 새 패키지 생성: `bash deploy/package.sh`
2. 대상 서버로 전송
3. 코드 압축 해제 (기존 덮어쓰기)
4. 이미지 로드: `bash build.sh load`
5. 서비스 재시작: `make restart`

---

## 6. 삭제

```bash
cd Roche_nxt

# 서비스 중지
make down

# Docker 이미지 삭제
make clean

# 프로젝트 디렉토리 삭제 (선택)
cd ..
rm -rf Roche_nxt
```

---

## 7. 트러블슈팅

### Docker 권한 오류

```
Got permission denied while trying to connect to the Docker daemon socket
```

```bash
sudo usermod -aG docker $USER
# 재로그인 후 다시 시도
```

### 포트 충돌

```
Error: Bind for 0.0.0.0:8080 failed: port is already allocated
```

`.env` 파일에서 `WEB_PORT`를 다른 포트로 변경 후 `make restart`

### Docker 이미지 로드 실패 (디스크 부족)

```bash
df -h                    # 디스크 확인 (최소 10GB 여유 필요)
docker system prune -f   # 미사용 Docker 리소스 정리
```

### 레퍼런스 데이터 symlink 깨짐

```bash
ls -la data
# data -> ../roche_data (깨진 경우 빨간색으로 표시)

# 올바른 경로로 재생성
rm data
ln -s /actual/path/to/roche_data data
```

### Nextflow 분석 실패 - 메모리 부족

Web UI 설정에서 동시 실행 수를 줄이거나, 샘플당 리소스를 조절합니다:
- 설정 > 리소스 설정 > 최대 동시 실행 수를 1로 변경

### 컨테이너 로그 확인

```bash
# Web UI 로그
docker compose logs -f roche-nxt-web

# 분석 컨테이너 로그
docker logs nxt_<샘플명>_<오더ID앞8자리>
```
