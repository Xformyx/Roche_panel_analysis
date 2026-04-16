# Roche Panel Analysis - 배포 가이드

## 개요

이 문서는 **폐쇄망(오프라인) 환경**에 Roche Panel Analysis를 배포하는 절차를 설명합니다.

> 온라인 환경 설치는 [설치 매뉴얼](../docs/INSTALL.md)을 참고하세요.

---

## 배포 패키지 구성

| 패키지 | 크기 (예상) | 내용 | 빈도 |
|--------|-----------|------|------|
| `roche_panel_analysis_code.tar.gz` | ~5 MB | 파이프라인 코드, 설정, 스크립트 | 매 업데이트 |
| `roche_panel_analysis_images.tar.gz` | ~3 GB | Docker 이미지 (analysis + web) | 이미지 변경 시 |
| `roche_data.tar.gz` | ~140 GB | 레퍼런스 게놈, dbSNP, BED, SnpEff | 최초 1회 |

---

## 1단계: 온라인 서버에서 패키지 준비

### 1.1 소스 코드 준비

```bash
git clone https://github.com/Xformyx/Roche_panel_analysis.git Roche_nxt
cd Roche_nxt
```

### 1.2 Docker 이미지 빌드

```bash
make build
# 또는
bash build.sh all
```

### 1.3 패키지 생성

```bash
# 코드 + Docker 이미지
bash deploy/package.sh

# 코드 + Docker 이미지 + 레퍼런스 데이터 (최초)
bash deploy/package.sh --with-data

# 코드만 (업데이트 시)
bash deploy/package.sh --code-only
```

생성 위치: `deploy/packages/`

```
deploy/packages/
├── roche_panel_analysis_code.tar.gz
├── roche_panel_analysis_images.tar.gz
└── roche_data.tar.gz          # --with-data 시
```

---

## 2단계: 파일 전송

USB, 외장 하드, 또는 내부 보안 네트워크를 통해 대상 서버로 복사합니다.

```bash
# USB로 복사 예시
cp deploy/packages/*.tar.gz /media/usb/
```

---

## 3단계: 대상 서버 설치

### 3.1 사전 요구사항 확인

```bash
docker --version         # Docker 20.10+
docker compose version   # Docker Compose v2.0+
```

### 3.2 압축 해제

```bash
cd /home/$USER

# 코드
tar xzf roche_panel_analysis_code.tar.gz

# 레퍼런스 데이터 (최초 1회)
tar xzf roche_data.tar.gz
```

### 3.3 자동 설치

```bash
cd Roche_nxt

# data symlink 생성
ln -s ../roche_data data

# 설치 실행
bash deploy/install.sh
```

`install.sh`가 자동으로 수행하는 작업:

1. Docker 설치 확인
2. Docker 이미지 로드 (`deploy/images/*.tar.gz`)
3. Nextflow 바이너리 확인
4. `.env` 파일 생성 (경로, UID/GID 자동 설정)
5. 필요 디렉토리 생성
6. 레퍼런스 데이터 symlink 확인
7. Web UI 시작

### 3.4 설치 확인

```bash
# Docker 이미지
docker images | grep roche_nxt

# 서비스 상태
docker compose ps

# Web UI 접속
# http://서버IP:8080
```

---

## 4단계: 환경 설정

`.env` 파일을 환경에 맞게 수정합니다:

```bash
vi .env
```

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `HOST_DIR` | (자동 설정) | 프로젝트 절대 경로 |
| `FASTQ_HOST_DIR` | `HOST_DIR/fastq` | FASTQ 파일 경로 |
| `BED_HOST_DIR` | `HOST_DIR/data/bed/hg38` | BED 파일 경로 |
| `WEB_PORT` | `8080` | Web UI 포트 |
| `UID` | (자동 설정) | 컨테이너 실행 UID |
| `GID` | (자동 설정) | 컨테이너 실행 GID |
| `TZ` | `Asia/Seoul` | 시간대 |
| `ENABLE_LONGITUDINAL` | `true` | Longitudinal 분석 활성화 |
| `MAX_CPUS` | `0` (자동감지) | 최대 CPU 코어 |
| `MAX_MEMORY` | `0` (자동감지) | 최대 메모리 (GB) |
| `MAX_CONCURRENT_SAMPLES` | `0` (자동계산) | 최대 동시 분석 수 |

설정 변경 후:

```bash
docker compose up -d    # 재시작
```

---

## 업데이트 절차

### 코드만 업데이트

```bash
# 온라인 서버에서
bash deploy/package.sh --code-only

# 대상 서버에서
tar xzf roche_panel_analysis_code.tar.gz
cd Roche_nxt
make restart
```

### Docker 이미지 포함 업데이트

```bash
# 온라인 서버에서
make build
bash deploy/package.sh

# 대상 서버에서
tar xzf roche_panel_analysis_code.tar.gz
cd Roche_nxt
bash build.sh load
make restart
```

---

## 관리 명령어

```bash
make up              # 서비스 시작
make down            # 서비스 중지
make restart         # 서비스 재시작
make logs            # 로그 확인
make status          # 상태 확인
make rebuild         # 전체 재빌드 (온라인 환경)
```

---

## 트러블슈팅

자세한 내용은 [설치 매뉴얼 - 트러블슈팅](../docs/INSTALL.md#7-트러블슈팅) 섹션을 참고하세요.
