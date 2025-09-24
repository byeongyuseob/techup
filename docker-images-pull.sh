#!/bin/bash

# ================================================
# Docker 이미지 사전 다운로드 스크립트
# 폐쇄망 환경을 위한 이미지 준비
# ================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Docker 이미지 사전 다운로드${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# 필요한 Docker 이미지 목록
IMAGES=(
    # 기본 이미지
    "ubuntu:22.04"
    "mysql:8.0"
    "haproxy:2.8"
    "python:3.9-slim"

    # 모니터링 스택
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "prom/alertmanager:latest"
    "prom/node-exporter:latest"
    "nginx/nginx-prometheus-exporter:latest"
)

# 이미지 다운로드
echo -e "${YELLOW}이미지 다운로드 시작...${NC}"
for image in "${IMAGES[@]}"; do
    echo -e "${GREEN}[다운로드] $image${NC}"
    docker pull $image || echo -e "${RED}[실패] $image${NC}"
done

# Nginx 커스텀 이미지 빌드
echo -e "${YELLOW}Nginx 커스텀 이미지 빌드...${NC}"
if [ -f nginx/Dockerfile ]; then
    docker build -t workspace-nginx nginx/
else
    echo -e "${RED}nginx/Dockerfile 없음. 나중에 빌드 필요${NC}"
fi

echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   이미지 다운로드 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# 다운로드된 이미지 확인
echo -e "${YELLOW}다운로드된 이미지 목록:${NC}"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"

echo ""
echo -e "${YELLOW}총 이미지 크기:${NC}"
docker system df -v | grep "Images" | head -1

echo ""
echo -e "${GREEN}[TIP] 폐쇄망으로 이미지 이동 방법:${NC}"
echo "1. 이미지 저장:"
echo "   docker save -o docker-images.tar ${IMAGES[@]}"
echo ""
echo "2. 파일 이동 (USB 등으로)"
echo ""
echo "3. 폐쇄망에서 로드:"
echo "   docker load -i docker-images.tar"