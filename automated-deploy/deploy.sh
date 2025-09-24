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

# IP 자동 감지
get_server_ip() {
    # 여러 방법으로 IP 감지 시도
    SERVER_IP=""

    # 방법 1: hostname 명령
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')

    # 방법 2: ip 명령
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[^ ]+')
    fi

    # 방법 3: ifconfig 명령
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
    fi

    echo "$SERVER_IP"
}

# 환경 변수 설정
setup_environment() {
    show_progress "환경 설정 구성"

    # 기본 변수
    export WORK_DIR="/opt/monitoring-stack"
    export LOG_DIR="/var/log/monitoring-stack"
    export BACKUP_DIR="/opt/monitoring-stack-backup"

    # 서버 IP 자동 감지
    SERVER_IP=$(get_server_ip)

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}       🔧 환경 설정 구성${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}감지된 서버 IP: ${YELLOW}$SERVER_IP${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # 배포 모드 선택
    echo -e "${YELLOW}배포 모드를 선택하세요:${NC}"
    echo -e "  1) ${GREEN}빠른 설치${NC} (기본값 사용)"
    echo -e "  2) ${BLUE}사용자 정의 설치${NC} (세부 설정)"
    echo -e "  3) ${MAGENTA}폐쇄망 설치${NC} (인터넷 없음)"
    echo -n "선택 [1-3] (기본값: 1): "
    read -r -t 10 DEPLOY_MODE || DEPLOY_MODE="1"
    echo

    case "$DEPLOY_MODE" in
        1)
            echo -e "${GREEN}✅ 빠른 설치 모드 - 기본값 사용${NC}"
            # 기본값 설정
            MYSQL_ROOT_PASSWORD="admin123"
            GRAFANA_ADMIN_USER="admin"
            GRAFANA_ADMIN_PASSWORD="admin123"
            USE_NFS="n"
            USE_REGISTRY="n"
            ;;

        2)
            echo -e "${BLUE}🔧 사용자 정의 설치 모드${NC}\n"

            # MySQL 설정
            echo -n "MySQL root 비밀번호 (기본값: admin123): "
            read -r MYSQL_ROOT_PASSWORD
            MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-admin123}

            # Grafana 설정
            echo -n "Grafana 관리자 계정 (기본값: admin): "
            read -r GRAFANA_ADMIN_USER
            GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}

            echo -n "Grafana 관리자 비밀번호 (기본값: admin123): "
            read -r GRAFANA_ADMIN_PASSWORD
            GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin123}

            # NFS 설정
            echo -n "NFS를 사용하시겠습니까? [y/N]: "
            read -r USE_NFS
            USE_NFS=${USE_NFS:-n}

            if [[ "$USE_NFS" == "y" || "$USE_NFS" == "Y" ]]; then
                echo -n "NFS 서버 IP: "
                read -r NFS_SERVER_IP
                echo -n "NFS Export 경로 (기본값: /nfs/shared): "
                read -r NFS_EXPORT_PATH
                NFS_EXPORT_PATH=${NFS_EXPORT_PATH:-/nfs/shared}
            fi
            ;;

        3)
            echo -e "${MAGENTA}🔒 폐쇄망 설치 모드${NC}\n"

            # 기본값 설정
            MYSQL_ROOT_PASSWORD="admin123"
            GRAFANA_ADMIN_USER="admin"
            GRAFANA_ADMIN_PASSWORD="admin123"

            # Docker Registry 설정
            echo -n "Docker Registry 주소: "
            read -r DOCKER_REGISTRY

            echo -n "Registry 인증이 필요합니까? [y/N]: "
            read -r NEED_AUTH

            if [[ "$NEED_AUTH" == "y" || "$NEED_AUTH" == "Y" ]]; then
                echo -n "Registry 사용자명: "
                read -r REGISTRY_USER
                echo -n "Registry 비밀번호: "
                read -rs REGISTRY_PASS
                echo
            fi

            export DOCKER_REGISTRY
            USE_REGISTRY="y"
            USE_NFS="n"
            ;;

        *)
            echo -e "${YELLOW}기본값 사용 (빠른 설치)${NC}"
            MYSQL_ROOT_PASSWORD="admin123"
            GRAFANA_ADMIN_USER="admin"
            GRAFANA_ADMIN_PASSWORD="admin123"
            USE_NFS="n"
            USE_REGISTRY="n"
            ;;
    esac

    # 디렉토리 생성
    mkdir -p $WORK_DIR $LOG_DIR $BACKUP_DIR

    # .env 파일 생성/업데이트
    cat > $WORK_DIR/.env << EOF
# 자동 생성된 환경 설정
# 생성 시간: $(date)

# 서버 설정
SERVER_IP=$SERVER_IP

# MySQL 설정
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_DATABASE=monitoring

# Grafana 설정
GF_SECURITY_ADMIN_USER=$GRAFANA_ADMIN_USER
GF_SECURITY_ADMIN_PASSWORD=$GRAFANA_ADMIN_PASSWORD

