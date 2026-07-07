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

> API Key는 `X-Api-Key` 헤더로 전달합니다.  
> 예: `curl -H "X-Api-Key: rnxt-xxxx" http://server:8080/api/orders`

---

## 6. roche_client.py 사용 설명서

`roche_client.py`는 API를 래핑한 Python CLI 도구입니다.  
개발 없이 터미널에서 바로 분석을 실행하거나, 자동화 스크립트에 활용할 수 있습니다.

### 다운로드

API Explorer (`/developer`) 페이지 상단 **`⬇ roche_client.py`** 버튼으로 다운로드합니다.  
또는 설치 서버에서 직접 복사:

```bash
cp /opt/roche_nxt/tools/roche_client.py .
```

### 사전 요구사항

Python 3.8 이상과 `requests` 패키지가 필요합니다.

```bash
python3 --version          # 3.8+ 확인
pip install requests       # requests 설치
```

---

### 최초 설정 (1회만)

서버 URL과 인증 정보를 `~/.roche_client.json`에 저장합니다.

**방법 A — ID/비밀번호로 로그인 (API Key 자동 저장, 편함)**

```bash
python3 roche_client.py login \
    --url http://<서버IP>:<포트> \
    --user admin
# 비밀번호는 안전하게 프롬프트로 입력
```

**방법 B — API Key 직접 입력**

```bash
# API Key는 Web UI → 설정 → 외부 연동 API Key 에서 복사
python3 roche_client.py configure \
    --url http://<서버IP>:<포트> \
    --key rnxt-xxxxxxxxxxxx
```

> 설정 확인: `cat ~/.roche_client.json`  
> 환경변수로도 사용 가능: `ROCHE_BASE_URL`, `ROCHE_API_KEY`

---

### 명령어 목록

| 명령 | 설명 |
|------|------|
| `login` | ID/비밀번호로 로그인하여 API Key 자동 저장 |
| `configure` | 서버 URL과 API Key 직접 저장 |
| `list` | Order 목록 조회 |
| `create` | Order 생성 (분석 실행 안 함) |
| `start` | 기존 Order 분석 시작 |
| `run` | **Order 생성 → 분석 시작 → 완료 대기 → 결과 출력** (원스텝) |
| `status` | 특정 Order 상태 확인 |
| `results` | QC 결과 지표 출력 |
| `report` | QC 리포트 텍스트 파일 저장 |
| `logs` | 분석 실행 로그 출력 |

---

### 상세 사용 예시

#### Order 목록 조회

```bash
python3 roche_client.py list
python3 roche_client.py list -n 10                  # 최근 10건만
python3 roche_client.py list --status completed     # 완료된 것만
```

#### 분석 실행 (원스텝 — 가장 자주 사용)

```bash
python3 roche_client.py run \
    --sample SAMPLE-001 \
    --r1 SAMPLE-001_R1.fastq.gz \
    --r2 SAMPLE-001_R2.fastq.gz
```

> `--r1`, `--r2`는 서버의 **FASTQ 디렉터리 기준 파일명**만 입력합니다.  
> (예: FASTQ 디렉터리 = `/data/fastq` → 파일명만 입력)

실행 흐름:
1. Order 생성
2. 분석 컨테이너 시작
3. 완료될 때까지 폴링 대기 (Ctrl+C로 대기 중단 가능, 분석은 계속 실행)
4. 완료 시 핵심 QC 지표 6종 자동 출력

**추가 옵션:**

```bash
python3 roche_client.py run \
    --sample SAMPLE-001 \
    --r1 SAMPLE-001_R1.fastq.gz \
    --r2 SAMPLE-001_R2.fastq.gz \
    --reference hg19 \               # hg38 (기본) 또는 hg19
    --bed SNUH_bed/coords.cons.bed \ # BED 파일 (생략 시 기본값)
    --af 0.01 \                      # AF threshold (기본 0.005)
    --umi Y \                        # UMI 사용 여부 (기본 Y)
    --patient "홍길동" \
    --chart "2026-00001" \
    --department "혈액종양내과" \
    --doctor "김철수" \
    --poll-interval 30               # 상태 확인 주기(초, 기본 15)
```

#### Order 상태 확인

```bash
python3 roche_client.py status 20260626120000-abc123
```

출력 예:
```
Order 상세
  ID       : 20260626120000-abc123
  Sample   : SAMPLE-001
  Status   : completed
  Reference: hg38
  Created  : 2026-06-26 12:00:00
  Completed: 2026-06-26 12:42:11
```

#### QC 결과 확인

```bash
python3 roche_client.py results 20260626120000-abc123
```

출력 예:
```
[핵심 QC 지표 - 6종]
+------------------------+--------------+------+
| 지표                    | 값           | 단위 |
+------------------------+--------------+------+
| Throughput             | 2341.50      | Mb   |
| Q30 Trimmed            | 92.34        | %    |
| Mapped                 | 89.78        | %    |
| Duplicated             | 12.45        | %    |
| On-Target              | 69.53        | %    |
| On-Target Coverage     | 1245.3       | x    |
+------------------------+--------------+------+
```

#### QC 리포트 저장

```bash
python3 roche_client.py report 20260626120000-abc123 -o qc_report.txt
python3 roche_client.py report 20260626120000-abc123 --print   # 화면에도 출력
```

#### 실행 로그 확인

```bash
python3 roche_client.py logs 20260626120000-abc123             # 마지막 100줄
python3 roche_client.py logs 20260626120000-abc123 -n 50       # 마지막 50줄
```

---

### 자동화 스크립트 예시

여러 샘플을 순차적으로 분석하는 배치 스크립트:

```bash
#!/bin/bash
SAMPLES=(
    "SAMPLE-001 SAMPLE-001_R1.fastq.gz SAMPLE-001_R2.fastq.gz"
    "SAMPLE-002 SAMPLE-002_R1.fastq.gz SAMPLE-002_R2.fastq.gz"
    "SAMPLE-003 SAMPLE-003_R1.fastq.gz SAMPLE-003_R2.fastq.gz"
)

for entry in "${SAMPLES[@]}"; do
    read -r sample r1 r2 <<< "$entry"
    echo "=== 분석 시작: $sample ==="
    python3 roche_client.py run \
        --sample "$sample" \
        --r1 "$r1" \
        --r2 "$r2"
    echo ""
done
```

---

### 오류 해결

| 오류 메시지 | 원인 | 해결 |
|-------------|------|------|
| `연결 실패` | 서버 URL 오류 또는 서버 미실행 | URL 확인, `docker ps`로 서버 상태 확인 |
| `HTTP 401` | API Key 오류 또는 미설정 | `roche_client.py login` 또는 `configure` 재실행 |
| `HTTP 404` | Order ID 오류 | `roche_client.py list`로 정확한 ID 확인 |
| `requests 패키지 필요` | requests 미설치 | `pip install requests` |
