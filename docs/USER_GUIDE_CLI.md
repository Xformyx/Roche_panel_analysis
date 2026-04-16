# Roche Panel Analysis - CLI 사용자 매뉴얼

## 목차

1. [개요](#1-개요)
2. [기본 사용법](#2-기본-사용법)
3. [Samplesheet 작성](#3-samplesheet-작성)
4. [파라미터 레퍼런스](#4-파라미터-레퍼런스)
5. [실행 예제](#5-실행-예제)
6. [프로파일](#6-프로파일)
7. [결과 파일 구조](#7-결과-파일-구조)
8. [고급 사용법](#8-고급-사용법)
9. [트러블슈팅](#9-트러블슈팅)

---

## 1. 개요

Web UI 없이 명령줄에서 직접 Nextflow 파이프라인을 실행할 수 있습니다.
대량 배치 분석이나 자동화 스크립트 작성 시 유용합니다.

### 파이프라인 흐름

```
FASTQ → FastQC → UMI Preprocessing → VarDict → SnpEff/SnpSift → QC Report
                                                                    ↓
                                              Select Reporter → Longitudinal Analysis
```

---

## 2. 기본 사용법

### 최소 실행

```bash
cd /path/to/Roche_nxt

nextflow run main.nf \
    -profile docker \
    --input samplesheet.csv \
    --outdir results
```

### 전체 옵션 실행

```bash
nextflow run main.nf \
    -profile docker \
    --input samplesheet.csv \
    --outdir results/my_run \
    --reference hg38 \
    --af_threshold 0.005 \
    --target_bed data/bed/hg38/custom.bed \
    --max_cpus 20 \
    --max_memory 64 \
    -resume
```

---

## 3. Samplesheet 작성

CSV 형식으로 분석할 샘플 목록을 작성합니다.

### 형식

```csv
sample_id,fastq_1,fastq_2
Sample1,/absolute/path/to/Sample1_R1_001.fastq.gz,/absolute/path/to/Sample1_R2_001.fastq.gz
Sample2,/absolute/path/to/Sample2_R1_001.fastq.gz,/absolute/path/to/Sample2_R2_001.fastq.gz
```

### 규칙

- 헤더는 반드시 `sample_id,fastq_1,fastq_2`
- FASTQ 경로는 **절대 경로** 사용
- Docker 프로파일 사용 시 컨테이너 내부에서 접근 가능한 경로 사용
- `sample_id`는 영문, 숫자, 언더스코어(`_`), 하이픈(`-`)만 허용

### Docker 프로파일에서의 경로

Docker 프로파일로 실행 시 FASTQ 파일은 컨테이너 내부 경로를 사용해야 합니다.
`docker-compose.yml`에서 마운트된 볼륨 경로를 참조합니다.

---

## 4. 파라미터 레퍼런스

### 필수 파라미터

| 파라미터 | 설명 |
|---------|------|
| `--input` | Samplesheet CSV 파일 경로 |
| `--outdir` | 결과 출력 디렉토리 |

### 레퍼런스 설정

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--reference` | `hg38` | 레퍼런스 게놈 (`hg38` 또는 `hg19`) |
| `--data_dir` | `data/` | 레퍼런스 데이터 경로 |
| `--target_bed` | 자동 설정 | 타겟 BED 파일 경로 |

### 변이 호출 설정

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--af_threshold` | `0.005` | 최소 Allele Frequency |

### UMI 설정

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--umi_read_structure` | `3M3S+T 3M3S+T` | UMI read structure |
| `--seqtk_sample_size` | `40000000` | 서브샘플링 리드 수 |
| `--min_reads` | `1` | 컨센서스 최소 리드 수 |
| `--min_base_quality` | `20` | 최소 베이스 품질 |
| `--max_read_error_rate` | `0.025` | 최대 리드 에러율 |
| `--max_base_error_rate` | `0.1` | 최대 베이스 에러율 |

### 리소스 제한

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--max_cpus` | `0` (전체) | 최대 CPU 코어 수 |
| `--max_memory` | `0` (전체) | 최대 메모리 (GB) |

### Select Reporter 설정

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--run_select_reporter` | `false` | Select Reporter 실행 여부 |
| `--sr_germline_cutoff` | `0.0005` | Germline cutoff |
| `--sr_min_af` | `0.005` | 최소 AF |
| `--sr_max_af` | `0.35` | 최대 AF |
| `--sr_min_dp` | `1000` | 최소 Depth |
| `--sr_min_vd` | `15` | 최소 Variant Depth |

### Longitudinal 설정

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--run_longitudinal` | `false` | Longitudinal 분석 실행 여부 |
| `--la_reads_threshold` | `1000` | 리드 수 임계값 |
| `--la_pvalue_threshold` | `0.001` | p-value 임계값 |
| `--la_vaf_threshold` | `0.1` | VAF 임계값 |
| `--la_n_sim` | `10000` | 시뮬레이션 횟수 |

### 파이프라인 제어

| 파라미터 | 기본값 | 설명 |
|---------|--------|------|
| `--skip_cleanup` | `false` | 정리 단계 건너뛰기 |

---

## 5. 실행 예제

### 기본 Baseline 분석

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results
```

### 커스텀 BED 파일 사용

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    --target_bed data/bed/hg38/custom_panel.bed
```

### 리소스 제한 (소규모 서버)

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    --max_cpus 8 \
    --max_memory 32
```

### Select Reporter 포함

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    --run_select_reporter true
```

### Longitudinal 분석 포함

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    --run_select_reporter true \
    --run_longitudinal true
```

### Resume (이전 실행 이어서)

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    -resume
```

### hg19 레퍼런스 사용

```bash
nextflow run main.nf \
    -profile docker \
    --input samples.csv \
    --outdir results \
    --reference hg19
```

### 폐쇄망 환경

```bash
nextflow run main.nf \
    -profile offline \
    --input samples.csv \
    --outdir results
```

---

## 6. 프로파일

| 프로파일 | 설명 |
|---------|------|
| `docker` | 표준 Docker 실행 (인터넷 연결) |
| `offline` | 폐쇄망 Docker 실행 (이미지 pull 비활성화) |
| `local` | Docker 없이 직접 실행 (도구가 로컬에 설치된 경우) |
| `test` | 테스트 데이터로 실행 |

### 프로파일 조합

```bash
# Docker + test
nextflow run main.nf -profile docker,test
```

---

## 7. 결과 파일 구조

```
results/
└── SampleName/
    ├── SampleName/
    │   ├── variant_calling/
    │   │   ├── SampleName_vardict.vcf           # Raw VCF
    │   │   ├── SampleName_snpeff.vcf            # SnpEff 주석
    │   │   ├── SampleName_snpsift.vcf           # dbSNP 주석
    │   │   └── SampleName_annotated_vcf.txt     # 최종 변이 테이블
    │   ├── QC_report/
    │   │   ├── SampleName_alignment_metrics_aligned.txt
    │   │   ├── SampleName_alignment_metrics_umi_deduped.txt
    │   │   ├── SampleName_insert_size_metrics_aligned.txt
    │   │   ├── SampleName_insert_size_metrics_umi_deduped.txt
    │   │   ├── SampleName_hs_metrics_aligned.txt
    │   │   ├── SampleName_hs_metrics_umi_deduped.txt
    │   │   ├── SampleName_markduplicates_metrics_gatk.txt
    │   │   ├── SampleName_mismatch_rate.csv
    │   │   └── SampleName_ontarget_reads_*.txt
    │   ├── trimming/
    │   │   └── fastp.json
    │   └── fastqc/
    │       ├── SampleName_R1_fastqc.html
    │       └── SampleName_R2_fastqc.html
    └── pipeline_info/
        ├── trace_YYYY-MM-DD_HH-mm-ss.txt       # 프로세스별 리소스 사용량
        ├── timeline_YYYY-MM-DD_HH-mm-ss.html    # 실행 타임라인
        └── report_YYYY-MM-DD_HH-mm-ss.html      # Nextflow 리포트
```

### 주요 결과 파일

| 파일 | 설명 |
|------|------|
| `*_annotated_vcf.txt` | 최종 변이 테이블 (TSV, 가장 중요) |
| `*_snpsift.vcf` | dbSNP 주석이 포함된 VCF |
| `fastp.json` | 트리밍 QC 결과 |
| `*_hs_metrics_umi_deduped.txt` | UMI 중복 제거 후 커버리지 |
| `trace_*.txt` | 프로세스별 CPU/메모리 사용량 |

---

## 8. 고급 사용법

### 배치 실행 스크립트

여러 샘플을 순차적으로 실행:

```bash
#!/bin/bash
for csv in samplesheets/*.csv; do
    sample=$(basename "$csv" .csv)
    echo "=== Running $sample ==="
    nextflow run main.nf \
        -profile docker \
        --input "$csv" \
        --outdir "results/$sample" \
        -resume
done
```

### Nextflow 리포트 확인

분석 완료 후 `results/pipeline_info/` 에 생성되는 HTML 리포트:

- **timeline**: 각 태스크의 실행 타임라인 (간트 차트)
- **report**: 리소스 사용량, 태스크 통계, 오류 요약
- **trace**: TSV 형태의 상세 프로세스 로그

### Work 디렉토리 정리

분석 완료 후 work 디렉토리는 수백 GB를 차지할 수 있습니다:

```bash
# 특정 실행의 work 디렉토리 삭제
rm -rf work/run_SampleName_*

# 전체 정리 (resume 불가능해짐)
nextflow clean -f
```

### 실행 이력 확인

```bash
nextflow log                    # 실행 이력 목록
nextflow log run_name -f hash   # 특정 실행의 태스크 해시
```

---

## 9. 트러블슈팅

### Java not found

```
ERROR: Cannot find Java or it's a wrong version
```

```bash
# Java 17 설치
sudo apt install openjdk-17-jre-headless
java -version
```

### Docker permission denied

```
Got permission denied while trying to connect to the Docker daemon
```

```bash
sudo usermod -aG docker $USER
# 재로그인 후 다시 시도
```

### 메모리 부족 (Out of Memory)

```
Process exceeded memory limit
```

`--max_cpus`와 `--max_memory`를 줄이거나, `nextflow.config`의 프로세스별 메모리를 조절합니다.

### Nextflow lock error

```
Unable to acquire lock on session
```

이전 실행이 비정상 종료된 경우:

```bash
# lock 파일 정리
rm -rf .nextflow/cache/*/db/LOCK
# 또는 다른 work 디렉토리 사용
nextflow run main.nf ... -work-dir work/new_run
```

### 레퍼런스 파일 없음

```
No such file: data/refs/hg38/ucsc.hg38.fasta
```

`data` symlink가 올바른지 확인:

```bash
ls -la data                           # symlink 확인
ls data/refs/hg38/ucsc.hg38.fasta     # 실제 파일 확인
```
