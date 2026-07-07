# Roche_nxt CLI 사용 설명서

> 분석 파이프라인을 Web UI 없이 CLI로 직접 실행하거나,  
> Custom Blocklist를 생성하고 적용하는 방법을 설명합니다.

---

## 목차

1. [사전 준비](#1-사전-준비)
2. [분석 실행 (CLI)](#2-분석-실행-cli)
3. [Custom Blocklist 생성](#3-custom-blocklist-생성)
4. [Custom Blocklist 적용](#4-custom-blocklist-적용)
5. [외부 프로그램 연동 (REST API)](#5-외부-프로그램-연동-rest-api)

---

## 1. 사전 준비

### Docker 이미지 확인

```bash
docker images | grep roche_nxt
# roche_nxt_web       latest   ...
# roche_nxt_analysis  latest   ...
```

### 디렉토리 구조 확인

```bash
ls /opt/roche_snuh/          # 설치 디렉토리 예시
# .env
# docker-compose.yml
# log/
# results/

cat /opt/roche_snuh/.env | grep -E "REF_HOST_DIR|FASTQ_HOST_DIR|DATA_HOST_DIR"
# REF_HOST_DIR=/data/refs         ← 레퍼런스 데이터 마운트 경로 (호스트)
# FASTQ_HOST_DIR=/data/fastq      ← FASTQ 파일 경로 (호스트)
# DATA_HOST_DIR=/data             ← 데이터 루트
```

---

## 2. 분석 실행 (CLI)

### 2-1. Samplesheet 작성

분석은 CSV 형식의 samplesheet를 입력으로 받습니다.

```csv
sample_id,fastq_1,fastq_2
SAMPLE-001,/data/fastq/SAMPLE-001_R1.fastq.gz,/data/fastq/SAMPLE-001_R2.fastq.gz
```

| 컬럼 | 설명 |
|------|------|
| `sample_id` | 샘플 식별자 (결과 디렉토리명이 됨) |
| `fastq_1` | R1 FASTQ 경로 (컨테이너 내부 기준) |
| `fastq_2` | R2 FASTQ 경로 (컨테이너 내부 기준) |

> 경로는 컨테이너 **내부** 경로 기준입니다.  
> 호스트 `/data/fastq/` → 컨테이너 `/work_nxt_fastq/` 로 마운트됩니다.

### 2-2. hg38 분석 실행

```bash
docker run --rm \
  -v /data:/work_nxt_data \
  -v /data/fastq:/work_nxt_fastq \
  -v /opt/roche_snuh/results:/work_nxt/results \
  -v /opt/roche_snuh/log:/work_nxt/log \
  -v /home/user/pipeline:/work_nxt \
  roche_nxt_analysis:latest \
  nextflow run /work_nxt/main.nf \
    --input /work_nxt/log/samplesheets/my_sample.csv \
    --reference hg38 \
    --af_threshold 0.005 \
    --use_umi true \
    --umi_read_structure "3M3S+T 3M3S+T" \
    --data_dir /work_nxt_data \
    --outdir /work_nxt/results \
    -profile local
```

### 2-3. hg19 분석 실행

`--reference hg19` 만 변경합니다.

```bash
docker run --rm \
  -v /data:/work_nxt_data \
  -v /data/fastq:/work_nxt_fastq \
  -v /opt/roche_snuh/results:/work_nxt/results \
  -v /opt/roche_snuh/log:/work_nxt/log \
  -v /home/user/pipeline:/work_nxt \
  roche_nxt_analysis:latest \
  nextflow run /work_nxt/main.nf \
    --input /work_nxt/log/samplesheets/my_sample.csv \
    --reference hg19 \
    --af_threshold 0.005 \
    --use_umi true \
    --data_dir /work_nxt_data \
    --outdir /work_nxt/results \
    -profile local
```

### 2-4. 주요 파라미터

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `--reference` | `hg38` | 레퍼런스 게놈 (`hg38` 또는 `hg19`) |
| `--af_threshold` | `0.005` | 변이 검출 최소 Allele Fraction (0.5%) |
| `--use_umi` | `true` | UMI 모드 사용 여부 |
| `--umi_read_structure` | `3M3S+T 3M3S+T` | UMI 리드 구조 (KAPA UMI 어댑터) |
| `--subsample` | `false` | 서브샘플링 여부 |
| `--subsample_threshold_gb` | `20` | 서브샘플링 트리거 파일 크기 (GB) |
| `--delete_intermediate` | `false` | 중간 파일 삭제 여부 |

### 2-5. 결과 확인

분석이 완료되면 `results/<sample_id>/` 디렉토리에 결과가 생성됩니다.

```
results/SAMPLE-001/
├── output/
│   ├── variants/          ← VarDict 변이 결과 (annotated txt, VCF)
│   └── bam/               ← 최종 BAM 파일
└── QC_report/             ← QC 지표 CSV 파일들
```

---

## 3. Custom Blocklist 생성

Blocklist는 패널 분석 시 artifact로 알려진 위치를 제외하기 위한 참조 파일입니다.  
Normal 샘플(정상 대조군) BAM 파일 여러 개를 사용해 생성합니다.

### 3-1. 생성 전 준비

**필요 파일:**
- Normal 샘플 BAM 파일 최소 **10개 이상** (많을수록 정확)
- BAM 파일 목록 CSV (헤더 없음)

```bash
# bam_list.csv 예시 — 컨테이너 내부 경로 기준
cat /data/blocklist/normal_bam_list.csv
# /work_nxt_data/normal_bams/Normal-001_deduped.bam
# /work_nxt_data/normal_bams/Normal-002_deduped.bam
# /work_nxt_data/normal_bams/Normal-003_deduped.bam
# ...
```

### 3-2. 1단계: Background Panel 생성

```bash
docker run --rm \
  -v /data:/work_nxt_data \
  roche_nxt_analysis:latest \
  Rscript /tools/kapa_nhl/R/create_bg_panel.R \
    --bam_list     /work_nxt_data/blocklist/normal_bam_list.csv \
    --panel_background /work_nxt_data/blocklist/my_panel_background.rds \
    --target_bed   /work_nxt_data/bed/hg38/NHL_bed/KAPA_HyperCap_DS_NHL_Panel_capture_targets.bed \
    --blist_type   variant \
    --reference    BSgenome.Hsapiens.UCSC.hg38
```

**hg19 사용 시** `--reference BSgenome.Hsapiens.UCSC.hg19` 로 변경.

소요 시간: BAM 수와 크기에 따라 수십 분 ~ 수 시간.

### 3-3. 2단계: Blocklist 파일 생성

```bash
docker run --rm \
  -v /data:/work_nxt_data \
  roche_nxt_analysis:latest \
  Rscript /tools/kapa_nhl/R/create_blocklist.R \
    --panel_background     /work_nxt_data/blocklist/my_panel_background.rds \
    --blocklist            /work_nxt_data/blocklist/my_custom_blocklist_hg38.txt \
    --vaf_quantile         0.95 \
    --min_samples_one_read 12 \
    --min_samples_two_reads 10
```

**주요 파라미터:**

| 파라미터 | 기본값 | 설명 |
|----------|--------|------|
| `--vaf_quantile` | `0.95` | 평균 VAF 기준 상위 5%를 noisy로 판정 |
| `--min_samples_one_read` | `12` | 이 수 이상의 샘플에서 1개 이상의 비레퍼런스 리드 관찰 시 noisy |
| `--min_samples_two_reads` | `10` | 이 수 이상의 샘플에서 2개 이상의 비레퍼런스 리드 관찰 시 noisy |

### 3-4. 생성 결과 확인

```bash
# 기본 형식 확인
head -5 /data/blocklist/my_custom_blocklist_hg38.txt
# chr1_2374767_A_T
# chr1_2374768_C_T
# chr3_12893456_G_A
# ...

# 라인 수 확인
wc -l /data/blocklist/my_custom_blocklist_hg38.txt
```

출력 형식: `{chrom}_{position}_{ref}_{alt}` (헤더 없음, 한 줄에 하나)

---

## 4. Custom Blocklist 적용

### 방법 A: 기본 파일 교체 (Web UI 포함 모든 분석에 적용)

```bash
# 기존 파일 백업
cp /data/refs/blocklist/panel_blocklist_hg38ucsc_65_5.txt \
   /data/refs/blocklist/panel_blocklist_hg38ucsc_65_5.txt.bak

# Custom 파일로 교체
cp /data/blocklist/my_custom_blocklist_hg38.txt \
   /data/refs/blocklist/panel_blocklist_hg38ucsc_65_5.txt
```

이후 Web UI 분석을 포함한 모든 분석에 자동 적용됩니다.

### 방법 B: CLI 실행 시 파라미터로 지정 (특정 분석에만 적용)

```bash
docker run --rm \
  -v /data:/work_nxt_data \
  ... \
  roche_nxt_analysis:latest \
  nextflow run /work_nxt/main.nf \
    --reference hg38 \
    --genomes.hg38.blocklist /work_nxt_data/blocklist/my_custom_blocklist_hg38.txt \
    ... (나머지 파라미터)
```

hg19 Custom Blocklist 지정:

```bash
    --genomes.hg19.blocklist /work_nxt_data/blocklist/my_custom_blocklist_hg19.txt
```

> 경로는 컨테이너 내부 기준입니다.

---

## 5. 외부 프로그램 연동 (REST API)

API 문서 및 테스트는 **API Explorer** 를 이용하세요.

```
http://<서버 IP>:<포트>/developer
```

로그인 없이 접속 가능하며, 각 API의 문서, 실시간 테스트, 코드 예시(curl / Python)를 제공합니다.

### API Key 발급

```
Web UI 로그인 → 설정 → 외부 연동 API Key → 복사
```

### Python 클라이언트 예시

`tools/roche_client.py` 를 사용하면 CLI에서 바로 API를 테스트할 수 있습니다.

```bash
# 설정
python3 tools/roche_client.py configure \
    --url http://<서버IP>:8080 \
    --api-key <발급받은 키>

# 오더 목록 조회
python3 tools/roche_client.py list

# 오더 생성 + 분석 시작 + 결과 대기 (one-shot)
python3 tools/roche_client.py run \
    --sample-id SAMPLE-001 \
    --r1 SAMPLE-001_R1.fastq.gz \
    --r2 SAMPLE-001_R2.fastq.gz \
    --reference hg38 \
    --panel NHL
```
