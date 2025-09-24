#!/bin/bash

#############################################
# 시스템 초기 설정 스크립트
# Docker, Docker Registry, NFS 설정
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정 변수
REGISTRY_SERVER="192.168.0.200:5000"
NFS_SERVER="10.95.137.10"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   모니터링 스택 시스템 설정 시작${NC}"
echo -e "${BLUE}======================================${NC}"

# 1. 기본 패키지 설치
echo -e "\n${YELLOW}[1/7] 기본 패키지 설치중...${NC}"
yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    nfs-utils \
    git \
    curl \
    wget \
    net-tools \
    nc \
    python3 \
    python3-pip

# 2. Docker 설치
echo -e "\n${YELLOW}[2/7] Docker 설치중...${NC}"
if ! command -v docker &> /dev/null; then
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum install -y docker-ce docker-ce-cli containerd.io
else
    echo -e "${GREEN}Docker가 이미 설치되어 있습니다.${NC}"
fi

# 3. Docker Compose 설치
echo -e "\n${YELLOW}[3/7] Docker Compose 설치중...${NC}"
if ! command -v docker-compose &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
    echo -e "${GREEN}Docker Compose가 이미 설치되어 있습니다.${NC}"
fi

# 4. Docker Registry 인증서 설정
echo -e "\n${YELLOW}[4/7] Docker Registry 인증서 설정중...${NC}"
mkdir -p /etc/docker/certs.d/${REGISTRY_SERVER}

# CA 인증서가 포함되어 있다면 복사
if [ -f "certs/domain.crt" ]; then
    cp certs/domain.crt /etc/docker/certs.d/${REGISTRY_SERVER}/ca.crt
    echo -e "${GREEN}Registry 인증서가 설정되었습니다.${NC}"
else
    echo -e "${YELLOW}경고: Registry 인증서 파일이 없습니다. 수동으로 설정하세요.${NC}"
    echo -e "${YELLOW}scp root@192.168.0.200:/opt/registry/certs/domain.crt /etc/docker/certs.d/${REGISTRY_SERVER}/ca.crt${NC}"
fi

# 5. Docker 서비스 시작 및 활성화
echo -e "\n${YELLOW}[5/7] Docker 서비스 시작중...${NC}"
systemctl enable docker
systemctl start docker

# 6. NFS 서비스 설정
echo -e "\n${YELLOW}[6/7] NFS 서비스 설정중...${NC}"
systemctl enable nfs-server
systemctl start nfs-server

# NFS export 설정
if ! grep -q "/nfs/shared" /etc/exports; then
    mkdir -p /nfs/shared
    echo "/nfs/shared *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports
    exportfs -ra
    echo -e "${GREEN}NFS export가 설정되었습니다.${NC}"
fi

# 7. 방화벽 설정
echo -e "\n${YELLOW}[7/7] 방화벽 규칙 설정중...${NC}"
if systemctl is-active --quiet firewalld; then
    # 필요한 포트 열기
    firewall-cmd --permanent --add-port=80/tcp      # HAProxy
    firewall-cmd --permanent --add-port=3000/tcp    # Grafana
    firewall-cmd --permanent --add-port=8404/tcp    # HAProxy Stats
    firewall-cmd --permanent --add-port=9090/tcp    # Prometheus
    firewall-cmd --permanent --add-port=9093/tcp    # Alertmanager
    firewall-cmd --permanent --add-port=9000/tcp    # Portainer
    firewall-cmd --permanent --add-port=9100/tcp    # Node Exporter
    firewall-cmd --permanent --add-port=5001/tcp    # Alert Webhook
    firewall-cmd --permanent --add-service=nfs
    firewall-cmd --permanent --add-service=mountd
    firewall-cmd --permanent --add-service=rpc-bind
    firewall-cmd --reload
    echo -e "${GREEN}방화벽 규칙이 설정되었습니다.${NC}"
else
    echo -e "${YELLOW}방화벽이 실행중이지 않습니다.${NC}"
fi

# SELinux 설정
if getenforce | grep -q "Enforcing"; then
    echo -e "${YELLOW}SELinux를 Permissive 모드로 설정중...${NC}"
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
fi

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}   시스템 설정 완료!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "${YELLOW}다음 명령으로 배포를 진행하세요:${NC}"
echo -e "${YELLOW}./load-images.sh${NC}"
echo -e "${YELLOW}./deploy-stack.sh${NC}"