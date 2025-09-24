#!/bin/bash

# ================================================
# Kickstart 서버 준비 스크립트
# 폐쇄망 환경에서 필요한 모든 패키지 준비
# ================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

KICKSTART_DIR="/var/www/html/ks"
ISO_MOUNT="/mnt/iso"
REPO_DIR="/var/www/html/repo"

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}    Kickstart 서버 준비${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ===== 1. 디렉토리 구조 생성 =====
echo -e "${YELLOW}[1/8] Kickstart 디렉토리 구조 생성${NC}"

mkdir -p ${KICKSTART_DIR}/{configs,scripts,packages}
mkdir -p ${REPO_DIR}/{BaseOS,AppStream,extras,docker,docker-compose,python-packages}
mkdir -p ${ISO_MOUNT}
mkdir -p /var/ftp/pub/rhel

# ===== 2. OS ISO 마운트 및 복사 =====
echo -e "${YELLOW}[2/8] OS ISO 처리${NC}"

# ISO 파일 확인 (예: CentOS, RHEL, Rocky)
if [ -f /root/CentOS*.iso ]; then
    mount -o loop /root/CentOS*.iso ${ISO_MOUNT}
elif [ -f /root/rhel*.iso ]; then
    mount -o loop /root/rhel*.iso ${ISO_MOUNT}
elif [ -f /root/Rocky*.iso ]; then
    mount -o loop /root/Rocky*.iso ${ISO_MOUNT}
else
    echo -e "${RED}OS ISO 파일을 찾을 수 없습니다!${NC}"
fi

# BaseOS와 AppStream 복사
if [ -d "${ISO_MOUNT}/BaseOS" ]; then
    cp -r ${ISO_MOUNT}/BaseOS/* ${REPO_DIR}/BaseOS/
    cp -r ${ISO_MOUNT}/AppStream/* ${REPO_DIR}/AppStream/
fi

# ===== 3. Docker 패키지 다운로드 =====
echo -e "${YELLOW}[3/8] Docker 관련 패키지 다운로드${NC}"

cd ${REPO_DIR}/docker

# Docker CE 저장소 설정 (온라인 환경에서)
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null

# Docker 패키지 다운로드
DOCKER_PACKAGES=(
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-compose-plugin"
    "docker-buildx-plugin"
    "docker-scan-plugin"
)

for pkg in "${DOCKER_PACKAGES[@]}"; do
    echo "  다운로드: $pkg"
    yumdownloader --resolve --destdir=. $pkg 2>/dev/null
done

# ===== 4. 시스템 패키지 다운로드 =====
echo -e "${YELLOW}[4/8] 시스템 패키지 다운로드${NC}"

cd ${REPO_DIR}/extras

# 추가 필요 패키지
SYSTEM_PACKAGES=(
    # 개발 도구
    "gcc"
    "gcc-c++"
    "make"
    "cmake"
    "autoconf"
    "automake"
    "kernel-devel"
    "kernel-headers"

    # Python
    "python3"
    "python3-devel"
    "python3-pip"
    "python3-setuptools"

    # 시스템 도구
    "vim-enhanced"
    "wget"
    "curl"
    "git"
    "tmux"
    "screen"
    "htop"
    "iotop"
    "sysstat"
    "net-tools"
    "bind-utils"
    "telnet"
    "nmap-ncat"
    "tcpdump"
    "traceroute"
    "mtr"

    # NFS
    "nfs-utils"
    "rpcbind"

    # 기타
    "epel-release"
    "jq"
    "tree"
    "unzip"
    "bzip2"
    "rsync"
    "socat"
    "lsof"
    "strace"
    "bc"
    "dos2unix"
)

for pkg in "${SYSTEM_PACKAGES[@]}"; do
    echo "  다운로드: $pkg"
    yumdownloader --resolve --destdir=. $pkg 2>/dev/null || true
done

# ===== 5. Docker Compose 바이너리 =====
echo -e "${YELLOW}[5/8] Docker Compose 바이너리 다운로드${NC}"

cd ${REPO_DIR}/docker-compose
COMPOSE_VERSION="v2.23.0"
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o docker-compose
chmod +x docker-compose

# ===== 6. Python 패키지 다운로드 =====
echo -e "${YELLOW}[6/8] Python 패키지 다운로드${NC}"

cd ${REPO_DIR}/python-packages
pip3 download flask requests pyyaml aiohttp jinja2 werkzeug click itsdangerous markupsafe

# ===== 7. Docker 이미지 저장 =====
echo -e "${YELLOW}[7/8] Docker 이미지 저장${NC}"

cd ${KICKSTART_DIR}/packages

# 필요한 이미지 목록
DOCKER_IMAGES=(
    "ubuntu:22.04"
    "mysql:8.0"
    "haproxy:2.8"
    "python:3.9-slim"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "prom/alertmanager:latest"
    "prom/node-exporter:latest"
    "nginx/nginx-prometheus-exporter:latest"
)

# Docker 이미지 풀 및 저장
for image in "${DOCKER_IMAGES[@]}"; do
    echo "  풀링: $image"
    docker pull $image
done

echo "  이미지 저장 중..."
docker save -o docker-images.tar ${DOCKER_IMAGES[@]}
echo -e "${GREEN}  docker-images.tar 생성 완료 ($(du -h docker-images.tar | cut -f1))${NC}"

# ===== 8. 프로젝트 파일 복사 =====
echo -e "${YELLOW}[8/8] 프로젝트 파일 준비${NC}"

# workspace 디렉토리 전체 복사
cp -r /root/workspace ${KICKSTART_DIR}/
cd ${KICKSTART_DIR}/workspace

# kickstart.cfg 복사
cp kickstart.cfg ${KICKSTART_DIR}/configs/

# 저장소 메타데이터 생성
createrepo ${REPO_DIR}/BaseOS
createrepo ${REPO_DIR}/AppStream
createrepo ${REPO_DIR}/extras
createrepo ${REPO_DIR}/docker

# ===== PXE 부트 설정 파일 =====
cat > ${KICKSTART_DIR}/configs/pxe-menu.cfg << 'EOF'
default menu.c32
prompt 0
timeout 300
ONTIMEOUT local

menu title ##### Kickstart Installation Menu #####

label 1
  menu label ^1) Install CentOS/RHEL/Rocky with Docker Stack
  kernel vmlinuz
  append initrd=initrd.img inst.ks=http://KICKSTART_SERVER_IP/ks/configs/kickstart.cfg inst.repo=http://KICKSTART_SERVER_IP/repo/BaseOS

label 2
  menu label ^2) Install Minimal OS Only
  kernel vmlinuz
  append initrd=initrd.img inst.repo=http://KICKSTART_SERVER_IP/repo/BaseOS

label 3
  menu label ^3) Boot from local drive
  localboot 0
EOF

# ===== DHCP 설정 예제 =====
cat > ${KICKSTART_DIR}/configs/dhcpd.conf.example << 'EOF'
# DHCP 설정 예제
subnet 192.168.1.0 netmask 255.255.255.0 {
    range 192.168.1.100 192.168.1.200;
    option routers 192.168.1.1;
    option domain-name-servers 8.8.8.8, 8.8.4.4;

    # PXE 부트 설정
    next-server KICKSTART_SERVER_IP;
    filename "pxelinux.0";

    # Kickstart 서버 위치
    option root-path "http://KICKSTART_SERVER_IP/ks/configs/kickstart.cfg";
}
EOF

# ===== Apache 설정 =====
cat > /etc/httpd/conf.d/kickstart.conf << 'EOF'
<Directory "/var/www/html/ks">
    Options +Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

<Directory "/var/www/html/repo">
    Options +Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF

# Apache 재시작
systemctl restart httpd
systemctl enable httpd

# ===== 완료 메시지 =====
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}    Kickstart 서버 준비 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "디렉토리 구조:"
echo "  ${KICKSTART_DIR}/configs/     - Kickstart 설정 파일"
echo "  ${KICKSTART_DIR}/scripts/     - 설치 스크립트"
echo "  ${KICKSTART_DIR}/packages/    - Docker 이미지 등"
echo "  ${KICKSTART_DIR}/workspace/   - 프로젝트 파일"
echo "  ${REPO_DIR}/                  - YUM 저장소"
echo ""
echo "Kickstart URL:"
echo "  http://$(hostname -I | awk '{print $1}')/ks/configs/kickstart.cfg"
echo ""
echo "Repository URL:"
echo "  http://$(hostname -I | awk '{print $1}')/repo/"
echo ""
echo "총 크기: $(du -sh ${KICKSTART_DIR} | cut -f1)"
echo ""
echo -e "${YELLOW}PXE 부트 설정시 위 URL을 사용하세요.${NC}"