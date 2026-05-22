# Roche_nxt — USB 기반 오프라인 설치 가이드

Docker 조차 설치되어 있지 않을 수 있는 **완전 폐쇄망 서버**에 Roche_nxt 를
USB 하나로 설치하는 방법을 다룹니다. 설치 스크립트는 11 단계로 나뉘어
각 단계마다 성공/실패를 눈으로 확인할 수 있게 출력합니다.

이 문서의 독자는 둘입니다.

- **담당자** (당신) — 번들을 만들어 USB 에 담는 사람. § 1 – § 4.
- **설치자** (현장 엔지니어) — USB 를 꽂고 `sudo bash install.sh` 를 실행하는 사람. § 5 – § 7.

관련 문서:
- `docs/OPERATIONS.md` — 일상 운영/갱신/장애 대응 런북
- `LICENSE.md` — 라이선스 메커니즘
- `docs/INSTALL.md` — (구) 단순 설치 매뉴얼

---

## 1. 전체 흐름 한눈에

```
 [담당자 PC, 인터넷 有]                     [고객 서버, 인터넷 無]
──────────────────────                    ──────────────────────
 make build                                sudo mount /dev/sdX1 /mnt/usb
 make license CUSTOMER=...                 cd /mnt/usb/<bundle>
 fetch-docker-debs (§ 3)                   sudo bash install.sh
 make usb-bundle CUSTOMER=... \                  │
                 LICENSE=... \                   ▼
                 DATA=1 \                   [1/11] 사전 점검
                 DEBS=...                   [2/11] Docker 오프라인 설치
         │                                  [3/11] 사용자/그룹
         ▼                                  [4/11] /opt/roche_nxt 생성
 deploy/usb/  (~3–140 GB)                   [5/11] Docker 이미지 로드
         │                                  [6/11] 레퍼런스 데이터 추출
 rsync → USB                                [7/11] 라이선스 설치
         │                                  [8/11] 런타임 디렉터리
         ▼                                  [9/11] .env 설정
 USB → 현장                                 [10/11] 스택 기동
                                            [11/11] 헬스체크
```

---

## 2. USB 번들 구조

`make usb-bundle` 이 다음 트리를 생성합니다:

```
deploy/usb/
├── install.sh                         ← 현장 엔지니어가 유일하게 실행
├── README.txt                         ← 1장짜리 요약
├── SHA256SUMS                         ← 전체 파일 체크섬
├── scripts/
│   ├── offline_install.sh             ← 11단계 설치 엔진
│   └── install_docker.sh              ← 오프라인 Docker 설치
├── docker/
│   └── ubuntu-22.04/
│       ├── containerd.io_*.deb
│       ├── docker-ce_*.deb
│       ├── docker-ce-cli_*.deb
│       ├── docker-buildx-plugin_*.deb
│       └── docker-compose-plugin_*.deb
├── images/
│   ├── roche_nxt_web.tar.gz           (~500 MB)
│   └── roche_nxt_analysis.tar.gz      (~3–5 GB)
├── data/
│   └── roche_data.tar.gz              (~140 GB, optional)
├── liftover/
│   └── hg38ToHg19.over.chain.gz
├── app/
│   ├── docker-compose.yml             (prod — 소스 mount 없음)
│   └── .env.example
└── license/
    └── license.json                   (고객별 서명)
```

설치자는 이 디렉터리를 통째로 USB에 복사해서 현장에 가져가기만 하면 됩니다.

---

## 3. 담당자 측 — Docker 오프라인 패키지 수집

Roche_nxt 는 타깃 OS 를 **자동 감지**해 `docker/<distro>/*.deb` 또는
`*.rpm` 을 설치합니다. 따라서 번들 제작 전에 **고객 서버의 OS** 를 먼저
확인하고 해당 패키지들을 한 디렉터리에 모아두세요.

### 3.1 고객 OS 사전 확인 (설치자에게 요청)

현장 엔지니어에게 다음 한 줄을 먼저 실행해 달라고 요청합니다:

```bash
cat /etc/os-release | grep -E '^(PRETTY_NAME|ID|VERSION_ID)='
```

예시:
```
PRETTY_NAME="Ubuntu 22.04.3 LTS"
ID=ubuntu
VERSION_ID="22.04"
```

→ 이 경우 필요한 패키지는 **Ubuntu 22.04 (jammy), amd64**.

### 3.2 (권장) 자동 다운로드 — `make usb-bundle DOCKER_FOR=...`

