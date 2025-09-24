#!/bin/bash

# ================================================
# 깡통 서버 초기 설정 스크립트
# ================================================

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    서버 초기 설정 시작${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. 시스템 업데이트
echo -e "${YELLOW}[1/7] 시스템 업데이트...${NC}"
if command -v apt-get &> /dev/null; then
    apt-get update && apt-get upgrade -y
    apt-get install -y curl wget git vim net-tools
elif command -v yum &> /dev/null; then
    yum update -y
    yum install -y curl wget git vim net-tools
fi

# 2. Docker 설치
echo -e "${YELLOW}[2/7] Docker 설치...${NC}"
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
    rm get-docker.sh
else
    echo -e "${GREEN}Docker 이미 설치됨${NC}"
fi

# 3. Docker Compose 설치
echo -e "${YELLOW}[3/7] Docker Compose 설치...${NC}"
if ! command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_VERSION="v2.23.0"
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
else
    echo -e "${GREEN}Docker Compose 이미 설치됨${NC}"
fi

# 4. NFS 클라이언트 설치
echo -e "${YELLOW}[4/7] NFS 클라이언트 설치...${NC}"
if command -v apt-get &> /dev/null; then
    apt-get install -y nfs-common
elif command -v yum &> /dev/null; then
    yum install -y nfs-utils
fi

# 5. 방화벽 설정
echo -e "${YELLOW}[5/7] 방화벽 포트 개방...${NC}"
if command -v ufw &> /dev/null; then
    ufw allow 80/tcp
    ufw allow 8404/tcp
    ufw allow 3000/tcp
    ufw allow 9090/tcp
    ufw allow 9093/tcp
    ufw allow 9100/tcp
    ufw allow 9113/tcp
    ufw allow 5001/tcp
    echo -e "${GREEN}UFW 방화벽 설정 완료${NC}"
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --add-port=80/tcp
    firewall-cmd --permanent --add-port=8404/tcp
    firewall-cmd --permanent --add-port=3000/tcp
    firewall-cmd --permanent --add-port=9090/tcp
    firewall-cmd --permanent --add-port=9093/tcp
    firewall-cmd --permanent --add-port=9100/tcp
    firewall-cmd --permanent --add-port=9113/tcp
    firewall-cmd --permanent --add-port=5001/tcp
    firewall-cmd --reload
    echo -e "${GREEN}Firewalld 방화벽 설정 완료${NC}"
fi

# 6. 작업 디렉토리 생성
echo -e "${YELLOW}[6/7] 작업 디렉토리 생성...${NC}"
mkdir -p /root/workspace
cd /root/workspace

# 7. Git 저장소 클론
echo -e "${YELLOW}[7/7] 프로젝트 파일 다운로드...${NC}"
if [ ! -d ".git" ]; then
    git clone https://github.com/byeongyuseob/techup.git .
else
    git pull
fi

# 완료
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    초기 설정 완료!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}다음 단계:${NC}"
echo "1. NFS 서버 IP 수정 (필요시):"
echo "   vi docker-compose.yml"
echo ""
echo "2. 서비스 시작:"
echo "   docker compose up -d --scale nginx=2"
echo ""
echo "3. 오토스케일러 시작:"
echo "   ./auto-scaler.sh &"
echo ""
echo "4. 접속 확인:"
echo "   - 웹: http://$(hostname -I | awk '{print $1}')"
echo "   - Grafana: http://$(hostname -I | awk '{print $1}'):3000"
echo "   - Prometheus: http://$(hostname -I | awk '{print $1}'):9090"