# Roche_nxt: KAPA ctDNA Analysis Pipeline (Nextflow Edition)

Roche KAPA HyperCap ctDNA 분석 파이프라인의 Nextflow DSL2 버전입니다.

## 파이프라인 개요

```
FASTQ → FastQC → UMI Preprocessing → VarDict → SnpEff/SnpSift → QC Report
                                                                  ↓
                                            Select Reporter → Longitudinal Analysis
```

### 주요 단계

1. **FastQC** - 원시 FASTQ 품질 확인
2. **UMI Preprocessing** - UMI 기반 consensus calling (GATK, fgbio, BWA, fastp)
3. **Variant Calling** - VarDict + SnpEff + SnpSift 변이 호출 및 주석
4. **QC Report** - 정렬 메트릭스, HsMetrics, 커버리지 통계
5. **Select Reporter** - Baseline reporter 선택 (옵션)
6. **Longitudinal Analysis** - 추적 분석 (옵션)

## 빠른 시작

### 사전 요구사항

- Docker
- Nextflow >= 23.04.0
- 레퍼런스 데이터 (`data/` 디렉토리)

### 설치

```bash
# 1. Docker 이미지 빌드
make build

# 2. Web UI 시작
make up
# -> http://localhost:8080

# 3. CLI로 실행
nextflow run main.nf \
    -profile docker \
    --input samplesheet.csv \
    --outdir results
```

### Samplesheet 형식 (CSV)

```csv
sample_id,fastq_1,fastq_2
Sample1,/path/to/S1_R1.fq.gz,/path/to/S1_R2.fq.gz
Sample2,/path/to/S2_R1.fq.gz,/path/to/S2_R2.fq.gz
```

### 주요 파라미터

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `--input` | (필수) | Samplesheet CSV 경로 |
| `--outdir` | `results` | 결과 출력 디렉토리 |
| `--reference` | `hg38` | 레퍼런스 게놈 (hg38/hg19) |
| `--af_threshold` | `0.005` | Allele Frequency 임계값 |
| `--target_bed` | config 기본값 | 타겟 BED 파일 |

## 디렉토리 구조

```
Roche_nxt/
├── main.nf              # 메인 워크플로우
├── nextflow.config      # 설정
├── modules/             # 프로세스 정의 (도구별)
├── workflows/           # 서브워크플로우
├── containers/          # Dockerfile
├── conf/                # 리소스 설정
├── web_ui/              # Flask Web UI
├── deploy/              # 폐쇄망 배포 스크립트
├── data -> ../roche_data  # 레퍼런스 데이터 (symlink)
├── config.json          # 파이프라인 파라미터
└── Makefile             # 빌드/관리 명령
```

## 폐쇄망 배포

```bash
# 1. 온라인 서버에서 빌드 + 저장
make build
make save          # deploy/images/ 에 이미지 저장

# 2. 오프라인 서버로 복사
#    - Roche_nxt/ 디렉토리
#    - roche_data/ 디렉토리 (레퍼런스)

# 3. 오프라인 서버에서 설치
cd Roche_nxt
bash deploy/install.sh
```

## 기존 Roche 파이프라인과의 차이점

| 항목 | Roche (기존) | Roche_nxt (Nextflow) |
|------|-------------|---------------------|
| 파이프라인 엔진 | Python + Shell | Nextflow DSL2 |
| 병렬화 | Docker 컨테이너 수동 관리 | Nextflow 자동 스케줄링 |
| 재시작 | 수동 | `-resume` 자동 |
| 이미지 | `roche_analysis:latest` | `roche_nxt_analysis:latest` |
| Web UI 포트 | 8000 | 8080 |
| 결과 디렉토리 | `analysis/` | `results/` |
| 입력 형식 | CLI args | Samplesheet CSV |

## 라이선스

Internal use only.