번들을 만드는 단계에서 다음 한 줄로 **인터넷이 되는 이 머신**에서
자동으로 받아 USB 번들에 포함됩니다 (Docker가 깔려 있어야 합니다 —
타깃 OS 컨테이너를 띄워 공식 저장소에서 받습니다):

```bash
# 단일 OS
make usb-bundle CUSTOMER="ABC" LICENSE=deploy/licenses/abc.json DATA=1 \
    DOCKER_FOR=ubuntu-22.04

# 여러 OS (다양한 고객 서버 대응 — 같은 USB로 모두 설치 가능)
make usb-bundle CUSTOMER="ABC" LICENSE=deploy/licenses/abc.json DATA=1 \
    DOCKER_FOR=ubuntu-22.04,ubuntu-24.04,rhel-9

# 알려진 5종 모두
make usb-bundle CUSTOMER="ABC" LICENSE=deploy/licenses/abc.json DATA=1 \
    DOCKER_FOR=all
```

설치 측 `install_docker.sh` 가 `/etc/os-release` 로 OS 를 감지해
번들 내 `docker/<distro>/` 중 알맞은 폴더의 패키지만 사용합니다 —
나머지는 그대로 무시됩니다.

수동으로 미리 받아 두고 `DEBS=` 로 가리키는 방식도 그대로 지원합니다.
아래는 그 수동 절차입니다.

### 3.3 (수동) .deb 다운로드 (Ubuntu 계열)

**인터넷이 되는 같은 버전 장비**(담당자 PC에 Ubuntu 22.04 컨테이너/VM
하나 띄우면 편리)에서:

```bash
mkdir -p ~/docker-debs/ubuntu-22.04
cd ~/docker-debs/ubuntu-22.04

# Docker 공식 저장소 등록 (https://docs.docker.com/engine/install/ubuntu/)
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update

# 5종 .deb 를 *다운로드만* 합니다 (--download-only)
sudo apt-get install --download-only -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# apt 캐시에서 추출
cp /var/cache/apt/archives/*.deb ./

ls -lh
#   containerd.io_1.6.*.deb
#   docker-ce_24.*.deb
#   docker-ce-cli_24.*.deb
#   docker-buildx-plugin_*.deb
#   docker-compose-plugin_*.deb
```

> **TIP**: 고객이 완전 신규 OS 라 `libseccomp2` 같은 기본 의존성도 없을
> 수 있다면, `apt-get install -d --reinstall` 로 의존성까지 한꺼번에
> 내려받아 같이 복사해 두면 안전합니다.

### 3.4 (수동) .rpm 다운로드 (RHEL/Rocky/AlmaLinux 계열)

```bash
mkdir -p ~/docker-rpms/rhel-9
cd ~/docker-rpms/rhel-9

sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf install --downloadonly --downloaddir=. -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
```

---

## 4. 담당자 측 — USB 번들 제작

### 4.1 한 줄 실행

```bash
cd /home/ken/Roche_nxt

# 이미지 + 라이선스 + 레퍼런스 + Docker .deb 모두 포함
make usb-bundle \
    CUSTOMER="ABC Hospital" \
    LICENSE=deploy/licenses/abc_hospital.json \
    DATA=1 \
    DEBS=~/docker-debs/ubuntu-22.04
```

주요 옵션:

| 변수       | 의미                                                        |
|------------|-------------------------------------------------------------|
| `CUSTOMER` | 고객 이름. `README.txt` 와 라이선스 식별용.                 |
| `LICENSE`  | `make license` 로 미리 발급한 `license.json` 의 경로.        |
| `DATA=1`   | `data/` 레퍼런스 디렉터리를 tar.gz 로 포함 (+ ~140 GB).      |
| `DEBS=DIR` | (수동) Docker .deb 디렉터리. 이름(`ubuntu-22.04`)이 그대로 사용됨.  |
| `DOCKER_FOR` | (자동) 인터넷에서 Docker 패키지를 받아 포함. 값: `ubuntu-22.04` 등. `DEBS` 와 동시 지정 불가. |
| `OUT=DIR`  | 출력 경로 (기본 `deploy/usb/`).                              |
| `REFRESH_DATA=1`  | `data/roche_data.tar.gz` 가 이미 있어도 강제로 재생성.  |
| `REFRESH_DOCKER=1`| `docker/<distro>/` 패키지가 있어도 강제로 재다운로드.   |

> **재실행 시 캐시 동작:** `make usb-bundle` 을 다시 돌리면
> `data/`(레퍼런스 tar) 와 `docker/<distro>/`(Docker 패키지) 는 이미
> 만들어져 있으면 **자동으로 재사용**합니다. 보통 바뀌는 부분(이미지,
> 라이선스, app/ 등)만 빠르게 다시 적용됩니다. 강제로 새로 받으려면 위
> `REFRESH_*` 변수를 사용하세요.

