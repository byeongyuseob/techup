# 🚀 깡통 서버 배포 가이드

## 1. 사전 준비사항

### 필수 확인사항
- [ ] 서버 OS 설치 완료 (Ubuntu 22.04 LTS 권장)
- [ ] root 권한 또는 sudo 권한
- [ ] 인터넷 연결 가능
- [ ] 최소 8GB RAM, 4 CPU 코어
- [ ] 50GB 이상 여유 공간

## 2. 빠른 설치 (One-Line)

```bash
curl -fsSL https://raw.githubusercontent.com/byeongyuseob/techup/master/install.sh | bash
```

## 3. 수동 설치 단계

### Step 1: 시스템 패키지 업데이트
```bash
# Ubuntu/Debian
apt-get update && apt-get upgrade -y
apt-get install -y curl wget git vim net-tools

# CentOS/RHEL
yum update -y
yum install -y curl wget git vim net-tools
```

### Step 2: Docker 설치
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker
```

### Step 3: Docker Compose 설치
```bash
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

### Step 4: 프로젝트 클론
```bash
cd /root
git clone https://github.com/byeongyuseob/techup.git workspace
cd workspace
```

### Step 5: NFS 설정 (선택사항)

#### 옵션 A: 외부 NFS 서버 사용
```bash
# docker-compose.yml 수정
vi docker-compose.yml

# nfs-shared 볼륨 설정 부분 수정:
volumes:
  nfs-shared:
    driver: local
    driver_opts:
      type: nfs
      o: addr=YOUR_NFS_SERVER_IP,rw,nolock,hard,intr
      device: ":/nfs/shared"
```

#### 옵션 B: 로컬 NFS 서버 구축
```bash
# NFS 서버 설치
apt-get install -y nfs-kernel-server

# Export 디렉토리 생성
mkdir -p /srv/nfs/shared
chmod 777 /srv/nfs/shared

# Export 설정
echo "/srv/nfs/shared *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports

# NFS 서비스 시작
systemctl restart nfs-kernel-server
systemctl enable nfs-kernel-server

# docker-compose.yml에서 IP를 localhost로 변경
```

#### 옵션 C: NFS 없이 로컬 볼륨 사용
```bash
# docker-compose.yml 수정
volumes:
  nfs-shared:
    driver: local
    # driver_opts 섹션 전체 주석 처리
```

### Step 6: 방화벽 설정

#### Ubuntu (UFW)
```bash
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 8404/tcp  # HAProxy Stats
ufw allow 3000/tcp  # Grafana
ufw allow 9090/tcp  # Prometheus
ufw allow 9093/tcp  # AlertManager
ufw --force enable
```

#### CentOS/RHEL (firewalld)
```bash
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=8404/tcp
firewall-cmd --permanent --add-port=3000/tcp
firewall-cmd --permanent --add-port=9090/tcp
firewall-cmd --permanent --add-port=9093/tcp
firewall-cmd --reload
```

## 4. 서비스 시작

### 컨테이너 시작
```bash
# 모든 서비스 시작 (Nginx 2개 인스턴스)
docker compose up -d --scale nginx=2

# 상태 확인
docker ps

# 로그 확인
docker compose logs -f
```

### 오토스케일러 시작
```bash
# 백그라운드에서 실행
nohup ./auto-scaler.sh > auto-scaler.log 2>&1 &

# 또는 systemd 서비스로 등록
cat > /etc/systemd/system/auto-scaler.service << EOF
[Unit]
Description=Docker Auto Scaler
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/root/workspace/auto-scaler.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable auto-scaler
systemctl start auto-scaler
```

## 5. 환경별 커스터마이징

### MySQL 비밀번호 변경
```yaml
# docker-compose.yml
environment:
  MYSQL_ROOT_PASSWORD: your_secure_password
```

### HAProxy 관리자 비밀번호 변경
```bash
# 새 비밀번호 생성
echo -n "newpassword" | mkpasswd --method=md5 --stdin

# haproxy/haproxy.cfg 수정
stats auth admin:$생성된_해시값
```

### Grafana 관리자 비밀번호 변경
```yaml
# docker-compose.yml
environment:
  - GF_SECURITY_ADMIN_PASSWORD=your_admin_password
```

### 도메인 설정
```bash
# Nginx 설정에 도메인 추가
vi nginx/nginx.conf

server_name your-domain.com www.your-domain.com;
```

## 6. 문제 해결

### Docker 권한 오류
```bash
usermod -aG docker $USER
newgrp docker
```

### 컨테이너 재시작
```bash
docker compose restart

# 특정 서비스만
docker compose restart nginx
```

### 전체 초기화
```bash
docker compose down -v
docker system prune -af
docker compose up -d --scale nginx=2
```

### 포트 충돌
```bash
# 사용중인 포트 확인
netstat -tulpn | grep :80
lsof -i :80

# 프로세스 종료
kill -9 $(lsof -t -i:80)
```

## 7. 모니터링 및 관리

### 접속 URL
- 웹 서비스: `http://서버IP/`
- HAProxy Stats: `http://서버IP/haproxy-stats` (admin/admin123)
- Grafana: `http://서버IP:3000` (admin/admin)
- Prometheus: `http://서버IP:9090`
- AlertManager: `http://서버IP:9093`

### 로그 확인
```bash
# 전체 로그
docker compose logs

# 특정 서비스 로그
docker compose logs nginx
docker compose logs haproxy

# 실시간 로그
docker compose logs -f --tail 100
```

### 백업
```bash
# 데이터 백업
tar czf backup_$(date +%Y%m%d).tar.gz \
  docker-compose.yml \
  nginx/ \
  haproxy/ \
  mysql/ \
  prometheus/ \
  grafana/ \
  web/

# MySQL 백업
docker exec mysql mysqldump -uroot -pnaver123 testdb > backup_db_$(date +%Y%m%d).sql
```

## 8. 성능 튜닝

### 시스템 파라미터
```bash
# /etc/sysctl.conf
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# 적용
sysctl -p
```

### Docker 리소스 제한
```yaml
# docker-compose.yml
services:
  nginx:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```

## 9. 보안 강화

### SSL/TLS 설정
```bash
# Let's Encrypt 인증서 발급
apt-get install -y certbot
certbot certonly --standalone -d your-domain.com

# HAProxy에 SSL 설정 추가
# haproxy/haproxy.cfg
bind *:443 ssl crt /etc/letsencrypt/live/your-domain.com/fullchain.pem
```

### 보안 헤더 추가
```nginx
# nginx/nginx.conf
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
```

## 10. 체크리스트

배포 전:
- [ ] 서버 스펙 확인
- [ ] 네트워크 설정 확인
- [ ] 방화벽 규칙 설정
- [ ] NFS 서버 준비 (선택)
- [ ] 도메인 DNS 설정 (선택)

배포 후:
- [ ] 모든 컨테이너 실행 확인
- [ ] 웹 서비스 접속 테스트
- [ ] 로드 밸런싱 동작 확인
- [ ] 모니터링 대시보드 확인
- [ ] 오토스케일링 테스트
- [ ] 백업 정책 수립

---

문제 발생시: https://github.com/byeongyuseob/techup/issues