#!/bin/bash

#############################################
# 04-prepare-files.sh
# 프로젝트 파일 압축 및 준비 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  프로젝트 파일 압축 스크립트${NC}"
echo -e "${GREEN}========================================${NC}"

# 현재 디렉토리 확인
WORKSPACE="/root/workspace"
if [ ! -d "$WORKSPACE" ]; then
    echo -e "${RED}작업 디렉토리가 없습니다: $WORKSPACE${NC}"
    exit 1
fi

cd $WORKSPACE

# 압축 파일명
ARCHIVE_NAME="monitoring-stack-$(date +%Y%m%d).tar.gz"
DEPLOY_DIR="monitoring-stack"

echo -e "\n${YELLOW}[1/3] 배포용 디렉토리 준비...${NC}"

# 임시 배포 디렉토리 생성
rm -rf /tmp/$DEPLOY_DIR
mkdir -p /tmp/$DEPLOY_DIR

# 필요한 파일들 복사
echo -e "${YELLOW}[2/3] 필요 파일 복사...${NC}"

# 디렉토리 구조 생성
directories=(
    "nginx"
    "haproxy"
    "mysql"
    "prometheus"
    "alertmanager"
    "grafana/dashboards"
    "grafana/provisioning"
    "web"
    "scripts"
)

for dir in "${directories[@]}"; do
    if [ -d "$WORKSPACE/$dir" ]; then
        echo -e "  📁 $dir"
        mkdir -p /tmp/$DEPLOY_DIR/$dir
        cp -r $WORKSPACE/$dir/* /tmp/$DEPLOY_DIR/$dir/ 2>/dev/null || true
    fi
done

# 개별 파일 복사
files=(
    "docker-compose.yml"
    ".env"
    "docker-stats-exporter.py"
    "multi-exporter.py"
    "nfs-monitor.py"
    "alert-webhook.py"
    "update-nfs-ip.sh"
    "ports.conf"
)

for file in "${files[@]}"; do
    if [ -f "$WORKSPACE/$file" ]; then
        echo -e "  📄 $file"
        cp $WORKSPACE/$file /tmp/$DEPLOY_DIR/
    fi
done

# 배포 스크립트 복사
cp -r $WORKSPACE/deploy-scripts /tmp/$DEPLOY_DIR/

# README 작성
cat > /tmp/$DEPLOY_DIR/README.md << 'EOF'
# 모니터링 스택 배포 가이드

## 시스템 요구사항
- OS: RHEL/CentOS/Rocky Linux 7/8/9
- CPU: 최소 2 Core
- RAM: 최소 4GB (권장 8GB)
- Disk: 최소 20GB

## 설치 순서
1. `deploy.sh` 실행으로 자동 설치
   ```bash
   chmod +x deploy.sh
   sudo ./deploy.sh
   ```

또는 수동 설치:
1. Repository 설정: `./deploy-scripts/01-setup-repo.sh`
2. Docker 설치: `./deploy-scripts/02-install-docker.sh`
3. 이미지 Pull: `./deploy-scripts/03-pull-images.sh`
4. 프로젝트 배포: `./deploy-scripts/05-deploy-stack.sh`

## 환경 설정
`.env` 파일에서 필요한 설정 변경:
- NFS_SERVER_IP: NFS 서버 IP 주소
- MYSQL_ROOT_PASSWORD: MySQL 비밀번호
- GF_SECURITY_ADMIN_PASSWORD: Grafana 관리자 비밀번호

## 서비스 접속
- HAProxy: http://서버IP
- Grafana: http://서버IP:3000 (admin/naver123)
- Prometheus: http://서버IP:9090
- Alertmanager: http://서버IP:9093
- Portainer: http://서버IP:9000

## 유용한 명령어
```bash
# 서비스 시작
docker compose up -d

# 서비스 중지
docker compose down

# 로그 확인
docker compose logs -f [서비스명]

# 상태 확인
docker compose ps
```
EOF

# 압축
echo -e "\n${YELLOW}[3/3] 파일 압축...${NC}"
cd /tmp
tar czf $WORKSPACE/$ARCHIVE_NAME $DEPLOY_DIR

# 정리
rm -rf /tmp/$DEPLOY_DIR

# 결과
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  압축 완료${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${BLUE}📦 압축 파일: $WORKSPACE/$ARCHIVE_NAME${NC}"
echo -e "${BLUE}📊 파일 크기: $(du -h $WORKSPACE/$ARCHIVE_NAME | cut -f1)${NC}"
echo -e "\n${GREEN}✅ 배포 파일 준비 완료!${NC}"