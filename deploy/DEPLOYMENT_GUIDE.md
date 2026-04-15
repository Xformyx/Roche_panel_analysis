# Roche_nxt 폐쇄망 배포 가이드

## 배포 패키지 구성

총 3개의 패키지를 전송합니다:

| 패키지 | 크기 (예상) | 내용 |
|--------|-----------|------|
| `Roche_nxt/` | ~50 MB | 파이프라인 코드, 설정, 스크립트 |
| `roche_data/` | ~140 GB | 레퍼런스 게놈, dbSNP, BED 파일 |
| `deploy/images/` | ~3 GB | Docker 이미지 (tar.gz) |

## 1단계: 온라인 서버에서 준비

```bash
cd /home/ken/Roche_nxt

# Docker 이미지 빌드
make build

# 이미지 저장
make save
# -> deploy/images/roche_nxt_analysis.tar.gz
# -> deploy/images/roche_nxt_web.tar.gz

# Nextflow 바이너리 다운로드
curl -s https://get.nextflow.io | bash
mv nextflow bin/
chmod +x bin/nextflow
```

## 2단계: 파일 전송

USB 또는 네트워크로 복사:

```bash
# 파이프라인 코드 (data/ symlink 제외)
tar --exclude='data' --exclude='work' --exclude='.nextflow*' \
    -czf roche_nxt_code.tar.gz -C /home/ken Roche_nxt/

# 레퍼런스 데이터 (최초 1회)
tar -czf roche_data.tar.gz -C /home/ken roche_data/
```

## 3단계: 오프라인 서버에서 설치

```bash
# 압축 해제
cd /home/target_user
tar xzf roche_nxt_code.tar.gz
tar xzf roche_data.tar.gz

# data symlink 생성
cd Roche_nxt
ln -s ../roche_data data

# 자동 설치
bash deploy/install.sh
```

## 4단계: 확인

```bash
# Docker 이미지 확인
docker images | grep roche_nxt

# Web UI 접속
# http://<서버IP>:8080

# CLI 테스트
./bin/nextflow run main.nf -profile docker --input test/samplesheet.csv --outdir test_results
```

## .env 설정

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `HOST_DIR` | 현재 디렉토리 | 프로젝트 루트 경로 |
| `WEB_PORT` | `8080` | Web UI 포트 |
| `UID` | 현재 사용자 | 컨테이너 실행 UID |
| `GID` | 현재 그룹 | 컨테이너 실행 GID |
| `TZ` | `Asia/Seoul` | 시간대 |

## 트러블슈팅

### Docker 이미지 로드 실패
```bash
docker load < deploy/images/roche_nxt_analysis.tar.gz
# ERROR: 디스크 공간 부족
# -> df -h 로 디스크 확인, 최소 10GB 여유 필요
```

### Nextflow 실행 안됨
```bash
./bin/nextflow -version
# Java 미설치 시:
# sudo apt install default-jre
```

### 레퍼런스 데이터 경로 문제
```bash
# symlink 확인
ls -la data
# data -> ../roche_data

# 실제 파일 확인
ls data/refs/hg38/ucsc.hg38.fasta
```
