#!/bin/bash

# ================================================
# 폐쇄망 이전을 위한 오프라인 패키지 준비
# ================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

OFFLINE_DIR="/root/offline-packages"
mkdir -p $OFFLINE_DIR

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   폐쇄망 오프라인 패키지 준비${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ===== 1. YUM 패키지 다운로드 =====
echo -e "${YELLOW}[1/4] YUM 패키지 다운로드${NC}"

cd $OFFLINE_DIR
mkdir -p rpms

# 필수 YUM 패키지 목록
PACKAGES=(
    # Docker 관련
    "docker-ce"
    "docker-ce-cli"
    "containerd.io"
    "docker-compose-plugin"

    # 시스템 도구
    "yum-utils"
    "device-mapper-persistent-data"
    "lvm2"
    "wget"
    "curl"
    "git"
    "vim"
    "net-tools"
    "bind-utils"
    "telnet"
    "nmap-ncat"
    "htop"
    "iotop"
    "sysstat"

    # NFS 관련
    "nfs-utils"
    "rpcbind"

    # Python
    "python3"
    "python3-pip"
    "gcc"
    "make"
    "openssl"
    "openssl-devel"

    # 기타 유틸리티
    "bash-completion"
    "tmux"
    "screen"
    "tree"
    "unzip"
    "bzip2"
    "rsync"
    "chrony"
    "jq"
    "bc"
    "dos2unix"
    "lsof"
    "tcpdump"
    "traceroute"
    "mtr"
    "socat"
)

# 패키지 다운로드 (의존성 포함)
for pkg in "${PACKAGES[@]}"; do
    echo "  다운로드: $pkg"
    yumdownloader --resolve --destdir=rpms $pkg 2>/dev/null || echo "    [경고] $pkg 다운로드 실패"
done

# ===== 2. Docker 이미지 저장 =====
echo -e "${YELLOW}[2/4] Docker 이미지 저장${NC}"

# 필요한 Docker 이미지 목록
IMAGES=(
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

# 이미지 풀
echo "  이미지 다운로드 중..."
for image in "${IMAGES[@]}"; do
    echo "    - $image"
    docker pull $image 2>/dev/null || echo "      [경고] $image 풀 실패"
done

# 이미지를 tar 파일로 저장
echo "  이미지를 tar 파일로 저장 중..."
docker save -o docker-images.tar ${IMAGES[@]}
echo -e "${GREEN}  docker-images.tar 생성 완료 ($(du -h docker-images.tar | cut -f1))${NC}"

# ===== 3. Python 패키지 다운로드 =====
echo -e "${YELLOW}[3/4] Python 패키지 다운로드${NC}"

mkdir -p python-packages
pip3 download -d python-packages \
    flask \
    requests \
    pyyaml \
    aiohttp \
    jinja2 \
    werkzeug \
    click \
    itsdangerous \
    markupsafe

# ===== 4. 설치 스크립트 및 설정 파일 압축 =====
echo -e "${YELLOW}[4/4] 전체 패키지 압축${NC}"

# 프로젝트 파일 복사
cp -r /root/workspace $OFFLINE_DIR/workspace

# 오프라인 설치 스크립트 생성
cat > $OFFLINE_DIR/offline-install.sh << 'OFFLINE_SCRIPT'
#!/bin/bash

# 폐쇄망에서 실행할 오프라인 설치 스크립트

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}폐쇄망 오프라인 설치 시작${NC}"

# 1. RPM 패키지 설치
echo -e "${YELLOW}[1/4] RPM 패키지 설치${NC}"
cd rpms
yum localinstall -y *.rpm

# 2. Docker 이미지 로드
echo -e "${YELLOW}[2/4] Docker 이미지 로드${NC}"
cd ..
docker load -i docker-images.tar

# 3. Python 패키지 설치
echo -e "${YELLOW}[3/4] Python 패키지 설치${NC}"
cd python-packages
pip3 install --no-index --find-links . flask requests pyyaml aiohttp

# 4. 프로젝트 파일 복사
echo -e "${YELLOW}[4/4] 프로젝트 설정${NC}"
cd ..
cp -r workspace /root/
cd /root/workspace
chmod +x complete-install.sh auto-scaler.sh

echo -e "${GREEN}오프라인 설치 완료!${NC}"
echo "이제 다음 명령을 실행하세요:"
echo "  cd /root/workspace"
echo "  ./complete-install.sh"
OFFLINE_SCRIPT

chmod +x $OFFLINE_DIR/offline-install.sh

# 전체 압축
cd /root
tar czf offline-packages.tar.gz offline-packages/

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   오프라인 패키지 준비 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo "생성된 파일:"
echo "  - offline-packages.tar.gz ($(du -h offline-packages.tar.gz | cut -f1))"
echo ""
echo "폐쇄망 이전 방법:"
echo "  1. offline-packages.tar.gz를 USB/CD로 폐쇄망 서버에 복사"
echo "  2. 폐쇄망 서버에서:"
echo "     tar xzf offline-packages.tar.gz"
echo "     cd offline-packages"
echo "     ./offline-install.sh"
echo ""
echo -e "${GREEN}준비 완료!${NC}"