### 4.2 USB 복사

```bash
# USB 가 /media/$USER/ROCHE_NXT 에 마운트되어 있다고 가정
rsync -aP --delete deploy/usb/ /media/$USER/ROCHE_NXT/
sync
```

OR 단일 tar로:

```bash
tar -C deploy/usb -cf /media/$USER/ROCHE_NXT/roche_nxt_bundle.tar .
```

### 4.3 무결성 검증 (선택, 권장)

담당자 PC에서 한번 검증 후 USB 로 복사하면 현장에서 USB 마운트 후 바로
`sha256sum -c SHA256SUMS` 가능:

```bash
cd deploy/usb && sha256sum -c SHA256SUMS
```

설치 스크립트도 자동으로 이 파일을 검증합니다.

---

## 5. 설치자 측 — 사전 준비

고객 서버에서 확인해야 할 것:

| 항목              | 요구사항                                           |
|-------------------|----------------------------------------------------|
| OS                | Ubuntu 22.04 / 24.04 / RHEL·Rocky 8·9 (x86_64)     |
| 권한              | `sudo` 사용 가능한 계정                            |
| 디스크 여유       | ≥ 20 GB (이미지 + 런타임), 레퍼런스 포함 시 +200 GB |
| 네트워크 포트     | 8080 (웹 UI) — 방화벽 허용                          |
| 기존 Docker       | 있어도 됨(설치 스킵). 없어도 됨.                    |

---

## 6. 설치자 측 — 설치 실행

> **현재 배포 파일:** `usb_bundle_v2.tar` (USB 루트에 위치)

### 6.1 USB 마운트

```bash
# USB 장치 확인 (보통 /dev/sdb1 또는 /dev/sdc1)
lsblk

# 마운트
sudo mkdir -p /mnt/usb
sudo mount /dev/sdb1 /mnt/usb   # 장치명은 lsblk 결과에 맞게 변경

# 번들 파일 확인
ls /mnt/usb/usb_bundle_v2.tar
```

### 6.2 번들 압축 해제

```bash
# 작업 디렉터리 생성 후 압축 해제
sudo mkdir -p /opt/roche_install
sudo tar -xf /mnt/usb/usb_bundle_v2.tar -C /opt/roche_install

# 압축 해제 결과 확인 — install.sh 가 보이면 정상
ls /opt/roche_install/usb/
#   install.sh  README.txt  SHA256SUMS  app/  data/  docker/  images/  license/  liftover/  scripts/
```

### 6.3 설치 실행

```bash
cd /opt/roche_install/usb
sudo bash install.sh
```

**그게 전부입니다.** 스크립트가 11단계로 진행하면서 각 단계마다 다음과 같이
출력합니다:

```
[1/11] Preflight checks
──────────────────────────────────────────────────────────────────────
  ✓ Running as root
  ✓ Detected OS: Ubuntu 22.04.3 LTS
  ✓ Architecture: x86_64
  ✓ Bundle structure looks valid
  ✓ Disk space: 412 GB free at /opt
  ✓ All checksums match

[2/11] Docker Engine (offline install)
──────────────────────────────────────────────────────────────────────
  ! Docker is not installed. Running offline installer...
[docker] Detected: Ubuntu 22.04.3 LTS — using ubuntu-22.04/
[docker] Installing 5 .deb packages...
  ✓ Packages installed
  ✓ Docker daemon is up
  ✓ Docker:  24.0.7
  ✓ Compose: 2.21.0
[docker] Docker is ready.
  ✓ Docker installed
  ✓ Docker Compose plugin available (v2.21.0)

...

[11/11] Verify
──────────────────────────────────────────────────────────────────────
  ✓ HTTP probe passed on port 8080
  Licensed features:
      customer : ABC Hospital
      expires  : 2027-04-20
      dev_mode : False
      longitudinal: True
      igv         : True
      hg19_view   : False

============================================================
  Installation complete.
============================================================

  Web UI     : http://<this-server-ip>:8080/
  Install dir: /opt/roche_nxt
  ...
```

### 6.3 실패했을 때

스크립트는 **실패한 단계 번호를 명시하고 즉시 중단**합니다. 메시지를 고친 뒤
같은 명령을 다시 실행하세요. 이미 끝난 단계는 자동으로 감지되어
재실행되지 않습니다(idempotent).

대표적인 실패와 해결:

