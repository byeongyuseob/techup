#!/bin/bash

#############################################
# install-packages.sh
# 필수 패키지 설치 스크립트
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[1/5] 필수 패키지 설치 시작${NC}"

# SELinux 비활성화
echo -e "${YELLOW}SELinux 설정...${NC}"
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true

# 방화벽 설정
echo -e "${YELLOW}방화벽 설정...${NC}"
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true

# 기본 패키지 업데이트 및 설치
echo -e "${YELLOW}기본 패키지 설치...${NC}"
yum install -y epel-release
yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    git \
    curl \
    wget \
    vim \
    net-tools \
    nfs-utils \
    python3 \
    python3-pip \
    gcc \
    make \
    openssl \
    openssl-devel

# Docker CE Repository 설정
echo -e "${YELLOW}Docker Repository 설정...${NC}"
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Docker 설치
echo -e "${YELLOW}Docker 및 Docker Compose 설치...${NC}"
yum install -y docker-ce docker-ce-cli containerd.io

# Docker Compose 설치 (최신 버전)
DOCKER_COMPOSE_VERSION="2.23.0"
curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Python 패키지 설치
echo -e "${YELLOW}Python 패키지 설치...${NC}"
pip3 install --upgrade pip
pip3 install docker flask requests pyyaml

echo -e "${GREEN}✅ 패키지 설치 완료${NC}"