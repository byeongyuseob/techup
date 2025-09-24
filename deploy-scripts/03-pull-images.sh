#!/bin/bash

#############################################
# 03-pull-images.sh
# 필요한 Docker 이미지 Pull 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Docker 이미지 Pull 스크립트${NC}"
echo -e "${GREEN}========================================${NC}"

# Registry 설정 (필요시 변경)
REGISTRY=""  # 예: "192.168.0.100:5000/"

# 필요한 이미지 목록
declare -a IMAGES=(
    "haproxy:2.8"
    "mysql:8.0"
    "grafana/grafana:latest"
    "prom/prometheus:latest"
    "prom/alertmanager:latest"
    "prom/node-exporter:latest"
    "nginx/nginx-prometheus-exporter:latest"
    "portainer/portainer-ce:latest"
    "python:3.9-alpine"
    "python:3.9-slim"
)

# Private Registry 사용 시 로그인
if [ -n "$REGISTRY" ]; then
    echo -e "\n${YELLOW}Private Registry 로그인...${NC}"
    echo -e "${BLUE}Registry: ${REGISTRY}${NC}"
    read -p "Username: " REGISTRY_USER
    read -s -p "Password: " REGISTRY_PASS
    echo ""
    echo "$REGISTRY_PASS" | docker login ${REGISTRY} -u "$REGISTRY_USER" --password-stdin
fi

# 이미지 Pull
echo -e "\n${YELLOW}Docker 이미지 다운로드 시작...${NC}"
TOTAL=${#IMAGES[@]}
CURRENT=0

for IMAGE in "${IMAGES[@]}"; do
    CURRENT=$((CURRENT + 1))
    echo -e "\n${BLUE}[$CURRENT/$TOTAL] Pulling ${REGISTRY}${IMAGE}...${NC}"

    if [ -n "$REGISTRY" ]; then
        # Private Registry에서 Pull
        docker pull ${REGISTRY}${IMAGE}
        # 태그 변경 (Registry prefix 제거)
        docker tag ${REGISTRY}${IMAGE} ${IMAGE}
    else
        # Docker Hub에서 Pull
        docker pull ${IMAGE}
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ${IMAGE} 다운로드 완료${NC}"
    else
        echo -e "${RED}❌ ${IMAGE} 다운로드 실패${NC}"
        FAILED_IMAGES+=("$IMAGE")
    fi
done

# nginx 이미지는 별도 빌드 필요
echo -e "\n${YELLOW}Nginx 커스텀 이미지 빌드 필요${NC}"
echo -e "${BLUE}📌 nginx 이미지는 프로젝트 파일 배포 후 빌드됩니다.${NC}"

# 결과 출력
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  이미지 다운로드 완료${NC}"
echo -e "${GREEN}========================================${NC}"

docker images | grep -E "haproxy|mysql|grafana|prometheus|alertmanager|node-exporter|nginx-prometheus|portainer|python"

if [ ${#FAILED_IMAGES[@]} -gt 0 ]; then
    echo -e "\n${RED}실패한 이미지:${NC}"
    for img in "${FAILED_IMAGES[@]}"; do
        echo -e "${RED}  - $img${NC}"
    done
    exit 1
fi

echo -e "\n${GREEN}✅ 모든 이미지 다운로드 완료!${NC}"