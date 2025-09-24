#!/bin/bash

#############################################
# Docker 이미지 저장 스크립트
# 폐쇄망 배포를 위한 이미지 export
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Docker 이미지 저장 시작...${NC}"

# 저장 디렉토리 생성
SAVE_DIR="docker-images"
mkdir -p ${SAVE_DIR}

# nginx 이미지 빌드
echo -e "${YELLOW}nginx 이미지 빌드중...${NC}"
cd /root/workspace
docker compose build nginx --no-cache
cd -

# 이미지 목록
IMAGES=(
    "grafana/grafana:latest"
    "haproxy:2.8"
    "mysql:8.0"
    "nginx/nginx-prometheus-exporter:latest"
    "portainer/portainer-ce:latest"
    "prom/alertmanager:latest"
    "prom/node-exporter:latest"
    "prom/prometheus:latest"
    "python:3.9-alpine"
    "python:3.9-slim"
    "workspace-nginx:latest"
)

# 각 이미지 저장
for IMAGE in "${IMAGES[@]}"; do
    FILENAME=$(echo ${IMAGE} | sed 's/:/-/g' | sed 's/\//-/g')
    echo -e "${YELLOW}저장중: ${IMAGE} -> ${FILENAME}.tar${NC}"
    docker save ${IMAGE} -o ${SAVE_DIR}/${FILENAME}.tar
done

# 이미지 목록 파일 생성
echo "${IMAGES[@]}" | tr ' ' '\n' > ${SAVE_DIR}/images.list

# tar.gz로 압축
echo -e "${YELLOW}압축중...${NC}"
tar czf docker-images.tar.gz ${SAVE_DIR}/

echo -e "${GREEN}완료! docker-images.tar.gz 파일이 생성되었습니다.${NC}"
echo -e "${GREEN}파일 크기: $(du -h docker-images.tar.gz | cut -f1)${NC}"