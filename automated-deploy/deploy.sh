#!/bin/bash

#############################################
# deploy.sh
# 통합 자동 배포 마스터 스크립트
# 깡통 OS에서 실행하면 모든 것이 자동 설정됨
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 배너
print_banner() {
    clear
    echo -e "${MAGENTA}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     ███╗   ███╗ ██████╗ ███╗   ██╗██╗████████╗ ██████╗ ██████╗     ║
║     ████╗ ████║██╔═══██╗████╗  ██║██║╚══██╔══╝██╔═══██╗██╔══██╗    ║
║     ██╔████╔██║██║   ██║██╔██╗ ██║██║   ██║   ██║   ██║██████╔╝    ║
║     ██║╚██╔╝██║██║   ██║██║╚██╗██║██║   ██║   ██║   ██║██╔══██╗    ║
║     ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║██║   ██║   ╚██████╔╝██║  ██║    ║
║     ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝    ║
║                                                                      ║
║                  AUTOMATED DEPLOYMENT SYSTEM v3.0                   ║
║                                                                      ║
║              🚀 Complete Infrastructure in One Command               ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 루트 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ 이 스크립트는 root 권한이 필요합니다.${NC}"
        echo -e "${YELLOW}다음 명령어로 실행하세요: sudo $0${NC}"
        exit 1
    fi
}

# OS 확인
check_os() {
    if [ -f /etc/redhat-release ]; then
        OS_TYPE="rhel"
        OS_VERSION=$(cat /etc/redhat-release)
    elif [ -f /etc/debian_version ]; then
        OS_TYPE="debian"
        OS_VERSION=$(cat /etc/debian_version)
    else
        echo -e "${RED}❌ 지원되지 않는 OS입니다.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ OS 확인: $OS_VERSION${NC}"
}

# 진행 상태 표시
show_progress() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 에러 핸들러
error_handler() {
    echo -e "\n${RED}❌ 오류가 발생했습니다!${NC}"
    echo -e "${RED}오류 위치: 라인 $1${NC}"
    echo -e "${YELLOW}로그 파일: $LOG_FILE${NC}"
    exit 1
}

trap 'error_handler $LINENO' ERR

# 환경 변수 설정
setup_environment() {
    show_progress "환경 변수 설정"

    # 기본 변수
    export WORK_DIR="/opt/monitoring-stack"
    export LOG_DIR="/var/log/monitoring-stack"
    export BACKUP_DIR="/opt/monitoring-stack-backup"

    # Docker Registry 설정 (선택사항)
    echo -e "${YELLOW}Docker Registry를 사용하시겠습니까? (y/n)${NC}"
    read -r USE_REGISTRY

    if [[ "$USE_REGISTRY" == "y" || "$USE_REGISTRY" == "Y" ]]; then
        echo -e "${YELLOW}Docker Registry 주소를 입력하세요:${NC}"
        read -r DOCKER_REGISTRY
        export DOCKER_REGISTRY

        echo -e "${YELLOW}Registry 인증이 필요합니까? (y/n)${NC}"
        read -r NEED_AUTH

        if [[ "$NEED_AUTH" == "y" || "$NEED_AUTH" == "Y" ]]; then
            echo -e "${YELLOW}Username:${NC}"
            read -r REGISTRY_USER
            echo -e "${YELLOW}Password:${NC}"
            read -rs REGISTRY_PASS
            echo
            docker login $DOCKER_REGISTRY -u $REGISTRY_USER -p $REGISTRY_PASS
        fi
    fi

    # NFS 설정 (선택사항)
    echo -e "${YELLOW}NFS를 사용하시겠습니까? (y/n)${NC}"
    read -r USE_NFS

    if [[ "$USE_NFS" == "y" || "$USE_NFS" == "Y" ]]; then
        echo -e "${YELLOW}NFS 서버 IP를 입력하세요:${NC}"
        read -r NFS_SERVER_IP
        echo -e "${YELLOW}NFS Export 경로를 입력하세요:${NC}"
        read -r NFS_EXPORT_PATH

        # .env 파일 업데이트
        sed -i "s/NFS_SERVER_IP=.*/NFS_SERVER_IP=$NFS_SERVER_IP/" $WORK_DIR/.env 2>/dev/null || true
        sed -i "s/NFS_EXPORT_PATH=.*/NFS_EXPORT_PATH=$NFS_EXPORT_PATH/" $WORK_DIR/.env 2>/dev/null || true
    fi

    # 디렉토리 생성
    mkdir -p $WORK_DIR $LOG_DIR $BACKUP_DIR
}

