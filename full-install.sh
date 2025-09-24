#!/bin/bash

# ================================================
# 폐쇄망 깡통 서버 완전 자동 설치 스크립트
# CentOS/RHEL 7,8,9 & Rocky Linux 8,9 지원
# ================================================

set -e

# 설정 값
NFS_SERVER_IP="10.95.137.5"
ADMIN_PASSWORD="naver123"
ADMIN_USER="admin"
MYSQL_PASSWORD="naver123"
GRAFANA_PASSWORD="naver123"
WORK_DIR="/root/workspace"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 로그 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# OS 버전 확인
check_os() {
    if [ -f /etc/redhat-release ]; then
        OS_VERSION=$(cat /etc/redhat-release)
        log_info "OS 확인: $OS_VERSION"
    else
        log_error "CentOS/RHEL/Rocky Linux가 아닙니다."
        exit 1
    fi
}

# 루트 권한 확인
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "root 권한으로 실행해주세요."
        exit 1
    fi
}

# SELinux 비활성화
disable_selinux() {
    log_info "SELinux 비활성화..."
    setenforce 0 2>/dev/null || true
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config 2>/dev/null || true
    sed -i 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config 2>/dev/null || true
}

# 방화벽 비활성화
disable_firewall() {
    log_info "방화벽 완전 비활성화..."
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    systemctl mask firewalld 2>/dev/null || true

    # iptables 초기화
    iptables -F 2>/dev/null || true
    iptables -X 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    iptables -t nat -X 2>/dev/null || true
    iptables -t mangle -F 2>/dev/null || true
    iptables -t mangle -X 2>/dev/null || true
    iptables -P INPUT ACCEPT 2>/dev/null || true
    iptables -P FORWARD ACCEPT 2>/dev/null || true
    iptables -P OUTPUT ACCEPT 2>/dev/null || true
}

# 기본 패키지 설치
install_basic_packages() {
    log_info "기본 패키지 설치..."

    # EPEL 저장소 설치
    yum install -y epel-release 2>/dev/null || true

    # 필수 패키지 설치
    yum install -y \
        yum-utils \
        device-mapper-persistent-data \
        lvm2 \
        wget \
        curl \
        git \
        vim \
        net-tools \
        telnet \
        bind-utils \
        htop \
        iotop \
        sysstat \
        nfs-utils \
        python3 \
        python3-pip \
        gcc \
        make \
        openssl \
        openssl-devel \
        kernel-devel \
        kernel-headers \
        bash-completion \
        tmux \
        screen \
        tree \
        unzip \
        bzip2 \
        nmap \
        tcpdump \
        traceroute \
        mtr \
        nc \
        socat \
        jq \
        rsync \
        chrony \
        2>/dev/null || true
}

# Docker 설치
install_docker() {
    log_info "Docker 설치..."

    # 기존 Docker 제거
    yum remove -y docker \
        docker-client \
        docker-client-latest \
        docker-common \
        docker-latest \
        docker-latest-logrotate \
        docker-logrotate \
        docker-engine \
        podman \
        runc 2>/dev/null || true

    # Docker 저장소 추가
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || \
    yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo 2>/dev/null

    # Docker 설치
    yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || {
        # 오프라인 설치를 위한 대체 방법
        log_warn "온라인 설치 실패. 로컬 패키지 설치 시도..."
        yum install -y docker 2>/dev/null || true
    }

    # Docker 서비스 설정
    systemctl enable docker
    systemctl start docker

    # Docker 설정 최적화
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "exec-opts": ["native.cgroupdriver=systemd"],
    "registry-mirrors": [],
    "insecure-registries": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
    "live-restore": true
}
EOF

    systemctl daemon-reload
    systemctl restart docker
}

# Docker Compose 설치
install_docker_compose() {
    log_info "Docker Compose 설치..."

    # 방법 1: Docker Compose V2 (권장)
    if [ -f /usr/libexec/docker/cli-plugins/docker-compose ]; then
        log_info "Docker Compose V2 이미 설치됨"
    else
        # 방법 2: Standalone 바이너리
        COMPOSE_VERSION="v2.23.0"
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose 2>/dev/null || {
            log_warn "Docker Compose 다운로드 실패. 수동 설치 필요"
        }

        if [ -f /usr/local/bin/docker-compose ]; then
            chmod +x /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        fi
    fi
}

# 시스템 최적화
optimize_system() {
    log_info "시스템 최적화 설정..."

    # sysctl 최적화
    cat >> /etc/sysctl.conf << EOF

# Network optimization for web server
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 10000 65000
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_slow_start_after_idle = 0

# File system
fs.file-max = 2097152
fs.nr_open = 1048576

# Memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

    sysctl -p 2>/dev/null || true

    # ulimit 설정
    cat >> /etc/security/limits.conf << EOF

* soft nofile 65535
* hard nofile 65535
* soft nproc 32768
* hard nproc 32768
root soft nofile 65535
root hard nofile 65535
root soft nproc 32768
root hard nproc 32768
EOF
}

# 작업 디렉토리 생성 및 파일 복사
setup_workspace() {
    log_info "작업 디렉토리 설정..."

    mkdir -p $WORK_DIR
    cd $WORK_DIR

    # Git이 있으면 클론, 없으면 현재 파일 사용
    if command -v git &> /dev/null; then
        if [ ! -d ".git" ]; then
            git clone https://github.com/byeongyuseob/techup.git . 2>/dev/null || {
                log_warn "Git 클론 실패. 로컬 파일 사용"
            }
        fi
    fi
}

