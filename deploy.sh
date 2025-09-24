#!/bin/bash

#############################################
# deploy.sh
# 통합 자동 배포 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 로고 출력
print_logo() {
    echo -e "${MAGENTA}"
    cat << "EOF"
    __  ___            _ __            _
   /  |/  /___  ____  (_) /_____  ____(_)____  ____ _
  / /|_/ / __ \/ __ \/ / __/ __ \/ ___/ / __ \/ __ `/
 / /  / / /_/ / / / / / /_/ /_/ / /  / / / / / /_/ /
/_/  /_/\____/_/ /_/_/\__/\____/_/  /_/_/ /_/\__, /
                                             /____/
         ____  __             __
        / ___// /_____ ______/ /__
        \__ \/ __/ __ `/ ___/ //_/
       ___/ / /_/ /_/ / /__/ ,<
      /____/\__/\__,_/\___/_/|_|

      🚀 Automated Deployment System v2.0
EOF
    echo -e "${NC}"
}

# 루트 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}이 스크립트는 root 권한이 필요합니다.${NC}"
        echo -e "${YELLOW}sudo $0 명령으로 실행해주세요.${NC}"
        exit 1
    fi
}

# OS 확인
check_os() {
    if [ ! -f /etc/redhat-release ]; then
        echo -e "${RED}이 스크립트는 RedHat 계열 리눅스에서만 작동합니다.${NC}"
        exit 1
    fi
    OS_VERSION=$(cat /etc/redhat-release)
    echo -e "${GREEN}✅ OS 확인: $OS_VERSION${NC}"
}

# 진행 상태 표시
progress() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 에러 핸들러
error_handler() {
    echo -e "\n${RED}❌ 오류가 발생했습니다!${NC}"
    echo -e "${RED}오류 위치: 라인 $1${NC}"
    echo -e "${YELLOW}로그를 확인하세요: /tmp/deploy.log${NC}"
    exit 1
}

trap 'error_handler $LINENO' ERR

# 메인 배포 함수
main() {
    print_logo

    echo -e "${GREEN}모니터링 스택 자동 배포를 시작합니다...${NC}\n"

    # 사전 체크
    check_root
    check_os

    # 로그 파일 준비
    LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"
    exec 1> >(tee -a "$LOG_FILE")
    exec 2>&1

    # 배포 옵션 선택
    echo -e "${YELLOW}배포 옵션을 선택하세요:${NC}"
    echo "1) 전체 자동 설치 (권장)"
    echo "2) Docker만 설치"
    echo "3) 프로젝트만 배포 (Docker 설치됨)"
    echo "4) 이미지만 다운로드"
    read -p "선택 [1-4]: " OPTION

    case $OPTION in
        1)
            # 전체 설치
            progress "STEP 1/5: YUM Repository 설정"
            if [ -f "deploy-scripts/01-setup-repo.sh" ]; then
                bash deploy-scripts/01-setup-repo.sh
            else
                echo -e "${RED}01-setup-repo.sh 파일을 찾을 수 없습니다.${NC}"
                exit 1
            fi

            progress "STEP 2/5: Docker 및 Docker Compose 설치"
            bash deploy-scripts/02-install-docker.sh

            progress "STEP 3/5: Docker 이미지 다운로드"
            bash deploy-scripts/03-pull-images.sh

            progress "STEP 4/5: 프로젝트 파일 배포"
            # 현재 디렉토리를 /opt/monitoring-stack으로 복사
            if [ ! -d "/opt/monitoring-stack" ]; then
                cp -r . /opt/monitoring-stack/
            fi

            progress "STEP 5/5: 서비스 시작"
            cd /opt/monitoring-stack
            bash deploy-scripts/05-deploy-stack.sh
            ;;

        2)
            # Docker만 설치
            progress "Docker 및 Docker Compose 설치"
            bash deploy-scripts/01-setup-repo.sh
            bash deploy-scripts/02-install-docker.sh
            ;;

        3)
            # 프로젝트만 배포
            progress "프로젝트 배포"
            if [ ! -d "/opt/monitoring-stack" ]; then
                cp -r . /opt/monitoring-stack/
            fi
            cd /opt/monitoring-stack
            bash deploy-scripts/05-deploy-stack.sh
            ;;

        4)
            # 이미지만 다운로드
            progress "Docker 이미지 다운로드"
            bash deploy-scripts/03-pull-images.sh
            ;;

        *)
            echo -e "${RED}잘못된 선택입니다.${NC}"
            exit 1
            ;;
    esac

    # 완료 메시지
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 배포가 성공적으로 완료되었습니다!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$OPTION" == "1" ] || [ "$OPTION" == "3" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo -e "\n${BLUE}📌 서비스 접속 정보:${NC}"
        echo -e "  ${YELLOW}HAProxy${NC}:      http://$SERVER_IP"
        echo -e "  ${YELLOW}Grafana${NC}:      http://$SERVER_IP:3000 (admin/naver123)"
        echo -e "  ${YELLOW}Prometheus${NC}:   http://$SERVER_IP:9090"
        echo -e "  ${YELLOW}Alertmanager${NC}: http://$SERVER_IP:9093"
        echo -e "  ${YELLOW}Portainer${NC}:    http://$SERVER_IP:9000"

        echo -e "\n${BLUE}📌 유용한 명령어:${NC}"
        echo -e "  서비스 상태: ${YELLOW}docker compose ps${NC}"
        echo -e "  로그 확인:   ${YELLOW}docker compose logs -f [서비스명]${NC}"
        echo -e "  재시작:     ${YELLOW}docker compose restart${NC}"
    fi

    echo -e "\n${GREEN}로그 파일: $LOG_FILE${NC}"
}

# 스크립트 실행
main "$@"