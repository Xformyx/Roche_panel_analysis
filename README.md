# Roche Panel Analysis

Roche KAPA HyperCap ctDNA 분석 파이프라인 (Nextflow DSL2) + Web UI

## 파이프라인 개요

```
FASTQ → FastQC → UMI Preprocessing → VarDict → SnpEff/SnpSift → QC Report
                                                                    ↓
                                              Select Reporter → Longitudinal Analysis
```

### 주요 단계

| 단계 | 도구 | 설명 |
|------|------|------|
| FastQC | FastQC | 원시 FASTQ 품질 확인 |
| UMI Preprocessing | GATK, fgbio, BWA, fastp | UMI 기반 consensus calling |
| Variant Calling | VarDict + SnpEff + SnpSift | 변이 호출 및 주석 |
| QC Report | Picard, samtools | 정렬 메트릭스, 커버리지 통계 |
| Select Reporter | ctDNAtools (R) | Baseline reporter 선택 (옵션) |
| Longitudinal | ctDNAtools (R) | 시계열 VAF 추적 분석 (옵션) |

## 빠른 시작

```bash
# 1. Docker 이미지 빌드
make build

# 2. 환경 설정
cp .env.example .env
vi .env

# 3. Web UI 시작
make up
# -> http://localhost:8080

# 4. 또는 CLI로 실행
nextflow run main.nf \
    -profile docker \
    --input samplesheet.csv \
    --outdir results
```

## 문서

| 문서 | 설명 |
|------|------|
| [설치 매뉴얼](docs/INSTALL.md) | 온라인/오프라인 환경 설치 |
| [Web UI 사용자 매뉴얼](docs/USER_GUIDE_WEB.md) | 웹 인터페이스 사용법 |
| [CLI 사용자 매뉴얼](docs/USER_GUIDE_CLI.md) | 명령줄 사용법, 파라미터 |
| [운영 지침서](docs/OPERATIONS.md) | 내부 개발 / 고객 배포 / 라이선스 갱신 / 장애 대응 런북 |
| [오프라인 설치 가이드](docs/OFFLINE_INSTALL.md) | USB 기반 11단계 자동 설치 (Docker 포함) |
| [라이선스 가이드](LICENSE.md) | 서명 라이선스 설계, 키 관리, DEV_MODE |
| [배포 가이드](deploy/DEPLOYMENT_GUIDE.md) | 폐쇄망 배포 절차 (간이) |

## 디렉토리 구조

```
Roche_nxt/
├── main.nf                  # 메인 워크플로우
├── nextflow.config          # Nextflow 설정
├── conf/
│   └── base.config          # 프로세스별 리소스 설정
├── modules/                 # 프로세스 정의 (도구별)
├── workflows/               # 서브워크플로우
├── web_ui/                  # Flask Web UI
│   ├── app.py               # Flask 애플리케이션
│   ├── templates/index.html # 프론트엔드
│   ├── Dockerfile           # Web UI Docker 이미지
│   └── requirements.txt
├── containers/
│   └── Dockerfile.all       # Analysis Docker 이미지
├── deploy/                  # 배포 스크립트
│   ├── package.sh           # 배포 패키지 생성
│   ├── install.sh           # 오프라인 설치
│   └── save_images.sh       # Docker 이미지 저장
├── docs/                    # 문서
├── docker-compose.yml
├── Makefile
├── config.json
├── .env.example
└── data -> ../roche_data    # 레퍼런스 데이터 (symlink)
```

## 시스템 요구사항

| 항목 | 최소 | 권장 |
|------|------|------|
| CPU | 8 코어 | 20+ 코어 |
| RAM | 32 GB | 64+ GB |
| 디스크 | 500 GB | 1 TB+ |
| Docker | 20.10+ | |
| Docker Compose | v2.0+ | |

## 라이선스

Copyright © 2026 Xformyx. All rights reserved.
