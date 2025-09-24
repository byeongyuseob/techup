#!/bin/bash

#############################################
# 통합 설치 스크립트
# 깡통 OS에서 전체 시스템 구축
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
         _____ __             __
        / ___// /_____ ______/ /__
        \__ \/ __/ __ `/ ___/ //_/
       ___/ / /_/ /_/ / /__/ ,<
      /____/\__/\__,_/\___/_/|_|

      Complete Monitoring Stack Deployment v3.0
      Offline Installation Package
EOF
    echo -e "${NC}"
}

# 진행 상태 표시
progress() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 루트 권한 체크
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}이 스크립트는 root 권한이 필요합니다.${NC}"
        echo -e "${YELLOW}sudo $0 명령으로 실행해주세요.${NC}"
        exit 1
    fi
}

# 메인 함수
main() {
    print_logo
    check_root

    echo -e "${GREEN}통합 모니터링 스택 설치를 시작합니다...${NC}\n"

    # 설치 옵션 선택
    echo -e "${YELLOW}설치 방법을 선택하세요:${NC}"
    echo "1) 폐쇄망 설치 (오프라인)"
    echo "2) 온라인 설치"
    echo "3) Registry 사용 설치"
    read -p "선택 [1-3]: " INSTALL_MODE

    case $INSTALL_MODE in
        1)
            # 폐쇄망 설치
            progress "STEP 1/4: 시스템 설정"
            ./setup-system.sh

            progress "STEP 2/4: Docker 이미지 로드"
            USE_REGISTRY=false ./load-images.sh

            progress "STEP 3/4: 모니터링 스택 배포"
            ./deploy-stack.sh

            progress "STEP 4/4: 상태 확인"
            sleep 10
            cd /opt/monitoring-stack
            docker-compose ps
            ;;

        2)
            # 온라인 설치
            progress "STEP 1/3: 시스템 설정"
            ./setup-system.sh

            progress "STEP 2/3: 모니터링 스택 배포"
            ./deploy-stack.sh

            progress "STEP 3/3: 상태 확인"
            sleep 10
            cd /opt/monitoring-stack
            docker-compose ps
            ;;

        3)
            # Registry 사용 설치
            echo -e "${YELLOW}Registry 서버 주소를 입력하세요:${NC}"
            read -p "Registry (예: 192.168.0.200:5000): " REGISTRY_SERVER

            progress "STEP 1/4: 시스템 설정"
            ./setup-system.sh

            progress "STEP 2/4: Docker 이미지 로드 및 Registry Push"
            USE_REGISTRY=true ./load-images.sh

            progress "STEP 3/4: 모니터링 스택 배포"
            USE_REGISTRY=${REGISTRY_SERVER} ./deploy-stack.sh

            progress "STEP 4/4: 상태 확인"
            sleep 10
            cd /opt/monitoring-stack
            docker-compose ps
            ;;

        *)
            echo -e "${RED}잘못된 선택입니다.${NC}"
            exit 1
            ;;
    esac

    # 완료 메시지
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎉 설치가 성공적으로 완료되었습니다!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "\n${BLUE}📌 서비스 접속 정보:${NC}"
    echo -e "  ${YELLOW}HAProxy${NC}:      http://$SERVER_IP"
    echo -e "  ${YELLOW}Grafana${NC}:      http://$SERVER_IP:3000 (admin/naver123)"
    echo -e "  ${YELLOW}Prometheus${NC}:   http://$SERVER_IP:9090"
    echo -e "  ${YELLOW}Alertmanager${NC}: http://$SERVER_IP:9093"
    echo -e "  ${YELLOW}Portainer${NC}:    http://$SERVER_IP:9000"

    echo -e "\n${GREEN}로그 파일: /var/log/monitoring-stack-install.log${NC}"
}

# 로그 설정
LOG_FILE="/var/log/monitoring-stack-install-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# 스크립트 실행
main "$@"