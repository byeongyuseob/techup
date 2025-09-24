#!/bin/bash

#############################################
# setup-services.sh
# 시스템 서비스 설정 및 시작 스크립트
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[2/5] 시스템 서비스 설정 시작${NC}"

# Docker 서비스 설정 및 시작
echo -e "${YELLOW}Docker 서비스 시작...${NC}"
systemctl enable docker
systemctl start docker

# Docker 데몬 설정
echo -e "${YELLOW}Docker 데몬 설정...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << EOF
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "insecure-registries": ["0.0.0.0/0"],
    "registry-mirrors": [],
    "storage-driver": "overlay2"
}
EOF

systemctl daemon-reload
systemctl restart docker

# Docker Compose 권한 설정
echo -e "${YELLOW}Docker Compose 권한 설정...${NC}"
chmod +x /usr/local/bin/docker-compose 2>/dev/null || true
chmod +x /usr/bin/docker-compose 2>/dev/null || true

# 커널 파라미터 설정 (컨테이너 성능 향상)
echo -e "${YELLOW}커널 파라미터 최적화...${NC}"
cat > /etc/sysctl.d/99-docker.conf << EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.max_map_count = 262144
fs.file-max = 2097152
EOF

sysctl --system > /dev/null 2>&1

# NFS 클라이언트 서비스 설정
echo -e "${YELLOW}NFS 클라이언트 서비스 설정...${NC}"
systemctl enable nfs-utils 2>/dev/null || true
systemctl start nfs-utils 2>/dev/null || true

# 로그 로테이션 설정
echo -e "${YELLOW}로그 로테이션 설정...${NC}"
cat > /etc/logrotate.d/docker-containers << EOF
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    sharedscripts
    postrotate
        docker kill --signal=USR1 \$(docker ps -q) 2>/dev/null || true
    endscript
}
EOF

# Docker 소켓 권한 설정
echo -e "${YELLOW}Docker 소켓 권한 설정...${NC}"
chmod 666 /var/run/docker.sock 2>/dev/null || true

# 서비스 상태 확인
echo -e "${YELLOW}서비스 상태 확인...${NC}"
docker --version
docker-compose --version
systemctl is-active docker

echo -e "${GREEN}✅ 서비스 설정 완료${NC}"