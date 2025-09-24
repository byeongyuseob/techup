#!/bin/bash

#############################################
# 02-install-docker.sh
# Docker 및 Docker Compose 설치 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Docker & Docker Compose 설치${NC}"
echo -e "${GREEN}========================================${NC}"

# 패키지 매니저 확인
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
else
    PKG_MANAGER="yum"
fi

# 1. 기존 Docker 제거
echo -e "\n${YELLOW}[1/7] 기존 Docker 제거...${NC}"
$PKG_MANAGER remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc 2>/dev/null || true

# 2. Docker 설치
echo -e "\n${YELLOW}[2/7] Docker CE 설치...${NC}"
$PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Docker 서비스 시작
echo -e "\n${YELLOW}[3/7] Docker 서비스 시작...${NC}"
systemctl start docker
systemctl enable docker

# 4. Docker Compose 설치
echo -e "\n${YELLOW}[4/7] Docker Compose 설치...${NC}"
DOCKER_COMPOSE_VERSION="v2.29.7"
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 5. Docker 설정 최적화
echo -e "\n${YELLOW}[5/7] Docker 데몬 설정...${NC}"
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "10"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.17.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Private Registry 사용 시 추가 (필요시 주석 해제)
# cat >> /etc/docker/daemon.json << 'EOF'
# {
#   "insecure-registries": ["192.168.0.100:5000"]
# }
# EOF

# 6. Docker 재시작
echo -e "\n${YELLOW}[6/7] Docker 서비스 재시작...${NC}"
systemctl daemon-reload
systemctl restart docker

# 7. Docker 설치 확인
echo -e "\n${YELLOW}[7/7] Docker 설치 확인...${NC}"
docker version
docker-compose version || docker compose version

# 사용자를 docker 그룹에 추가 (선택사항)
if [ -n "$SUDO_USER" ]; then
    usermod -aG docker $SUDO_USER
    echo -e "${GREEN}사용자 $SUDO_USER를 docker 그룹에 추가했습니다.${NC}"
fi

echo -e "\n${GREEN}✅ Docker 및 Docker Compose 설치 완료!${NC}"
echo -e "${YELLOW}📌 일반 사용자로 Docker를 사용하려면 로그아웃 후 다시 로그인하세요.${NC}"