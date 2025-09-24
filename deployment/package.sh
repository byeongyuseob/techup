#!/bin/bash

#############################################
# 전체 패키징 스크립트
# 배포에 필요한 모든 파일 준비
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}   배포 패키지 생성 시작${NC}"
echo -e "${BLUE}======================================${NC}"

# 임시 패키지 디렉토리
PACKAGE_DIR="monitoring-stack-package"
rm -rf ${PACKAGE_DIR}
mkdir -p ${PACKAGE_DIR}

# 1. 스크립트 복사
echo -e "\n${YELLOW}[1/6] 설치 스크립트 복사중...${NC}"
cp install.sh ${PACKAGE_DIR}/
cp setup-system.sh ${PACKAGE_DIR}/
cp load-images.sh ${PACKAGE_DIR}/
cp deploy-stack.sh ${PACKAGE_DIR}/
cp save-images.sh ${PACKAGE_DIR}/
chmod +x ${PACKAGE_DIR}/*.sh

# 2. 모니터링 스택 파일 복사
echo -e "\n${YELLOW}[2/6] 모니터링 스택 파일 준비중...${NC}"
mkdir -p ${PACKAGE_DIR}/monitoring-stack

# 필요한 파일들 복사
cp /root/workspace/docker-compose.yml ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/nginx ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/haproxy ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/prometheus ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/grafana ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/alertmanager ${PACKAGE_DIR}/monitoring-stack/
cp -r /root/workspace/scripts ${PACKAGE_DIR}/monitoring-stack/
cp /root/workspace/docker-stats-exporter.py ${PACKAGE_DIR}/monitoring-stack/
cp /root/workspace/multi-exporter.py ${PACKAGE_DIR}/monitoring-stack/
cp /root/workspace/alert-webhook.py ${PACKAGE_DIR}/monitoring-stack/

# 3. Docker 이미지 저장
echo -e "\n${YELLOW}[3/6] Docker 이미지 저장중...${NC}"
cd ${PACKAGE_DIR}
bash save-images.sh
cd ..

# 4. README 생성
echo -e "\n${YELLOW}[4/6] README 문서 생성중...${NC}"
cat > ${PACKAGE_DIR}/README.md << 'EOF'
# 모니터링 스택 배포 패키지

## 개요
완전한 컨테이너 기반 모니터링 시스템 배포 패키지

## 포함 컴포넌트
- HAProxy (로드밸런서)
- Nginx (웹서버)
- MySQL (데이터베이스)
- Prometheus (메트릭 수집)
- Grafana (시각화)
- Alertmanager (알림)
- Portainer (컨테이너 관리)
- 각종 Exporter

## 설치 방법

### 1. 빠른 시작 (폐쇄망)
```bash
chmod +x install.sh
sudo ./install.sh
# 옵션 1 선택 (폐쇄망 설치)
```

### 2. 온라인 설치
```bash
chmod +x install.sh
sudo ./install.sh
# 옵션 2 선택 (온라인 설치)
```

### 3. 수동 설치
```bash
# 시스템 설정
sudo ./setup-system.sh

# 이미지 로드 (폐쇄망)
sudo ./load-images.sh

# 스택 배포
sudo ./deploy-stack.sh
```

## 접속 정보
- HAProxy: http://SERVER_IP
- Grafana: http://SERVER_IP:3000 (admin/naver123)
- Prometheus: http://SERVER_IP:9090
- Alertmanager: http://SERVER_IP:9093
- Portainer: http://SERVER_IP:9000

## 환경 변수
`.env` 파일에서 수정 가능:
- NFS_SERVER_IP: NFS 서버 주소
- MYSQL_ROOT_PASSWORD: MySQL 비밀번호
- GF_SECURITY_ADMIN_PASSWORD: Grafana 관리자 비밀번호

## 문제 해결

### NFS 마운트 실패
```bash
systemctl status nfs-server
systemctl start nfs-server
```

### Docker 서비스 확인
```bash
systemctl status docker
docker-compose ps
```

## 파일 구조
```
monitoring-stack-package/
├── install.sh              # 통합 설치 스크립트
├── setup-system.sh         # 시스템 설정
├── load-images.sh          # 이미지 로드
├── deploy-stack.sh         # 스택 배포
├── docker-images.tar.gz    # Docker 이미지
└── monitoring-stack/       # 설정 파일들
```
EOF

# 5. 버전 정보 파일
echo -e "\n${YELLOW}[5/6] 버전 정보 생성중...${NC}"
cat > ${PACKAGE_DIR}/VERSION << EOF
Version: 3.0
Build Date: $(date +%Y-%m-%d)
Components:
  - HAProxy 2.8
  - Nginx 1.18
  - MySQL 8.0
  - Prometheus latest
  - Grafana latest
  - Alertmanager latest
  - Portainer CE latest
EOF

# 6. 전체 압축
echo -e "\n${YELLOW}[6/6] 최종 패키지 생성중...${NC}"
PACKAGE_NAME="monitoring-stack-v3.0-$(date +%Y%m%d).tar.gz"
tar czf ${PACKAGE_NAME} ${PACKAGE_DIR}/

# 크기 확인
PACKAGE_SIZE=$(du -h ${PACKAGE_NAME} | cut -f1)

echo -e "\n${GREEN}======================================${NC}"
echo -e "${GREEN}   패키지 생성 완료!${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}파일명: ${PACKAGE_NAME}${NC}"
echo -e "${GREEN}크기: ${PACKAGE_SIZE}${NC}"
echo -e "\n${YELLOW}배포 방법:${NC}"
echo -e "1. 대상 서버로 파일 전송: ${YELLOW}scp ${PACKAGE_NAME} root@target-server:/tmp/${NC}"
echo -e "2. 압축 해제: ${YELLOW}tar xzf ${PACKAGE_NAME}${NC}"
echo -e "3. 설치 실행: ${YELLOW}cd monitoring-stack-package && sudo ./install.sh${NC}"