| 메시지                                         | 원인                                | 해결                                    |
|------------------------------------------------|-------------------------------------|-----------------------------------------|
| `ls: cannot access '...usb_bundle_v2.tar'`    | USB 마운트 실패 또는 파일 위치 오류 | `lsblk` 재확인 후 올바른 장치 마운트    |
| `install.sh: No such file or directory`        | tar 해제 경로 오류                  | `ls /opt/roche_install/usb/` 로 구조 재확인 |
| `Unsupported OS: ...`                          | 지원 OS 아님                        | 담당자에게 OS 버전 전달 → 재번들링       |
| `No packages at docker/ubuntu-XX.XX/`          | 해당 OS 용 .deb 미포함              | 담당자에게 재번들링 요청                |
| `dpkg dependencies failed`                     | OS 기본 패키지 누락                 | 의존성 .deb 추가 포함 필요              |
| `LicenseError: signature verification failed` | 잘못된 라이선스 또는 공개키 불일치  | 담당자에게 라이선스 재발급 요청         |
| `Checksum verification failed`                 | USB 손상/복사 불완전                | USB 재작성 또는 다른 매체로 재전송      |

---

## 7. 설치 후 확인 사항

### 7.1 동작 확인

```bash
cd /opt/roche_nxt
docker compose ps                       # 컨테이너 상태
docker compose logs -f roche-nxt-web    # 실시간 로그 (Ctrl-C로 종료)

curl http://localhost:8080/api/features | python3 -m json.tool
```

### 7.2 기본 디렉터리

```
/opt/roche_nxt/
├── docker-compose.yml        ← 프로덕션 버전
├── .env                      ← 경로/UID/포트 자동 설정됨
├── license/license.json      ← 0444 (읽기전용)
├── data/                     ← 레퍼런스 게놈/BED 등
├── fastq/                    ← 고객이 여기에 원본 FASTQ 업로드
├── bed/                      ← 고객이 BED 추가 시
├── results/                  ← 분석 산출물 (자동 생성)
├── work/                     ← Nextflow 작업 디렉터리
├── log/                      ← 웹 UI + 파이프라인 로그 + SQLite DB
└── liftover/                 ← hg38→hg19 chain (hg19_view 기능용)
```

### 7.3 일상 운영 명령

`/opt/roche_nxt/` 에서:

```bash
docker compose ps                       # 상태
docker compose restart roche-nxt-web    # 재시작
docker compose down                     # 중지
docker compose up -d                    # 시작
docker compose logs --tail=100          # 로그
```

라이선스 갱신·기능 추가 등 운영 시나리오는 `docs/OPERATIONS.md` § 4, § 6
을 참고하세요.

---

## 8. 제거/재설치

완전 제거:

```bash
cd /opt/roche_nxt
docker compose down
docker image rm roche_nxt_web:latest roche_nxt_analysis:latest
cd /
sudo rm -rf /opt/roche_nxt
# (선택) Docker 자체도 제거
sudo apt-get purge -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
```

재설치는 `sudo bash install.sh` 를 같은 USB 에서 다시 실행하면 됩니다.

---

## 9. 체크리스트

### 담당자

- [ ] `make build` 로 최신 이미지 빌드됨
- [ ] `make license CUSTOMER=... EXPIRES=... FEATURES=...` 실행됨
- [ ] 고객 OS 확인 후 해당 버전의 `.deb`/`.rpm` 수집 완료
- [ ] `make usb-bundle CUSTOMER=... LICENSE=... DATA=1 DEBS=...` 성공
- [ ] `deploy/usb/SHA256SUMS` 로 로컬 검증 통과
- [ ] USB 총 용량 확인 후 복사 완료 (`sync` 필수)
- [ ] 라이선스 별도 사본 백업 (재전송용)

### 설치자

- [ ] `cat /etc/os-release` 로 OS 버전 담당자에 공유
- [ ] 고객 서버에서 `sudo` 권한 확보
- [ ] USB 마운트 확인 (`lsblk` → `sudo mount /dev/sdXn /mnt/usb`)
- [ ] `ls /mnt/usb/usb_bundle_v2.tar` 로 번들 파일 존재 확인
- [ ] `sudo tar -xf /mnt/usb/usb_bundle_v2.tar -C /opt/roche_install` 압축 해제
- [ ] `ls /opt/roche_install/usb/install.sh` 로 해제 결과 확인
- [ ] `cd /opt/roche_install/usb && sudo bash install.sh` 실행, 11 단계 모두 ✓
- [ ] 웹 UI 접속 확인 (`http://<ip>:8080/`)
- [ ] 테스트 FASTQ 1세트 업로드 후 파이프라인 완주 확인
