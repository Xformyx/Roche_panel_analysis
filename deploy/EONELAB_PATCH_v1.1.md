# EONELAB 패치 가이드 — v1.1.0

> **대상**: EONELAB (이원의학연구소)  
> **패치 유형**: Web 이미지 교체 + hg19 레퍼런스 데이터 추가

---

## 변경 내용

| 기능 | 설명 |
|------|------|
| **API Key 인증** | 외부 프로그램이 `X-Api-Key` 헤더로 REST API 호출 가능 |
| **API Explorer** | `/developer` 페이지 — 인증 없이 접속, API 문서 + 테스트 + 코드 예시 |
| **report_status** | 외부 CLI가 분석 완료 후 Web UI에 결과 상태를 보고하는 엔드포인트 |
| **hg19 UI 지원** | 오더 생성/설정 화면에서 `hg19 (GRCh37)` 레퍼런스 선택 가능 |
| **QC 핵심 지표 6종** | Throughput, Q30, Mapped %, Duplicated %, On-Target %, On-Target Coverage |
| **버전 표시** | 사이드바 하단 `Ver.1.1.0` 표시 |

---

## 전달 파일 목록

| 파일명 | 크기 (예상) | 내용 |
|--------|------------|------|
| `eonelab_patch_v1.1.tar` | ~140 MB | Web 이미지 + 패치 스크립트 |
| `roche_data_hg19.tar` | ~19 GB | hg19 레퍼런스 데이터 (신규 추가) |

> `roche_data_hg19.tar`는 대용량이므로 별도 드라이브로 전달합니다.

---

## Part 1 — Web 이미지 패치

### 1-1. 패치 파일 서버에 복사

```bash
# USB에서 서버로 복사 (예시)
scp /mnt/usb/eonelab_patch_v1.1.tar user@eonelab-server:/home/user/
```

### 1-2. 압축 해제

```bash
cd /home/user
tar -xf eonelab_patch_v1.1.tar
cd eonelab_patch
```

### 1-3. 패치 실행

```bash
# 기존 설치 디렉토리가 /opt/roche_eonelab 인 경우
sudo bash patch.sh --install-dir /opt/roche_eonelab
```

설치 디렉토리를 모르는 경우:

```bash
# docker-compose.yml 위치로 찾기
find /opt /home -name "docker-compose.yml" 2>/dev/null | grep roche
```

패치 스크립트가 수행하는 작업:
1. 새 `roche_nxt_web:latest` 이미지 로드
2. 기존 컨테이너 이미지 교체 후 재시작
3. 약 20초 후 서비스 기동 확인

> **기존 분석 데이터, DB, 설정은 영향 없습니다.**

### 1-4. 패치 확인

웹 브라우저에서 접속 후 사이드바 하단에 `Ver.1.1.0` 이 표시되면 완료.

```
http://<서버 IP>:8080/developer    ← API Explorer 접속 확인
```

---

## Part 2 — hg19 레퍼런스 데이터 추가

hg19 분석 기능을 사용하려면 레퍼런스 데이터를 추가로 설치해야 합니다.

### 2-1. 현재 레퍼런스 디렉토리 확인

```bash
# 예: /opt/roche_eonelab 에 설치된 경우
cat /opt/roche_eonelab/.env | grep REF_HOST_DIR
# 결과 예시: REF_HOST_DIR=/data/refs
```

레퍼런스 디렉토리: **`REF_HOST_DIR`** 값 (예: `/data/refs`)

### 2-2. hg19 데이터 압축 해제

```bash
REF_DIR="/data/refs"   # 위에서 확인한 REF_HOST_DIR 값으로 변경

# roche_data_hg19.tar 위치 (USB 복사 경로로 변경)
HG19_TAR="/mnt/usb_data/roche_data_hg19.tar"

echo "hg19 데이터 압축 해제 중 (약 5~30분)..."
tar -xf "$HG19_TAR" -C "$REF_DIR" --strip-components=1

echo "완료: $(ls $REF_DIR/hg19/)"
```

압축 해제 후 예상 디렉토리 구조:

```
$REF_DIR/
├── hg38/          (기존)
│   ├── ucsc.hg38.fasta
│   ├── ucsc.hg38.fasta.bwt
│   ├── dbsnp/
│   └── ...
└── hg19/          (신규 추가)
    ├── ucsc.hg19.fasta
    ├── ucsc.hg19.fasta.bwt
    ├── dbsnp/
    │   └── dbsnp_138.hg19.vcf.gz
    └── snpeff/
        └── GRCh37.87/
```

### 2-3. nextflow.config 확인

`/opt/roche_eonelab/app/pipeline/nextflow.config` 에 hg19 레퍼런스 경로가 올바르게 설정되어 있는지 확인합니다.

```bash
grep -A 10 "hg19" /opt/roche_eonelab/app/pipeline/nextflow.config
```

다음과 같은 설정이 있어야 합니다:

```groovy
hg19 {
    fasta       = "${params.ref_base}/hg19/ucsc.hg19.fasta"
    bwa_index   = "${params.ref_base}/hg19/ucsc.hg19.fasta"
    dbsnp       = "${params.ref_base}/hg19/dbsnp/dbsnp_138.hg19.vcf.gz"
    snpeff_db   = "GRCh37.87"
    // bed_target, bed_longit 은 별도 설정
}
```

### 2-4. hg19 분석 테스트

1. Web UI 에서 새 오더 생성
2. **레퍼런스** 드롭다운에서 `hg19 (GRCh37)` 선택
3. 분석 실행 후 정상 완료 확인

---

## API 연동 시작

### API Key 발급

Web UI → **설정** → **외부 연동 API Key** 섹션 → 키 복사

### API Explorer 접속

```
http://<서버 IP>:8080/developer
```

---

## 롤백 방법

패치 후 문제가 발생하면:

```bash
# 이전 이미지로 복원 (build 서버에서)
docker save roche_nxt_web_backup:latest | gzip > roche_nxt_web_old.tar.gz

# 대상 서버에서
gunzip -c roche_nxt_web_old.tar.gz | docker load
cd /opt/roche_eonelab
docker compose up -d --no-deps --force-recreate roche-nxt-web
```
