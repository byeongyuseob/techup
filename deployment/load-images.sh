#!/bin/bash

#############################################
# Docker 이미지 로드 스크립트
# Registry로 push 또는 local load
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Registry 설정
REGISTRY="192.168.0.200:5000"
USE_REGISTRY=${USE_REGISTRY:-false}

echo -e "${GREEN}Docker 이미지 로드 시작...${NC}"

# 압축 해제
if [ -f "docker-images.tar.gz" ]; then
    echo -e "${YELLOW}압축 해제중...${NC}"
    tar xzf docker-images.tar.gz
else
    echo -e "${RED}docker-images.tar.gz 파일이 없습니다!${NC}"
    exit 1
fi

# 이미지 목록 읽기
if [ ! -f "docker-images/images.list" ]; then
    echo -e "${RED}이미지 목록 파일이 없습니다!${NC}"
    exit 1
fi

# 각 이미지 로드
while IFS= read -r IMAGE; do
    FILENAME=$(echo ${IMAGE} | sed 's/:/-/g' | sed 's/\//-/g')
    TAR_FILE="docker-images/${FILENAME}.tar"

    if [ -f "${TAR_FILE}" ]; then
        echo -e "${YELLOW}로드중: ${IMAGE}${NC}"
        docker load -i ${TAR_FILE}

        if [ "$USE_REGISTRY" = "true" ]; then
            # Registry로 push
            echo -e "${YELLOW}Registry로 push중: ${IMAGE}${NC}"
            NEW_TAG="${REGISTRY}/${IMAGE}"
            docker tag ${IMAGE} ${NEW_TAG}
            docker push ${NEW_TAG}
        fi
    else
        echo -e "${RED}파일 없음: ${TAR_FILE}${NC}"
    fi
done < docker-images/images.list

echo -e "${GREEN}이미지 로드 완료!${NC}"

# 로드된 이미지 확인
echo -e "\n${GREEN}로드된 이미지 목록:${NC}"
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"