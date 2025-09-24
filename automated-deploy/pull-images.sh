#!/bin/bash

#############################################
# pull-images.sh
# Docker 이미지 다운로드 스크립트
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[4/5] Docker 이미지 다운로드 시작${NC}"

# 필요한 이미지 목록
IMAGES=(
    "haproxy:2.8"
    "nginx:alpine"
    "mysql:8.0"
    "prom/prometheus:latest"
    "prom/alertmanager:latest"
    "grafana/grafana:latest"
    "prom/node-exporter:latest"
    "gcr.io/cadvisor/cadvisor:latest"
    "portainer/portainer-ce:latest"
    "python:3.9-slim"
    "python:3.9-alpine"
)

# Docker Registry 설정 (선택사항)
if [ ! -z "$DOCKER_REGISTRY" ]; then
    echo -e "${YELLOW}Docker Registry 사용: $DOCKER_REGISTRY${NC}"
    docker login $DOCKER_REGISTRY
fi

# 이미지 다운로드
total=${#IMAGES[@]}
current=0

for image in "${IMAGES[@]}"; do
    current=$((current + 1))
    echo -e "${YELLOW}[$current/$total] Pulling $image...${NC}"

    if [ ! -z "$DOCKER_REGISTRY" ]; then
        # 사설 레지스트리에서 pull
        registry_image="$DOCKER_REGISTRY/$image"
        docker pull $registry_image
        docker tag $registry_image $image
        docker rmi $registry_image
    else
        # Docker Hub에서 직접 pull
        docker pull $image
    fi
done

echo -e "${GREEN}✅ 모든 이미지 다운로드 완료${NC}"

# 다운로드된 이미지 확인
echo -e "${YELLOW}다운로드된 이미지 목록:${NC}"
docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep -E "(haproxy|nginx|mysql|prometheus|alertmanager|grafana|node-exporter|cadvisor|portainer|python)"