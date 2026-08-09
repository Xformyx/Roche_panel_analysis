# Roche_nxt v1.4.0 배포 가이드

생성일: 2026-08-09  
버전: **1.4.0**

---

## 주요 변경 내용

- UMI QC 리포트 추가 (UMI 패밀리 depth 통계)
- IGV BAM 뷰어: hg19 지원, `_clipped_sorted.bam` 자동 우선 선택
- 분석 결과 디렉터리 구조 개선 (오더별 results 분리)
- Web UI 재시작 시 경고 모달 추가 (분석 중 재시작 방지)
- docker-compose: roche_data 마운트 추가 (hg19 IGV 참조)

---

## 케이스별 배포 방법

---

### 케이스 1.1 — 기존 설치 업데이트 (오프라인)

> 병원 서버가 인터넷 차단 환경일 때 사용. 패치 파일을 USB 또는 SCP로 전달.

#### 개발 서버에서 (패치 파일 준비)

```bash
# 패치 파일 위치
ls /home/ken/Roche_nxt/deploy/patches/roche_patch_v1.4.0/
# roche_nxt_web_v1.4.0.tar.gz  (140 MB) — Web Docker 이미지
# Roche_nxt_v1.4.0.tar.gz      (156 MB) — 소스 파일
# apply_patch.sh               — 적용 스크립트
# apply_full_patch.sh          — EONE 전용 풀패치 스크립트
# PATCH_NOTES.md

# 단일 tar로 묶어서 전달
cd /home/ken/Roche_nxt/deploy/patches
tar -czf roche_patch_v1.4.0.tar.gz roche_patch_v1.4.0/
# → USB 복사 또는 scp로 병원 서버 전송
```

#### 병원 서버에서 (적용)

```bash
# 1. 패치 파일 압축 해제
cd /tmp
tar -xzf roche_patch_v1.4.0.tar.gz

# 2. 패치 적용 (설치 경로 자동 탐색)
bash /tmp/roche_patch_v1.4.0/apply_patch.sh

# 또는 경로 명시
bash /tmp/roche_patch_v1.4.0/apply_patch.sh --install-dir /opt/roche_nxt

# 3. 적용 확인
# 웹 브라우저에서 접속 → 사이드바 하단 버전 확인: v1.4.0
```

> **EONE (`/home/roche`, root 설치)**: `apply_full_patch.sh` 사용
>
> hg19 데이터는 이미 설치돼 있고 **파이프라인 + Web UI만** 갱신하는 경우:
> ```bash
> # 패치 파일을 /home/roche/roche_install/patch 등에 둔 뒤
> sudo bash /tmp/roche_patch_v1.4.0/apply_full_patch.sh \
>     --install-dir /home/roche \
>     --patch-dir /home/roche/roche_install/patch \
>     --run-user roche \
>     --skip-hg19
> ```
> - `--skip-hg19` : 기존 hg19 data 덮어쓰지 않음 (EONE처럼 이미 받은 경우 필수에 가깝음)
> - ownership / `.env` UID·GID 갱신은 스크립트가 처리 (`chown` 별도 불필요)
> - 분석 이미지도 안 바꿀 때만: `--skip-analysis` 추가
>
> hg19 tar까지 같이 재설치할 때만 `--skip-hg19` 를 빼면 됩니다.

---

### 케이스 1.2 — 기존 설치 업데이트 (온라인)

> 병원 BI 담당자가 직접 수행. GitHub 접속 가능 환경.

#### 전제 조건 확인

```bash
# GitHub 접속 가능 여부
curl -s --connect-timeout 5 https://github.com | head -1

# 현재 설치 경로 확인
docker inspect roche_nxt_web \
    --format '{{range .Mounts}}{{if eq .Destination "/roche_nxt"}}{{.Source}}{{end}}{{end}}'
```

#### 업데이트 실행 (한 줄 명령)

```bash
# 자동 탐색 (설치 경로를 /opt/roche_nxt, /home/*/roche_nxt 순으로 탐색)
bash <(curl -fsSL https://raw.githubusercontent.com/Xformyx/Roche_panel_analysis/main/deploy/scripts/upgrade_from_github.sh)

# 또는 경로 명시
bash <(curl -fsSL https://raw.githubusercontent.com/Xformyx/Roche_panel_analysis/main/deploy/scripts/upgrade_from_github.sh) \
    --install-dir /opt/roche_nxt \
    --tag v1.4.0
```

#### 업데이트 상세 절차 (수동)

