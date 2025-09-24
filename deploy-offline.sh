#!/bin/bash

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}     폐쇄망 모니터링 스택 배포 스크립트     ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

# tar.gz 파일 찾기
TAR_FILE=$(ls monitoring-stack-packed-*.tar.gz 2>/dev/null | head -1)

if [ -z "$TAR_FILE" ]; then
    echo -e "${RED}[ERROR] monitoring-stack-packed-*.tar.gz 파일을 찾을 수 없습니다.${NC}"
    echo -e "${YELLOW}패키징된 이미지 파일을 먼저 복사해주세요.${NC}"
    exit 1
fi

echo -e "${GREEN}[INFO] 패키징된 이미지 파일 발견: $TAR_FILE${NC}"
echo ""

# 1. 압축 해제
echo -e "${YELLOW}1. tar.gz 파일 압축 해제 중...${NC}"
gunzip -k "$TAR_FILE"
TAR_NAME="${TAR_FILE%.gz}"

# 2. Docker 이미지 로드
echo -e "${YELLOW}2. Docker 이미지 로드 중... (시간이 걸릴 수 있습니다)${NC}"
docker load -i "$TAR_NAME"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Docker 이미지 로드 완료${NC}"
else
    echo -e "${RED}[ERROR] Docker 이미지 로드 실패${NC}"
    exit 1
fi

# 3. 로드된 이미지 확인
echo ""
echo -e "${YELLOW}3. 로드된 이미지 목록:${NC}"
docker images | grep packed

# 4. 기존 컨테이너 정리 (옵션)
echo ""
read -p "기존 컨테이너를 정리하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}기존 컨테이너 정리 중...${NC}"
    docker-compose -f docker-compose-offline.yml down
    docker volume prune -f
fi

# 5. 컨테이너 시작
echo ""
echo -e "${YELLOW}5. 모니터링 스택 시작 중...${NC}"
docker-compose -f docker-compose-offline.yml up -d

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 모니터링 스택 시작 완료${NC}"
else
    echo -e "${RED}[ERROR] 모니터링 스택 시작 실패${NC}"
    exit 1
fi

# 6. 컨테이너 상태 확인
echo ""
echo -e "${YELLOW}6. 컨테이너 상태:${NC}"
docker-compose -f docker-compose-offline.yml ps

# 7. 서비스 접속 정보
echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}      서비스 접속 정보      ${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""
echo -e "${GREEN}Grafana:${NC}        http://localhost:3000"
echo -e "                 ID: admin / PW: naver123"
echo ""
echo -e "${GREEN}Prometheus:${NC}     http://localhost:9090"
echo ""
echo -e "${GREEN}Alertmanager:${NC}   http://localhost:9093"
echo ""
echo -e "${GREEN}Portainer:${NC}      http://localhost:9000"
echo -e "                 ID: admin / PW: naver123"
echo ""
echo -e "${GREEN}HAProxy Stats:${NC}  http://localhost:8080/stats"
echo ""
echo -e "${GREEN}Nginx:${NC}          http://localhost:8081"
echo ""
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}✨ 배포 완료!${NC}"
echo ""

# 압축 해제된 tar 파일 삭제 여부 확인
read -p "압축 해제된 tar 파일을 삭제하시겠습니까? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$TAR_NAME"
    echo -e "${GREEN}✓ tar 파일 삭제 완료${NC}"
fi