# 메인 실행 함수
main() {
    # 배너 출력
    print_banner

    # 시작 시간
    START_TIME=$(date +%s)

    # 로그 파일 설정
    LOG_FILE="$LOG_DIR/deploy-$(date +%Y%m%d-%H%M%S).log"
    mkdir -p $LOG_DIR
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1

    echo -e "${GREEN}🚀 모니터링 스택 자동 배포를 시작합니다...${NC}\n"

    # 사전 체크
    check_root
    check_os

    # 현재 스크립트 디렉토리로 이동
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd $SCRIPT_DIR

    # 단계별 실행
    show_progress "[1/5] 필수 패키지 설치"
    bash install-packages.sh

    show_progress "[2/5] 시스템 서비스 설정"
    bash setup-services.sh

    show_progress "[3/5] 설정 파일 생성"
    bash create-configs.sh

    # 환경 변수 설정
    setup_environment

    show_progress "[4/5] Docker 이미지 다운로드"
    bash pull-images.sh

    show_progress "[5/5] 서비스 시작"
    cd $WORK_DIR
    docker-compose up -d

    # 서비스 상태 확인
    show_progress "서비스 상태 확인"
    sleep 10
    docker-compose ps

    # 완료 시간 계산
    END_TIME=$(date +%s)
    ELAPSED_TIME=$((END_TIME - START_TIME))
    MINUTES=$((ELAPSED_TIME / 60))
    SECONDS=$((ELAPSED_TIME % 60))

    # 서버 IP 확인
    SERVER_IP=$(hostname -I | awk '{print $1}')

    # 완료 메시지
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 배포가 성공적으로 완료되었습니다! (소요시간: ${MINUTES}분 ${SECONDS}초)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "\n${CYAN}📌 서비스 접속 정보:${NC}"
    echo -e "  ${YELLOW}Main Dashboard${NC}:  http://$SERVER_IP"
    echo -e "  ${YELLOW}Grafana${NC}:         http://$SERVER_IP:3000 (admin/naver123)"
    echo -e "  ${YELLOW}Prometheus${NC}:      http://$SERVER_IP:9090"
    echo -e "  ${YELLOW}Alertmanager${NC}:    http://$SERVER_IP:9093"
    echo -e "  ${YELLOW}Portainer${NC}:       http://$SERVER_IP:9000"
    echo -e "  ${YELLOW}HAProxy Stats${NC}:   http://$SERVER_IP:8404/stats (admin/admin)"

    echo -e "\n${CYAN}📌 유용한 명령어:${NC}"
    echo -e "  ${YELLOW}서비스 상태${NC}:     cd $WORK_DIR && docker-compose ps"
    echo -e "  ${YELLOW}로그 확인${NC}:       cd $WORK_DIR && docker-compose logs -f [서비스명]"
    echo -e "  ${YELLOW}서비스 재시작${NC}:   cd $WORK_DIR && docker-compose restart"
    echo -e "  ${YELLOW}서비스 중지${NC}:     cd $WORK_DIR && docker-compose down"
    echo -e "  ${YELLOW}서비스 시작${NC}:     cd $WORK_DIR && docker-compose up -d"

    echo -e "\n${CYAN}📌 시스템 정보:${NC}"
    echo -e "  ${YELLOW}작업 디렉토리${NC}:   $WORK_DIR"
    echo -e "  ${YELLOW}로그 디렉토리${NC}:   $LOG_DIR"
    echo -e "  ${YELLOW}백업 디렉토리${NC}:   $BACKUP_DIR"
    echo -e "  ${YELLOW}설치 로그${NC}:       $LOG_FILE"

    echo -e "\n${GREEN}🔥 모든 서비스가 정상적으로 실행중입니다!${NC}\n"
}

# 스크립트 실행
main "$@"