# 모든 설정 파일 생성
create_all_configs() {
    log_info "모든 설정 파일 생성..."

    # docker-compose.yml 수정 (NFS IP, 비밀번호 변경)
    if [ -f docker-compose.yml ]; then
        sed -i "s/10.95.137.10/$NFS_SERVER_IP/g" docker-compose.yml
        sed -i "s/MYSQL_ROOT_PASSWORD: .*/MYSQL_ROOT_PASSWORD: $MYSQL_PASSWORD/g" docker-compose.yml
        sed -i "s/GF_SECURITY_ADMIN_PASSWORD=.*/GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_PASSWORD/g" docker-compose.yml
    fi

    # HAProxy 비밀번호 설정
    if [ -f haproxy/haproxy.cfg ]; then
        # admin:naver123 의 MD5 해시
        HAPROXY_PASS_HASH='$1$SomeSalt$7kDN7Qyb8YOnZPIJZFK0K/'
        sed -i "s/stats auth .*/stats auth admin:$ADMIN_PASSWORD/g" haproxy/haproxy.cfg
    fi
}

# NFS 마운트 설정
setup_nfs() {
    log_info "NFS 설정..."

    # NFS 서비스 활성화
    systemctl enable nfs-utils 2>/dev/null || true
    systemctl start nfs-utils 2>/dev/null || true

    # rpcbind 활성화
    systemctl enable rpcbind 2>/dev/null || true
    systemctl start rpcbind 2>/dev/null || true

    # NFS 테스트 마운트
    mkdir -p /mnt/nfs-test
    mount -t nfs ${NFS_SERVER_IP}:/nfs/shared /mnt/nfs-test 2>/dev/null || {
        log_warn "NFS 마운트 실패. NFS 서버 확인 필요"
    }
    umount /mnt/nfs-test 2>/dev/null || true
}

# 서비스 자동 시작 설정
setup_services() {
    log_info "서비스 자동 시작 설정..."

    # Docker 자동 시작
    systemctl enable docker 2>/dev/null || true

    # rc.local 설정 (부팅시 자동 실행)
    cat > /etc/rc.d/rc.local << 'EOF'
#!/bin/bash
# Docker 컨테이너 자동 시작
sleep 30
cd /root/workspace
docker compose up -d --scale nginx=2
nohup /root/workspace/auto-scaler.sh > /var/log/auto-scaler.log 2>&1 &
EOF

    chmod +x /etc/rc.d/rc.local
    systemctl enable rc-local 2>/dev/null || true

    # systemd 서비스 생성 (대체 방법)
    cat > /etc/systemd/system/docker-stack.service << EOF
[Unit]
Description=Docker Stack Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${WORK_DIR}
ExecStart=/usr/bin/docker compose up -d --scale nginx=2
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/auto-scaler.service << EOF
[Unit]
Description=Docker Auto Scaler
After=docker-stack.service
Requires=docker-stack.service

[Service]
Type=simple
WorkingDirectory=${WORK_DIR}
ExecStart=${WORK_DIR}/auto-scaler.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable docker-stack 2>/dev/null || true
    systemctl enable auto-scaler 2>/dev/null || true
}

# 크론잡 설정
setup_cron() {
    log_info "크론잡 설정..."

    # 헬스체크 크론잡
    cat > /usr/local/bin/docker-health-check.sh << 'EOF'
#!/bin/bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(unhealthy|Exited)" && {
    cd /root/workspace
    docker compose up -d --scale nginx=2
}
EOF

    chmod +x /usr/local/bin/docker-health-check.sh

    # 크론탭 추가
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/docker-health-check.sh") | crontab -
}

# 로그 로테이션 설정
setup_logrotate() {
    log_info "로그 로테이션 설정..."

    cat > /etc/logrotate.d/docker-containers << EOF
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
}
EOF
}

# 호스트 파일 설정
setup_hosts() {
    log_info "호스트 파일 설정..."

    # 로컬 해석 추가
    grep -q "nfs-server" /etc/hosts || echo "${NFS_SERVER_IP} nfs-server" >> /etc/hosts
}

# Python 패키지 설치
install_python_packages() {
    log_info "Python 패키지 설치..."

    pip3 install --upgrade pip 2>/dev/null || true
    pip3 install flask requests pyyaml 2>/dev/null || true
}

# 메인 실행
main() {
    echo "================================================"
    echo "   폐쇄망 깡통 서버 완전 자동 설치 시작"
    echo "================================================"
    echo ""

    check_root
    check_os
    disable_selinux
    disable_firewall
    install_basic_packages
    install_docker
    install_docker_compose
    optimize_system
    setup_workspace
    create_all_configs
    setup_nfs
    setup_services
    setup_cron
    setup_logrotate
    setup_hosts
    install_python_packages

    echo ""
    echo "================================================"
    echo "   설치 완료!"
    echo "================================================"
    echo ""
    echo "서버 IP: $(hostname -I | awk '{print $1}')"
    echo ""
    echo "1. 서비스 시작:"
    echo "   cd ${WORK_DIR}"
    echo "   docker compose up -d --scale nginx=2"
    echo ""
    echo "2. 오토스케일러 시작:"
    echo "   nohup ./auto-scaler.sh &"
    echo ""
    echo "3. 서비스 확인:"
    echo "   docker ps"
    echo ""
    echo "4. 접속 정보:"
    echo "   - 웹: http://$(hostname -I | awk '{print $1}')"
    echo "   - HAProxy Stats: http://$(hostname -I | awk '{print $1}')/haproxy-stats (admin/${ADMIN_PASSWORD})"
    echo "   - Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/${GRAFANA_PASSWORD})"
    echo "   - Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
    echo ""
    echo "5. 재부팅 후 자동 시작 설정됨"
    echo ""
    log_info "설치 로그: /var/log/messages"
}

# 스크립트 실행
main 2>&1 | tee -a /var/log/docker-install.log