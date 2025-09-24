#!/bin/bash

#############################################
# 05-deploy-stack.sh
# Docker Compose 스택 배포 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  모니터링 스택 배포${NC}"
echo -e "${GREEN}========================================${NC}"

# 작업 디렉토리 설정
DEPLOY_DIR="/opt/monitoring-stack"

# 1. 디렉토리 준비
echo -e "\n${YELLOW}[1/8] 배포 디렉토리 준비...${NC}"
mkdir -p $DEPLOY_DIR
cd $DEPLOY_DIR

# 2. 환경 변수 설정
echo -e "\n${YELLOW}[2/8] 환경 변수 설정...${NC}"
if [ ! -f ".env" ]; then
    echo -e "${RED}.env 파일이 없습니다. 생성합니다...${NC}"
    cat > .env << 'EOF'
# Docker Compose 환경 설정
# NFS 서버 설정
NFS_SERVER_IP=192.168.0.240
NFS_EXPORT_PATH=/nfs/shared

# MySQL 설정
MYSQL_ROOT_PASSWORD=naver123
MYSQL_DATABASE=testdb

# Grafana 설정
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=naver123
EOF
fi

# 3. 네트워크 설정
echo -e "\n${YELLOW}[3/8] 방화벽 설정...${NC}"
# Firewalld 사용 여부 확인
if systemctl is-active firewalld >/dev/null 2>&1; then
    echo "방화벽 포트 열기..."
    firewall-cmd --permanent --add-port=80/tcp     # HAProxy
    firewall-cmd --permanent --add-port=3000/tcp   # Grafana
    firewall-cmd --permanent --add-port=9090/tcp   # Prometheus
    firewall-cmd --permanent --add-port=9093/tcp   # Alertmanager
    firewall-cmd --permanent --add-port=9000/tcp   # Portainer
    firewall-cmd --permanent --add-port=8404/tcp   # HAProxy Stats
    firewall-cmd --reload
    echo -e "${GREEN}✅ 방화벽 설정 완료${NC}"
else
    echo -e "${YELLOW}방화벽이 비활성화되어 있습니다.${NC}"
fi

# 4. SELinux 설정
echo -e "\n${YELLOW}[4/8] SELinux 설정...${NC}"
if command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce)
    if [ "$SELINUX_STATUS" != "Disabled" ]; then
        echo "SELinux를 Permissive 모드로 설정..."
        setenforce 0
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    fi
fi

# 5. Nginx 이미지 빌드
echo -e "\n${YELLOW}[5/8] Nginx 커스텀 이미지 빌드...${NC}"
if [ -d "nginx" ]; then
    docker build -t workspace-nginx:latest ./nginx/
    echo -e "${GREEN}✅ Nginx 이미지 빌드 완료${NC}"
fi

# 6. 볼륨 디렉토리 생성
echo -e "\n${YELLOW}[6/8] 볼륨 디렉토리 생성...${NC}"
mkdir -p web
echo "<?php phpinfo(); ?>" > web/index.php

# 7. Docker Compose 실행
echo -e "\n${YELLOW}[7/8] Docker Compose 시작...${NC}"
docker compose down 2>/dev/null || true
docker compose up -d

# 8. 서비스 상태 확인
echo -e "\n${YELLOW}[8/8] 서비스 상태 확인...${NC}"
sleep 10

docker compose ps

# 헬스체크
echo -e "\n${YELLOW}서비스 헬스체크...${NC}"

check_service() {
    local service=$1
    local port=$2
    local url=$3

    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$port$url | grep -q "200\|301\|302"; then
        echo -e "${GREEN}✅ $service (포트 $port) - 정상${NC}"
    else
        echo -e "${RED}❌ $service (포트 $port) - 응답 없음${NC}"
    fi
}

check_service "HAProxy" 80 "/"
check_service "Grafana" 3000 "/api/health"
check_service "Prometheus" 9090 "/-/healthy"
check_service "Alertmanager" 9093 "/-/healthy"
check_service "Portainer" 9000 "/"

# 완료 메시지
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  배포 완료!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${BLUE}📌 서비스 접속 정보:${NC}"
echo -e "  HAProxy:      http://$(hostname -I | awk '{print $1}')"
echo -e "  Grafana:      http://$(hostname -I | awk '{print $1}'):3000"
echo -e "  Prometheus:   http://$(hostname -I | awk '{print $1}'):9090"
echo -e "  Alertmanager: http://$(hostname -I | awk '{print $1}'):9093"
echo -e "  Portainer:    http://$(hostname -I | awk '{print $1}'):9000"

echo -e "\n${BLUE}📌 기본 로그인 정보:${NC}"
echo -e "  Grafana: admin / naver123"
echo -e "  MySQL:   root / naver123"

echo -e "\n${YELLOW}📌 로그 확인:${NC}"
echo -e "  docker compose logs -f [서비스명]"

echo -e "\n${GREEN}✅ 모든 서비스가 시작되었습니다!${NC}"