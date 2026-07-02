# SNUH 초기 설치 가이드 — Roche_nxt v1.1.0

> **대상**: SNUH (서울대학교병원)  
> **설치 방식**: 오프라인 (에어갭) 초기 설치  
> **설치 담당**: 병원 자체 IT 담당자

---

## 1. 전달 파일 목록

USB에 아래 파일 3개를 복사해 전달합니다.

| 파일명 | 크기 (예상) | 내용 |
|--------|------------|------|
| `usb_bundle_snuh_v1.tar` | ~260 MB | 앱 번들 (Docker 이미지, 설치 스크립트, SNUH 라이선스, Rocky Linux 9 용 Docker 오프라인 패키지) |
| `roche_data_hg38.tar` | ~210 GB | hg38 레퍼런스 데이터 |
| `roche_data_hg19.tar` | ~19 GB | hg19 레퍼런스 데이터 |

> 데이터 tar 두 개는 별도 대용량 드라이브에 저장해 함께 전달합니다.

---

## 2. 서버 요구 사항

| 항목 | 최소 | 권장 |
|------|------|------|
| OS | Rocky Linux 9.x | Rocky Linux 9.5 |
| CPU | 16 코어 | 32 코어 이상 |
| RAM | 64 GB | 128 GB |
| 실행 디스크 | 500 GB (SSD 권장) | 1 TB SSD |
| 데이터 디스크 | 500 GB (hg38+hg19 ~230 GB) | 별도 HDD/NAS |
| Docker | 없어도 됨 (번들에 포함) | 이미 설치되어 있으면 더 빠름 |

> SLURM 이 이미 설치된 서버라도 Docker 는 충돌 없이 공존합니다.  
> 단, Docker 그룹에 설치 계정을 추가해야 합니다 (설치 스크립트가 자동 처리).

---

## 3. 설치 절차

### 3-1. USB / 드라이브 마운트

```bash
# USB 앱 번들 드라이브 마운트 (예시)
sudo mkdir -p /mnt/usb_app
sudo mount /dev/sdb1 /mnt/usb_app

# 대용량 데이터 드라이브 마운트 (예시)
sudo mkdir -p /mnt/usb_data
sudo mount /dev/sdc1 /mnt/usb_data
```

### 3-2. 앱 번들 압축 해제

```bash
mkdir -p /opt/roche_bundle_snuh_v1
cd /opt/roche_bundle_snuh_v1

tar -xf /mnt/usb_app/usb_bundle_snuh_v1.tar
```

### 3-3. 데이터 파일 위치 확인

설치 스크립트는 다음 위치에서 데이터 tar 를 자동 탐색합니다.

1. `<번들 디렉토리>/data/roche_data_hg38.tar` (번들 내부)
2. `<번들 상위 디렉토리>/roche_data_hg38.tar` **(권장)**

데이터가 대용량이라 번들에 포함시키지 않은 경우, **번들 상위 디렉토리**에 복사합니다.

```bash
# 예: /opt/roche_bundle_snuh_v1 번들인 경우, 상위 = /opt/
cp /mnt/usb_data/roche_data_hg38.tar /opt/
cp /mnt/usb_data/roche_data_hg19.tar /opt/
```

### 3-4. 설치 실행

```bash
cd /opt/roche_bundle_snuh_v1
sudo bash install.sh --install-dir /opt/roche_snuh
```

설치 스크립트가 11단계를 수행합니다:
1. 사전 점검 (OS, 디스크, 체크섬 등)
2. Docker 오프라인 설치 (Rocky Linux 9 용 rpm 번들 사용)
3. 런타임 사용자 및 docker 그룹 설정
4. 설치 디렉토리 생성 및 앱 파일 배포
5. 환경설정 파일 (`.env`) 대화형 설정
6. **레퍼런스 데이터 압축 해제** ← `roche_data_hg38.tar`, `roche_data_hg19.tar` 자동 탐색
7. Docker 이미지 로드
8. 라이선스 파일 배치
9. 컨테이너 기동
10. 헬스체크
11. 완료 메시지 및 접속 URL 출력

> 레퍼런스 데이터 압축 해제는 **수 시간** 소요될 수 있습니다.

### 3-5. 설치 완료 확인

설치 완료 후 출력되는 접속 URL 로 웹 브라우저에서 접속합니다.

```
http://<서버 IP>:8080/
```

기본 로그인:
- ID: `admin`
- PW: `.env` 파일의 `ADMIN_PASSWORD` 값 (기본: `changeme` → **반드시 변경**)

---

## 4. 설치 후 초기 설정

### 4-1. 관리자 비밀번호 변경

Web UI → **설정** → 관리자 비밀번호 변경

### 4-2. FASTQ 디렉토리 설정

Web UI → **설정** → FASTQ 디렉토리 경로를 실제 시퀀서 출력 경로로 변경  
(변경 후 **서비스 재시작** 버튼 클릭)

### 4-3. BED 파일 디렉토리 설정

Web UI → **설정** → BED 디렉토리 경로 확인

### 4-4. 라이선스 확인

Web UI → **설정** → 라이선스 탭에서 만료일 및 활성 기능 확인

---

## 5. hg19 분석 기능 확인

SNUH 라이선스에는 `hg19_view` 기능이 포함되어 있습니다.

1. 오더 생성 시 **레퍼런스 선택** 드롭다운에서 `hg19 (GRCh37)` 선택
2. hg19 레퍼런스 데이터가 정상 설치된 경우 즉시 사용 가능

---

## 6. API 연동 (외부 프로그램)

병원 자체 LIS/EMR 등 외부 시스템과 API 연동을 원하는 경우:

### API Key 발급

Web UI → **설정** → **외부 연동 API Key** → 복사

### API Explorer

```
http://<서버 IP>:8080/developer
```

인증 없이 접속 가능한 API 문서 및 테스트 도구입니다.

### 기본 연동 흐름 (Method A)

```bash
BASE="http://<서버>:8080"
KEY="<발급받은 API Key>"

# 1. 오더 생성
ORDER=$(curl -s -X POST "$BASE/api/orders" \
  -H "X-Api-Key: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"sample_id":"SAMPLE-001","reference":"hg38","panel":"NHL","umi_mode":true}')

ORDER_ID=$(echo $ORDER | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# 2. 분석 시작
curl -s -X POST "$BASE/api/orders/$ORDER_ID/start" -H "X-Api-Key: $KEY"
```

---

## 7. 업그레이드 절차 (향후)

새 버전이 배포될 때는 `eonelab_patch_v*.tar` 형식의 패치 파일을 전달받아 적용합니다.

```bash
tar -xf eonelab_patch_vX.Y.tar
cd eonelab_patch_vX.Y
sudo bash patch.sh --install-dir /opt/roche_snuh
```

---

## 8. 문의

- 기술 지원: [개발사 연락처]
- 라이선스 문의: [영업 담당자]