```bash
INSTALL_DIR=/opt/roche_nxt   # ← 실제 설치 경로로 변경

cd $INSTALL_DIR

# 1. 최신 소스 pull
git fetch origin main
git reset --hard origin/main

# 2. Web 이미지 재빌드
docker build -t roche_nxt_web:latest web_ui/

# 3. 서비스 재시작 (볼륨 마운트 반영)
docker compose -f docker-compose.prod.yml up -d --force-recreate

# 4. 버전 확인
curl -s http://localhost:8080/api/version 2>/dev/null || \
    docker exec roche_nxt_web cat /app/version.json
```

> **BI 담당자용 체크리스트**
> - [ ] GitHub 접속 가능 확인
> - [ ] 분석 중인 작업 없음 확인 (`docker ps | grep nxt_`)
> - [ ] 업데이트 전 백업: `cp $INSTALL_DIR/log/orders_nxt.db ~/orders_nxt.db.bak`
> - [ ] 업데이트 실행
> - [ ] 웹 브라우저에서 v1.4.0 확인

---

### 케이스 2 — 신규 병원 설치

> 새 서버에 처음 설치하는 경우.

#### 2-A. 온라인 설치 (GitHub 접속 가능)

```bash
# 1. Docker 설치 (없는 경우)
curl -fsSL https://get.docker.com | bash
sudo usermod -aG docker $USER
newgrp docker

# 2. 통합 설치 스크립트 실행
bash <(curl -fsSL https://raw.githubusercontent.com/Xformyx/Roche_panel_analysis/main/deploy/scripts/roche_install.sh) \
    --install-dir /opt/roche_nxt \
    --port 8080 \
    --source online

# 3. hg38 레퍼런스 데이터 설치 (별도 전달: roche_data_hg38.tar)
tar -xf roche_data_hg38.tar -C /opt/roche_nxt/data/

# 4. 서비스 기동
cd /opt/roche_nxt
docker compose -f docker-compose.prod.yml up -d
```

#### 2-B. 오프라인 설치 (인터넷 차단 환경)

필요 파일 (USB로 전달):
```
roche_nxt_web_v1.4.0.tar.gz      — Web 이미지 (140 MB)
roche_nxt_analysis_v1.4.0.tar.gz — Analysis 이미지 (별도 준비, ~8 GB)
Roche_nxt_v1.4.0.tar.gz          — 소스 파일 (156 MB)
roche_data_hg38.tar               — hg38 레퍼런스 데이터 (~50 GB)
roche_install.sh                  — 설치 스크립트
```

```bash
# 1. USB 마운트 후 설치 스크립트 실행
bash /media/usb/roche_install.sh \
    --install-dir /opt/roche_nxt \
    --patch-dir /media/usb \
    --port 8080 \
    --source offline

# (hg19도 필요한 경우 roche_data_hg19.tar 추가)
# tar -xf /media/usb/roche_data_hg19.tar -C /opt/roche_nxt/data/
```

---

## 패치 파일 전달 방법

```bash
# 개발 서버 → 병원 서버 SCP 전송
scp /home/ken/Roche_nxt/deploy/patches/roche_patch_v1.4.0.tar.gz \
    admin@hospital-server:/tmp/

# 또는 USB 복사 후 서버에서 마운트
cp deploy/patches/roche_patch_v1.4.0.tar.gz /media/usb/
```

---

## 롤백 방법

```bash
# apply_patch.sh 실행 시 자동 생성된 백업 사용
INSTALL_DIR=/opt/roche_nxt

# 백업 위치 확인
ls $INSTALL_DIR/backup/

# DB 복원
cp $INSTALL_DIR/backup/orders_nxt.db.bak $INSTALL_DIR/log/orders_nxt.db

# 이전 이미지로 복원 (이전 버전 이미지가 남아있는 경우)
docker tag roche_nxt_web:backup roche_nxt_web:latest
docker compose -f $INSTALL_DIR/docker-compose.prod.yml up -d --force-recreate
```

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 웹 접속 불가 | 컨테이너 미기동 | `docker ps \| grep roche` 확인 후 `docker compose up -d` |
| 버전이 이전 버전 | 브라우저 캐시 | Ctrl+Shift+R (강제 새로고침) |
| IGV 초기화 실패 (hg19) | roche_data 미마운트 | `docker-compose.yml`에 `roche_data` 볼륨 확인 |
| 분석이 시작되지 않음 | 이미지 미로드 | `docker images \| grep roche_nxt_analysis` 확인 |
| DB 접근 오류 | 권한 문제 | `chown -R $(id -u):$(id -g) $INSTALL_DIR/log/` |
