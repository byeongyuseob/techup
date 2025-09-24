#!/bin/bash

# YUM/Docker Repository 관리 스크립트
# 192.168.0.200을 로컬 레포지토리 서버로 설정/해제

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_SERVER="192.168.0.200"
YUM_BACKUP_DIR="/root/yum-repos-backup"

show_help() {
    echo -e "${BLUE}Repository Manager - YUM/Docker 로컬 레포 설정${NC}"
    echo ""
    echo "사용법: $0 [up|down|status]"
    echo ""
    echo "명령어:"
    echo "  up     - 로컬 레포지토리 서버(${REPO_SERVER}) 설정"
    echo "  down   - 원본 레포지토리 설정으로 복구"
    echo "  status - 현재 레포지토리 설정 상태 확인"
    echo ""
}

backup_original_repos() {
    echo -e "${YELLOW}기존 레포지토리 설정 백업 중...${NC}"

    # 백업 디렉토리 생성
    mkdir -p "$YUM_BACKUP_DIR"

    # 기존 repo 파일들 백업 (이미 백업이 없는 경우만)
    if [ ! -f "$YUM_BACKUP_DIR/.backup_done" ]; then
        cp -r /etc/yum.repos.d/* "$YUM_BACKUP_DIR/" 2>/dev/null
        touch "$YUM_BACKUP_DIR/.backup_done"
        echo -e "${GREEN}✓ 기존 레포지토리 설정 백업 완료${NC}"
    else
        echo -e "${GREEN}✓ 백업이 이미 존재함${NC}"
    fi
}

setup_local_repos() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}     로컬 레포지토리 설정 (${REPO_SERVER})${NC}"
    echo -e "${BLUE}================================================${NC}"

    backup_original_repos

    # 기존 repo 파일들 비활성화
    echo -e "${YELLOW}기존 레포지토리 파일들 비활성화 중...${NC}"
    find /etc/yum.repos.d/ -name "*.repo" -exec mv {} {}.disabled \; 2>/dev/null

    # 로컬 YUM 레포지토리 설정
    echo -e "${YELLOW}로컬 YUM 레포지토리 설정 중...${NC}"
    cat > /etc/yum.repos.d/local.repo << EOF
[local-baseos]
name=Local BaseOS Repository
baseurl=http://${REPO_SERVER}/centos8/BaseOS/
enabled=1
gpgcheck=0
priority=1

[local-appstream]
name=Local AppStream Repository
baseurl=http://${REPO_SERVER}/centos8/AppStream/
enabled=1
gpgcheck=0
priority=1

[local-extras]
name=Local Extras Repository
baseurl=http://${REPO_SERVER}/centos8/extras/
enabled=1
gpgcheck=0
priority=1

[local-powertools]
name=Local PowerTools Repository
baseurl=http://${REPO_SERVER}/centos8/PowerTools/
enabled=1
gpgcheck=0
priority=1

[local-epel]
name=Local EPEL Repository
baseurl=http://${REPO_SERVER}/epel8/
enabled=1
gpgcheck=0
priority=1
EOF

    # Docker 레포지토리 설정
    echo -e "${YELLOW}로컬 Docker 레포지토리 설정 중...${NC}"
    cat > /etc/yum.repos.d/docker-local.repo << EOF
[docker-local]
name=Local Docker Repository
baseurl=http://${REPO_SERVER}/docker-ce/
enabled=1
gpgcheck=0
priority=1
EOF

    # Docker 데몬 설정 (로컬 registry 사용)
    echo -e "${YELLOW}Docker 데몬 설정 중...${NC}"
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
    "insecure-registries": ["${REPO_SERVER}:5000"],
    "registry-mirrors": ["http://${REPO_SERVER}:5000"],
    "data-root": "/var/lib/docker",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF

    # YUM 캐시 정리 및 업데이트
    echo -e "${YELLOW}YUM 캐시 정리 및 업데이트 중...${NC}"
    yum clean all
    yum makecache

    # Docker 서비스 재시작 (실행 중인 경우)
    if systemctl is-active --quiet docker; then
        echo -e "${YELLOW}Docker 서비스 재시작 중...${NC}"
        systemctl restart docker
    fi

    echo -e "\n${GREEN}✅ 로컬 레포지토리 설정 완료!${NC}"
    echo -e "${GREEN}   YUM Repository: http://${REPO_SERVER}/centos8/${NC}"
    echo -e "${GREEN}   Docker Registry: http://${REPO_SERVER}:5000${NC}"
}

restore_original_repos() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}        원본 레포지토리 설정 복구${NC}"
    echo -e "${BLUE}================================================${NC}"

    if [ ! -d "$YUM_BACKUP_DIR" ] || [ ! -f "$YUM_BACKUP_DIR/.backup_done" ]; then
        echo -e "${RED}✗ 백업된 레포지토리 설정을 찾을 수 없습니다.${NC}"
        return 1
    fi

    # 현재 repo 파일들 제거
    echo -e "${YELLOW}로컬 레포지토리 설정 제거 중...${NC}"
    rm -f /etc/yum.repos.d/local.repo
    rm -f /etc/yum.repos.d/docker-local.repo

    # 비활성화된 파일들 복구
    echo -e "${YELLOW}기존 레포지토리 파일들 복구 중...${NC}"
    find /etc/yum.repos.d/ -name "*.repo.disabled" -exec sh -c 'mv "$1" "${1%.disabled}"' _ {} \;

    # Docker 데몬 설정 복구
    echo -e "${YELLOW}Docker 데몬 설정 복구 중...${NC}"
    if [ -f /etc/docker/daemon.json ]; then
        cat > /etc/docker/daemon.json << EOF
{
    "data-root": "/var/lib/docker",
    "storage-driver": "overlay2",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF
    fi

    # YUM 캐시 정리 및 업데이트
    echo -e "${YELLOW}YUM 캐시 정리 및 업데이트 중...${NC}"
    yum clean all
    yum makecache

    # Docker 서비스 재시작 (실행 중인 경우)
    if systemctl is-active --quiet docker; then
        echo -e "${YELLOW}Docker 서비스 재시작 중...${NC}"
        systemctl restart docker
    fi

    echo -e "\n${GREEN}✅ 원본 레포지토리 설정 복구 완료!${NC}"
}

check_status() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}          현재 레포지토리 상태${NC}"
    echo -e "${BLUE}================================================${NC}"

    # YUM 레포지토리 상태
    echo -e "\n${YELLOW}YUM 레포지토리:${NC}"
    if [ -f /etc/yum.repos.d/local.repo ]; then
        echo -e "${GREEN}✓ 로컬 레포지토리 설정됨 (${REPO_SERVER})${NC}"
        echo "  활성 레포지토리:"
        yum repolist enabled | grep -E "local-|repo id"
    else
        echo -e "${YELLOW}○ 기본 레포지토리 사용 중${NC}"
        echo "  활성 레포지토리 수: $(yum repolist enabled | grep -c "^[^r]")"
    fi

    # Docker 레포지토리 상태
    echo -e "\n${YELLOW}Docker 설정:${NC}"
    if [ -f /etc/docker/daemon.json ] && grep -q "${REPO_SERVER}" /etc/docker/daemon.json 2>/dev/null; then
        echo -e "${GREEN}✓ 로컬 Docker 레지스트리 설정됨 (${REPO_SERVER}:5000)${NC}"
    else
        echo -e "${YELLOW}○ 기본 Docker 설정 사용 중${NC}"
    fi

    # 연결 테스트
    echo -e "\n${YELLOW}연결 테스트:${NC}"
    if curl -s --connect-timeout 3 "http://${REPO_SERVER}" >/dev/null; then
        echo -e "${GREEN}✓ 레포지토리 서버(${REPO_SERVER}) 연결 가능${NC}"
    else
        echo -e "${RED}✗ 레포지토리 서버(${REPO_SERVER}) 연결 불가${NC}"
    fi

    # 백업 상태
    echo -e "\n${YELLOW}백업 상태:${NC}"
    if [ -f "$YUM_BACKUP_DIR/.backup_done" ]; then
        echo -e "${GREEN}✓ 원본 설정 백업 존재${NC}"
        echo "  백업 위치: $YUM_BACKUP_DIR"
    else
        echo -e "${YELLOW}○ 백업 없음${NC}"
    fi
}

test_repos() {
    echo -e "\n${YELLOW}레포지토리 테스트 중...${NC}"

    echo -e "YUM 테스트:"
    if yum list available | head -5; then
        echo -e "${GREEN}✓ YUM 레포지토리 정상${NC}"
    else
        echo -e "${RED}✗ YUM 레포지토리 오류${NC}"
    fi

    if systemctl is-active --quiet docker; then
        echo -e "\nDocker 테스트:"
        if docker info >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Docker 정상${NC}"
        else
            echo -e "${RED}✗ Docker 오류${NC}"
        fi
    fi
}

# 메인 로직
case "$1" in
    up)
        setup_local_repos
        test_repos
        ;;
    down)
        restore_original_repos
        test_repos
        ;;
    status)
        check_status
        ;;
    test)
        test_repos
        ;;
    *)
        show_help
        exit 1
        ;;
esac

exit 0