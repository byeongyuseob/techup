#!/bin/bash

#############################################
# 모니터링 스택 배포 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 설정
DEPLOY_DIR="/opt/monitoring-stack"
REGISTRY="${USE_REGISTRY:-}"

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   모니터링 스택 배포 시작${NC}"
echo -e "${BLUE}======================================${NC}"

# 1. 배포 디렉토리 생성
echo -e "\n${YELLOW}[1/5] 배포 디렉토리 준비중...${NC}"
mkdir -p ${DEPLOY_DIR}

# 2. 필요 파일 복사
echo -e "\n${YELLOW}[2/5] 파일 복사중...${NC}"
cp -r monitoring-stack/* ${DEPLOY_DIR}/
cd ${DEPLOY_DIR}

# 3. Registry 사용 시 docker-compose.yml 수정
if [ ! -z "${REGISTRY}" ]; then
    echo -e "\n${YELLOW}[3/5] Registry 설정 적용중...${NC}"
    # Registry 주소를 이미지 앞에 추가
    sed -i "s|image: \(.*\)|image: ${REGISTRY}/\1|g" docker-compose.yml
    # workspace-nginx는 별도 처리
    sed -i "s|${REGISTRY}/workspace-nginx|workspace-nginx|g" docker-compose.yml
fi

# 4. 환경 변수 설정
echo -e "\n${YELLOW}[4/5] 환경 변수 설정중...${NC}"
cat > .env << EOF
# NFS Configuration
NFS_SERVER_IP=10.95.137.10
NFS_EXPORT_PATH=/nfs/shared

# MySQL Configuration
MYSQL_ROOT_PASSWORD=naver123
MYSQL_DATABASE=testdb

# Grafana Configuration
GF_SECURITY_ADMIN_PASSWORD=naver123
EOF

# 5. Docker Compose 실행
echo -e "\n${YELLOW}[5/5] 서비스 시작중...${NC}"
docker-compose up -d

# 서비스 시작 대기
echo -e "${YELLOW}서비스 시작 대기중...${NC}"
sleep 15

# 상태 확인
echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}   배포 상태 확인${NC}"
echo -e "${GREEN}======================================${NC}"

docker-compose ps

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}   서비스 접속 정보${NC}"
echo -e "${GREEN}======================================${NC}"

SERVER_IP=$(hostname -I | awk '{print $1}')
echo -e "${YELLOW}HAProxy:${NC}        http://${SERVER_IP}"
echo -e "${YELLOW}Grafana:${NC}        http://${SERVER_IP}:3000 (admin/naver123)"
echo -e "${YELLOW}Prometheus:${NC}     http://${SERVER_IP}:9090"
echo -e "${YELLOW}Alertmanager:${NC}   http://${SERVER_IP}:9093"
echo -e "${YELLOW}Portainer:${NC}      http://${SERVER_IP}:9000"
echo -e "${YELLOW}HAProxy Stats:${NC}  http://${SERVER_IP}:8404/stats"

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}   유용한 명령어${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "서비스 상태:  ${YELLOW}cd ${DEPLOY_DIR} && docker-compose ps${NC}"
echo -e "로그 확인:    ${YELLOW}cd ${DEPLOY_DIR} && docker-compose logs -f [서비스명]${NC}"
echo -e "재시작:       ${YELLOW}cd ${DEPLOY_DIR} && docker-compose restart${NC}"
echo -e "중지:         ${YELLOW}cd ${DEPLOY_DIR} && docker-compose down${NC}"

echo -e "\n${GREEN}✅ 배포가 완료되었습니다!${NC}"