# NFS 설정 (선택사항)
USE_NFS=$USE_NFS
NFS_SERVER_IP=${NFS_SERVER_IP:-}
NFS_EXPORT_PATH=${NFS_EXPORT_PATH:-}

# Docker Registry (선택사항)
USE_REGISTRY=$USE_REGISTRY
DOCKER_REGISTRY=${DOCKER_REGISTRY:-}
EOF

    echo -e "${GREEN}✅ 환경 설정 완료${NC}\n"
}

# 설정 요약 표시
show_configuration_summary() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}                     📋 설정 요약${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${YELLOW}서버 IP${NC}:           $SERVER_IP"
    echo -e "  ${YELLOW}작업 디렉토리${NC}:     $WORK_DIR"
    echo -e "  ${YELLOW}MySQL Password${NC}:   $MYSQL_ROOT_PASSWORD"
    echo -e "  ${YELLOW}Grafana 계정${NC}:     $GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_PASSWORD"

    if [[ "$USE_NFS" == "y" ]]; then
        echo -e "  ${YELLOW}NFS 서버${NC}:         $NFS_SERVER_IP:$NFS_EXPORT_PATH"
    fi

    if [[ "$USE_REGISTRY" == "y" ]]; then
        echo -e "  ${YELLOW}Docker Registry${NC}:  $DOCKER_REGISTRY"
    fi

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    echo -n "이 설정으로 계속하시겠습니까? [Y/n]: "
    read -r CONFIRM
    if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
        echo -e "${YELLOW}설치가 취소되었습니다.${NC}"
        exit 0
    fi
}

# 메인 실행 함수
main() {
    # 배너 출력
    print_banner

    # 시작 시간
    START_TIME=$(date +%s)

    # 로그 파일 설정
    LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1

    echo -e "${GREEN}🚀 모니터링 스택 자동 배포를 시작합니다...${NC}\n"

    # 사전 체크
    check_root
    check_os

    # 현재 스크립트 디렉토리로 이동
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd $SCRIPT_DIR

    # 환경 설정
    setup_environment

    # 설정 요약 및 확인
    show_configuration_summary

    # Registry 로그인 처리
    if [[ "$USE_REGISTRY" == "y" ]] && [[ ! -z "$REGISTRY_USER" ]]; then
        show_progress "Docker Registry 로그인"
        docker login $DOCKER_REGISTRY -u $REGISTRY_USER -p $REGISTRY_PASS
    fi

    # 단계별 실행
    show_progress "[1/5] 필수 패키지 설치"
    bash install-packages.sh

    show_progress "[2/5] 시스템 서비스 설정"
    bash setup-services.sh

    show_progress "[3/5] 설정 파일 생성"
    # .env 파일을 create-configs.sh에 전달
    cp $WORK_DIR/.env ./
    bash create-configs.sh

    show_progress "[4/5] Docker 이미지 다운로드"
    if [[ "$USE_REGISTRY" == "y" ]]; then
        DOCKER_REGISTRY=$DOCKER_REGISTRY bash pull-images.sh
    else
        bash pull-images.sh
    fi

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

    # 완료 메시지
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 배포가 성공적으로 완료되었습니다! (소요시간: ${MINUTES}분 ${SECONDS}초)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    echo -e "\n${CYAN}📌 서비스 접속 정보:${NC}"
    echo -e "  ${YELLOW}Main Dashboard${NC}:  http://$SERVER_IP"
    echo -e "  ${YELLOW}Grafana${NC}:         http://$SERVER_IP:3000 ($GRAFANA_ADMIN_USER/$GRAFANA_ADMIN_PASSWORD)"
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

    echo -e "\n${CYAN}📌 접속 정보 다시 보기:${NC}"
    echo -e "  ${YELLOW}cat $WORK_DIR/.env${NC}"

    echo -e "\n${GREEN}🔥 모든 서비스가 정상적으로 실행중입니다!${NC}\n"

    # 접속 정보를 파일로 저장
    cat > $WORK_DIR/access-info.txt << EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
       모니터링 스택 접속 정보
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
생성 시간: $(date)
서버 IP: $SERVER_IP

서비스 URL:
- Main Dashboard:  http://$SERVER_IP
- Grafana:         http://$SERVER_IP:3000
  계정: $GRAFANA_ADMIN_USER / $GRAFANA_ADMIN_PASSWORD
- Prometheus:      http://$SERVER_IP:9090
- Alertmanager:    http://$SERVER_IP:9093
- Portainer:       http://$SERVER_IP:9000
- HAProxy Stats:   http://$SERVER_IP:8404/stats
  계정: admin / admin

MySQL:
- Host: $SERVER_IP
- Port: 3306
- Root Password: $MYSQL_ROOT_PASSWORD
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

    echo -e "${YELLOW}접속 정보가 $WORK_DIR/access-info.txt 에 저장되었습니다.${NC}"
}

# 스크립트 실행
main "$@"