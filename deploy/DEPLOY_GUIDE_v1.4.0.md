# Roche_nxt v1.4.0 배포 가이드

생성일: 2026-08-09  
버전: **1.4.0**

---

## 한 줄 요약

**USB의 `v1.4.0_full` + `roche_install.sh` 하나**로 신규 설치와 기존 병원 패치를 모두 처리합니다.  
(신규/패치는 스크립트가 자동 감지합니다.)

---

## USB 구성 (`deploy/v1.4.0_full`)

| 파일 | 역할 |
|------|------|
| `roche_install.sh` | **유일한 설치/패치 스크립트** |
| `Roche_nxt_v1.4.0.tar.gz` | 파이프라인 + Web 소스 |
| `roche_nxt_web_v1.4.0.tar.gz` | Web Docker 이미지 |
| `roche_nxt_analysis_v1.3.0.tar.gz` | Analysis 이미지 (도구, v1.4와 동일) |
| `roche_data_hg19.tar.gz` | hg19 레퍼런스 |
| `roche_data_hg38_base.tar.gz` | hg38 refs/snpeff/bed/blocklist |
| `roche_data_hg38_dbsnp.tar.gz` | hg38 dbSNP |
| `apply_*.sh` | (선택) 구형 패치 스크립트 — 기본은 사용 안 함 |

USB에 `v1.4.0_full` 폴더 통째로 복사하면 됩니다.

---

## 공통 명령 (이게 전부)

```bash
# USB 마운트 경로를 실제 경로로 바꾸세요
USB=/media/usb/v1.4.0_full

bash $USB/roche_install.sh \
  --install-dir <설치경로> \
  --patch-dir $USB \
  --source offline
```

- **신규 병원**: `<설치경로>`에 기존 설치가 없으면 → 신규 설치  
- **기존 병원**: `.env` 또는 compose 가 있으면 → 패치 (DB·`.env`·results 보존, data는 USB 내용으로 채움/덮어씀)

data 압축 해제에 시간이 걸립니다. 의도적으로 단순화한 방식입니다.

---

## 병원별 예시

### BSCH (기존, hg38 중심 → hg19도 USB로 함께 설치)

```bash
USB=/media/usb/v1.4.0_full   # 실제 USB 경로

# 설치 경로 확인
docker inspect roche_nxt_web \
  --format '{{range .Mounts}}{{if eq .Destination "/roche_nxt"}}{{.Source}}{{end}}{{end}}'
# 예: /opt/roche_bsch

bash $USB/roche_install.sh \
  --install-dir /opt/roche_bsch \
  --patch-dir $USB \
  --source offline
```

패치 후 웹에서 `Ver.1.4.0` 확인.  
(예전에 `NXF_SYNTAX_PARSER=v1` 을 썼다면 스크립트가 `.env`에서 자동 제거합니다.)

### EONE (기존, `/home/roche`, hg19 이미 있음)

```bash
USB=/media/usb/v1.4.0_full

sudo bash $USB/roche_install.sh \
  --install-dir /home/roche \
  --patch-dir $USB \
  --source offline
```

- 기존 `.env` / DB / results 유지  
- data tar가 있으면 hg19·hg38을 다시 풀어 **최신 데이터로 맞춤** (시간 소요 OK)  
- 실행 유저가 `roche`이면 `sudo` 후 ownership은 환경에 맞게 확인

### 신규 병원

```bash
USB=/media/usb/v1.4.0_full

# Docker 없는 경우 먼저 설치 후
bash $USB/roche_install.sh \
  --install-dir /opt/roche_nxt \
  --patch-dir $USB \
  --source offline \
  --port 8080
```

---

## 확인

```bash
curl -s http://localhost:8080/api/version
docker images | grep roche_nxt
ls <DATA_HOST_DIR>/refs/hg19/hg19.fa
ls <DATA_HOST_DIR>/refs/hg38/ucsc.hg38.fasta
```

웹 UI 사이드바: **Ver.1.4.0**

---

## 온라인 패치 (BI 담당, GitHub 가능 시)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xformyx/Roche_panel_analysis/main/deploy/scripts/upgrade_from_github.sh) \
  --install-dir /opt/roche_nxt \
  --tag v1.4.0
```

레퍼런스 data는 USB/별도 전달분이 그대로 필요합니다.

---

## 롤백

```bash
INSTALL_DIR=/opt/roche_nxt   # 실제 경로
ls $INSTALL_DIR/backup/
# 예: cp $INSTALL_DIR/backup/YYYYMMDD_HHMMSS/log/orders_nxt.db $INSTALL_DIR/log/orders_nxt.db
#     cp $INSTALL_DIR/backup/YYYYMMDD_HHMMSS/.env $INSTALL_DIR/.env
docker compose -f $INSTALL_DIR/docker-compose.prod.yml up -d --force-recreate
# compose 파일이 docker-compose.yml 이면 그 파일 사용
```

---

## 트러블슈팅

| 증상 | 해결 |
|------|------|
| 웹 접속 불가 | `docker ps \| grep roche` → `docker compose up -d` |
| 이전 버전으로 보임 | Ctrl+Shift+R |
| IGV hg19 실패 | `DATA_HOST_DIR` / `roche_data` 마운트, fasta 존재 확인 |
| 분석 안 뜸 | `docker images \| grep analysis` |
| DB 권한 오류 | `chown` 을 실행 유저로 `log/` 에 적용 |
