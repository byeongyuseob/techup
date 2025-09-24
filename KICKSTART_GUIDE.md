# 📦 폐쇄망 Kickstart 서버 완전 가이드

## 🎯 개요

폐쇄망에서 Kickstart 서버를 통해 OS 설치부터 Docker Stack 구성까지 완전 자동화

## 📋 Kickstart 서버에 필요한 준비물

### 1. OS ISO 파일
- CentOS 7/8/9 DVD ISO
- RHEL 7/8/9 DVD ISO
- Rocky Linux 8/9 DVD ISO

### 2. 패키지 (kickstart.cfg에 정의됨)

#### 필수 시스템 패키지
```
@^minimal
@core
@development
kernel kernel-devel kernel-headers
bash bash-completion sudo
openssh-server openssh-clients
rsync tar gzip bzip2 xz unzip zip
wget curl net-tools bind-utils
telnet nmap-ncat traceroute mtr tcpdump
vim-enhanced nano git tree
htop iotop sysstat lsof strace psmisc
bc jq dos2unix
```

#### 개발 도구
```
gcc gcc-c++ make cmake
autoconf automake libtool
patch pkgconfig gettext
flex bison gdb
```

#### Python 환경
```
python3 python3-devel python3-pip
python3-setuptools python3-libs
```

#### NFS 관련
```
nfs-utils rpcbind libnfsidmap nfs4-acl-tools
```

#### 파일시스템 & LVM
```
xfsprogs e2fsprogs lvm2
device-mapper-persistent-data
parted gdisk
```

#### 시스템 관리
```
systemd systemd-sysv systemd-libs
dbus acpid irqbalance microcode_ctl
numactl tuned
yum-utils createrepo
```

### 3. Docker 패키지 (별도 다운로드 필요)
```bash
docker-ce
docker-ce-cli
containerd.io
docker-compose-plugin
docker-buildx-plugin
```

### 4. Docker 이미지 (tar 파일로 저장)
```bash
ubuntu:22.04          # Nginx 베이스
mysql:8.0             # 데이터베이스
haproxy:2.8          # 로드 밸런서
python:3.9-slim      # Alert Webhook
prom/prometheus:latest
grafana/grafana:latest
prom/alertmanager:latest
prom/node-exporter:latest
nginx/nginx-prometheus-exporter:latest
```

## 🚀 Kickstart 서버 구성 절차

### Step 1: Kickstart 서버 준비
```bash
# Kickstart 서버 (인터넷 연결된 서버)에서
chmod +x kickstart-server-prepare.sh
./kickstart-server-prepare.sh
```

### Step 2: 디렉토리 구조
```
/var/www/html/
├── ks/
│   ├── configs/
│   │   └── kickstart.cfg      # Kickstart 설정
│   ├── scripts/                # 설치 스크립트
│   ├── packages/
│   │   └── docker-images.tar   # Docker 이미지
│   └── workspace/              # 프로젝트 파일
└── repo/
    ├── BaseOS/                 # OS 기본 패키지
    ├── AppStream/              # 애플리케이션 스트림
    ├── extras/                 # 추가 패키지
    ├── docker/                 # Docker RPM
    ├── docker-compose/         # Docker Compose 바이너리
    └── python-packages/        # Python 오프라인 패키지
```

### Step 3: PXE 부트 설정

#### DHCP 서버 설정
```bash
# /etc/dhcp/dhcpd.conf
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    next-server KICKSTART_SERVER_IP;
    filename "pxelinux.0";
}
```

#### TFTP 서버 설정
```bash
# TFTP 루트에 복사
cp /usr/share/syslinux/pxelinux.0 /var/lib/tftpboot/
cp /mnt/iso/images/pxeboot/{vmlinuz,initrd.img} /var/lib/tftpboot/

# PXE 메뉴 설정
cat > /var/lib/tftpboot/pxelinux.cfg/default << EOF
label linux
  kernel vmlinuz
  append initrd=initrd.img inst.ks=http://KICKSTART_SERVER_IP/ks/configs/kickstart.cfg
EOF
```

### Step 4: Apache 웹 서버 설정
```bash
systemctl enable --now httpd
firewall-cmd --add-service=http --permanent
firewall-cmd --reload
```

## 📝 Kickstart 설정 주요 내용

### 디스크 파티션 (LVM)
```
/boot          1GB    (XFS)
/              20GB   (XFS)
/var           40GB   (XFS)
/var/lib/docker 100GB (XFS) # Docker 전용
/home          10GB   (XFS)
swap           8GB
```

### 자동 설정 항목
- ✅ SELinux 비활성화
- ✅ 방화벽 비활성화
- ✅ root 비밀번호: naver123
- ✅ 시스템 최적화 (sysctl)
- ✅ Docker 저장소 설정
- ✅ 서비스 자동 시작 설정

### Post 설치 스크립트
1. 시스템 최적화 설정
2. Docker 설치 스크립트 생성
3. 프로젝트 설정 스크립트 생성
4. systemd 서비스 파일 생성
5. rc.local 자동 실행 설정

## 🖥️ 클라이언트 설치 절차

### 자동 설치 (PXE 부트)
1. 서버 BIOS에서 PXE 부트 활성화
2. 네트워크 부트 선택
3. 자동으로 Kickstart 설치 진행
4. 재부팅 후 자동으로 Docker Stack 시작

### 수동 설치 후 실행
```bash
# 설치 완료 후 실행
/root/scripts/install-docker.sh
/root/scripts/install-compose.sh
/root/scripts/setup-project.sh

# 서비스 시작
systemctl start docker-stack
systemctl start auto-scaler
```

## 📊 설치 후 확인

```bash
# 시스템 확인
cat /root/SETUP_COMPLETE.txt

# Docker 상태
docker ps

# 서비스 상태
systemctl status docker-stack
systemctl status auto-scaler

# 웹 접속
curl http://localhost
```

## 🔧 문제 해결

### Kickstart 서버 접근 불가
```bash
# Apache 확인
systemctl status httpd
curl http://localhost/ks/configs/kickstart.cfg

# 권한 확인
chmod -R 755 /var/www/html/ks
chmod -R 755 /var/www/html/repo
```

### 패키지 설치 실패
```bash
# 저장소 메타데이터 재생성
createrepo --update /var/www/html/repo/BaseOS
createrepo --update /var/www/html/repo/docker
```

### Docker 이미지 로드 실패
```bash
# 수동 로드
docker load -i /mnt/cdrom/docker-images.tar
```

## 📋 체크리스트

### Kickstart 서버
- [ ] OS ISO 파일 준비
- [ ] kickstart-server-prepare.sh 실행
- [ ] Apache/DHCP/TFTP 서비스 확인
- [ ] 저장소 메타데이터 생성
- [ ] Docker 이미지 tar 파일 생성

### 클라이언트 서버
- [ ] PXE 부트 설정
- [ ] 네트워크 연결 확인
- [ ] 자동 설치 완료
- [ ] Docker Stack 실행 확인
- [ ] 웹 서비스 접속 테스트

## 🎯 최종 결과

1. **OS 설치**: 자동 파티션, 패키지 설치
2. **시스템 설정**: SELinux/방화벽 비활성화, 최적화
3. **Docker 환경**: Docker/Compose 설치, 이미지 로드
4. **프로젝트 배포**: 모든 설정 파일 생성
5. **자동 시작**: 부팅시 자동으로 서비스 시작

---

**완전 자동화된 폐쇄망 배포 시스템 완성!**