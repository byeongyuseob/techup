#!/bin/bash

# ================================================
# 폐쇄망 완전 자동 설치 스크립트
# OS: 현재와 동일한 환경
# NFS: 10.95.137.5
# Password: naver123
# ================================================

set -e

# ===== 설정 값 =====
NFS_SERVER_IP="10.95.137.5"
MYSQL_ROOT_PASSWORD="naver123"
GRAFANA_ADMIN_PASSWORD="naver123"
HAPROXY_ADMIN_USER="admin"
HAPROXY_ADMIN_PASSWORD="naver123"
WORK_DIR="/root/workspace"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}    폐쇄망 완전 자동 설치 시작${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""

# ===== 1. 시스템 기본 설정 =====
echo -e "${YELLOW}[1/15] SELinux 및 방화벽 비활성화${NC}"

# SELinux 비활성화
setenforce 0 2>/dev/null || true
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true

# 방화벽 완전 비활성화
systemctl stop firewalld 2>/dev/null || true
systemctl disable firewalld 2>/dev/null || true
systemctl mask firewalld 2>/dev/null || true

# iptables 초기화
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# ===== 2. 필수 패키지 설치 =====
echo -e "${YELLOW}[2/15] 필수 패키지 설치${NC}"

# EPEL 저장소 추가
yum install -y epel-release

# 필수 패키지 목록
yum install -y \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    wget \
    curl \
    git \
    vim \
    net-tools \
    bind-utils \
    telnet \
    nmap-ncat \
    htop \
    iotop \
    sysstat \
    nfs-utils \
    rpcbind \
    python3 \
    python3-pip \
    gcc \
    make \
    openssl \
    openssl-devel \
    bash-completion \
    tmux \
    screen \
    tree \
    unzip \
    bzip2 \
    rsync \
    chrony \
    jq \
    bc \
    dos2unix \
    lsof \
    tcpdump \
    traceroute \
    mtr \
    socat

# ===== 3. Docker 설치 =====
echo -e "${YELLOW}[3/15] Docker 설치${NC}"

# 기존 Docker 제거
yum remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    podman \
    runc 2>/dev/null || true

# Docker CE 저장소 추가
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# Docker 설치
yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Docker 설정 파일 생성
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    "exec-opts": ["native.cgroupdriver=systemd"],
    "insecure-registries": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"],
    "live-restore": true,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 65536,
            "Soft": 65536
        }
    }
}
EOF

# Docker 서비스 시작 및 자동 시작 설정
systemctl daemon-reload
systemctl enable docker
systemctl start docker

# ===== 4. Docker Compose 설치 =====
echo -e "${YELLOW}[4/15] Docker Compose 설치${NC}"

# Docker Compose 바이너리 설치
COMPOSE_VERSION="v2.23.0"
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# ===== 5. NFS 설정 =====
echo -e "${YELLOW}[5/15] NFS 클라이언트 설정${NC}"

# NFS 관련 서비스 시작
systemctl enable rpcbind
systemctl start rpcbind
systemctl enable nfs-utils
systemctl start nfs-utils

# NFS 마운트 테스트 디렉토리
mkdir -p /mnt/nfs-test

# ===== 6. 시스템 최적화 =====
echo -e "${YELLOW}[6/15] 시스템 커널 파라미터 최적화${NC}"

# sysctl 설정
cat > /etc/sysctl.d/99-docker-tuning.conf << 'EOF'
# Network optimization
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.ip_local_port_range = 10000 65000
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1

# File system
fs.file-max = 2097152
fs.nr_open = 1048576
fs.inotify.max_user_watches = 524288

# Memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
EOF

sysctl -p /etc/sysctl.d/99-docker-tuning.conf

# ulimit 설정
cat > /etc/security/limits.d/99-docker.conf << 'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF

# ===== 7. 작업 디렉토리 생성 =====
echo -e "${YELLOW}[7/15] 작업 디렉토리 생성${NC}"

mkdir -p ${WORK_DIR}
cd ${WORK_DIR}

# ===== 8. 프로젝트 파일 생성 =====
echo -e "${YELLOW}[8/15] 프로젝트 파일 생성${NC}"

# 디렉토리 구조 생성
mkdir -p nginx haproxy mysql web/nfs prometheus alertmanager grafana/provisioning/datasources grafana/provisioning/dashboards grafana/dashboards

# docker-compose.yml 생성
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  haproxy:
    image: haproxy:2.8
    container_name: haproxy
    ports:
      - "80:80"
      - "8404:8404"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - nginx
    networks:
      - webnet
    restart: unless-stopped

  nginx:
    build:
      context: ./nginx
      dockerfile: Dockerfile
    volumes:
      - ./web:/var/www/html
      - type: volume
        source: nfs-shared
        target: /var/www/html/nfs
        volume:
          nocopy: true
    networks:
      webnet:
        aliases:
          - nginx-backend
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: naver123
      MYSQL_DATABASE: testdb
    command: --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci
    volumes:
      - ./mysql/init.sql:/docker-entrypoint-initdb.d/init.sql
      - mysql_data:/var/lib/mysql
    networks:
      - webnet
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=200h'
      - '--web.enable-lifecycle'
    networks:
      - webnet
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks:
      - webnet
    restart: unless-stopped

  alert-webhook:
    image: python:3.9-slim
    container_name: alert-webhook
    ports:
      - "5001:5001"
    volumes:
      - ./alert-webhook.py:/app/alert-webhook.py:ro
    command: bash -c "cd /app && pip install flask && python alert-webhook.py"
    networks:
      - webnet
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=naver123
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/etc/grafana/dashboards:ro
    networks:
      - webnet
    restart: unless-stopped

  nginx-exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: nginx-exporter
    ports:
      - "9113:9113"
    command:
      - '-nginx.scrape-uri=http://nginx-backend/nginx_status'
    depends_on:
      - nginx
    networks:
      - webnet
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    restart: unless-stopped
    networks:
      - webnet

volumes:
  grafana_data:
  mysql_data:
  nfs-shared:
    driver: local
    driver_opts:
      type: nfs
      o: addr=10.95.137.5,rw,nolock,hard,intr
      device: ":/nfs/shared"

networks:
  webnet:
    driver: bridge
EOF

# Nginx Dockerfile
cat > nginx/Dockerfile << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    nginx \
    php8.1-fpm \
    php8.1-mysql \
    php8.1-cli \
    nfs-common \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/nfs

COPY nginx.conf /etc/nginx/sites-available/default
RUN sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/' /etc/php/8.1/fpm/php.ini

COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 80

CMD ["/start.sh"]
EOF

# Nginx 설정
cat > nginx/nginx.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.php index.html index.htm;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location /nginx_status {
        stub_status on;
        access_log off;
        allow all;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Nginx 시작 스크립트
cat > nginx/start.sh << 'EOF'
#!/bin/bash
service php8.1-fpm start
nginx -g "daemon off;"
EOF

chmod +x nginx/start.sh

# HAProxy 설정
cat > haproxy/haproxy.cfg << 'EOF'
global
    log stdout local0
    maxconn 4096
    daemon

defaults
    mode http
    log global
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option forwardfor
    option http-server-close

frontend web_frontend
    bind *:80
    stats enable
    stats uri /haproxy-stats
    stats realm HAProxy\ Statistics
    stats auth admin:naver123
    default_backend nginx_backend

backend nginx_backend
    balance roundrobin
    option httpchk GET /
    server-template nginx- 1-10 nginx-backend:80 check resolvers docker resolve-prefer ipv4

resolvers docker
    nameserver dns1 127.0.0.11:53
    resolve_retries 3
    timeout resolve 1s
    timeout retry 1s
    hold other 10s
    hold refused 10s
    hold nx 10s
    hold timeout 10s
    hold valid 10s
    hold obsolete 10s

listen stats
    bind *:8404
    stats enable
    stats uri /metrics
    stats refresh 10s
EOF

# MySQL 초기화 SQL
cat > mysql/init.sql << 'EOF'
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email) VALUES
('John Smith', 'john.smith@example.com'),
('Alice Johnson', 'alice.johnson@example.com'),
('Bob Wilson', 'bob.wilson@example.com'),
('Sarah Davis', 'sarah.davis@example.com'),
('Michael Brown', 'michael.brown@example.com');
EOF

# PHP 애플리케이션
cat > web/index.php << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Docker Stack Test</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        h1 { color: #333; }
        .info { background: #f0f0f0; padding: 15px; margin: 10px 0; border-radius: 5px; }
        .success { color: green; }
        .error { color: red; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #4CAF50; color: white; }
    </style>
</head>
<body>
    <h1>Docker Stack Status</h1>

    <div class="info">
        <h2>System Information</h2>
        <p>PHP Version: <?php echo phpversion(); ?></p>
        <p>Server: <?php echo gethostname(); ?></p>
        <p>Time: <?php echo date('Y-m-d H:i:s'); ?></p>
    </div>

    <div class="info">
        <?php
        $host = 'mysql';
        $user = 'root';
        $pass = 'naver123';
        $db = 'testdb';

        try {
            $conn = new mysqli($host, $user, $pass, $db);
            if ($conn->connect_error) {
                throw new Exception($conn->connect_error);
            }

            echo '<h2 class="success">MySQL Connection: SUCCESS</h2>';

            $result = $conn->query("SELECT * FROM users");
            if ($result->num_rows > 0) {
                echo '<h3>Test Users:</h3>';
                echo '<table><tr><th>ID</th><th>Name</th><th>Email</th><th>Created</th></tr>';
                while($row = $result->fetch_assoc()) {
                    echo '<tr><td>'.$row["id"].'</td><td>'.$row["name"].'</td><td>'.$row["email"].'</td><td>'.$row["created_at"].'</td></tr>';
                }
                echo '</table>';
            }
            $conn->close();
        } catch (Exception $e) {
            echo '<h2 class="error">MySQL Connection: FAILED</h2>';
            echo '<p>Error: ' . $e->getMessage() . '</p>';
        }
        ?>
    </div>
</body>
</html>
EOF

# hostname.php
cat > web/hostname.php << 'EOF'
<?php
echo "Server Hostname: " . gethostname();
?>
EOF

# Prometheus 설정
cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets:
          - alertmanager:9093

rule_files:
  - "alert.rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:8404']
    scrape_interval: 10s

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']
    scrape_interval: 10s

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
    scrape_interval: 10s
EOF

# Alert Rules
cat > prometheus/alert.rules.yml << 'EOF'
groups:
  - name: system_alerts
    rules:
      - alert: HighCPUUsage
        expr: rate(node_cpu_seconds_total{mode!="idle"}[5m]) * 100 > 80
        for: 5m
        annotations:
          summary: "High CPU usage detected"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 5m
        annotations:
          summary: "High memory usage detected"
EOF

# AlertManager 설정
cat > alertmanager/alertmanager.yml << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'webhook'

receivers:
  - name: 'webhook'
    webhook_configs:
      - url: 'http://alert-webhook:5001/webhook'
        send_resolved: true
EOF

# Alert Webhook
cat > alert-webhook.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, request, jsonify
from datetime import datetime

app = Flask(__name__)

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.json
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] Alert received: {data.get('status')}")
    for alert in data.get('alerts', []):
        print(f"  - {alert.get('labels', {}).get('alertname')}: {alert.get('status')}")
    return jsonify({"status": "success"}), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001)
EOF

# Grafana Datasource
cat > grafana/provisioning/datasources/prometheus.yml << 'EOF'
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

# Grafana Dashboard Provider
cat > grafana/provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    options:
      path: /etc/grafana/dashboards
EOF

# ===== 9. Auto-scaler 스크립트 생성 =====
echo -e "${YELLOW}[9/15] Auto-scaler 스크립트 생성${NC}"

cat > auto-scaler.sh << 'EOF'
#!/bin/bash

MIN_INSTANCES=2
MAX_INSTANCES=10
CPU_THRESHOLD_UP=70
CPU_THRESHOLD_DOWN=30
CHECK_INTERVAL=30

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[Auto-Scaler] 시작${NC}"
echo -e "${GREEN}[Auto-Scaler] 설정: MIN=$MIN_INSTANCES, MAX=$MAX_INSTANCES${NC}"

while true; do
    current_instances=$(docker ps --filter "name=workspace-nginx" --format "{{.Names}}" | wc -l)

    cpu_usage=$(curl -s "http://localhost:9090/api/v1/query?query=avg(rate(container_cpu_usage_seconds_total[1m]))*100" | \
                grep -o '"value":\[[0-9.]*,"[0-9.]*"' | \
                sed 's/.*,"\([0-9.]*\)".*/\1/' | \
                cut -d. -f1)

    cpu_usage=${cpu_usage:-0}

    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 인스턴스=$current_instances, CPU=$cpu_usage%${NC}"

    if [[ $current_instances -lt $MAX_INSTANCES ]] && [[ $cpu_usage -gt $CPU_THRESHOLD_UP ]]; then
        new_instances=$((current_instances + 1))
        echo -e "${RED}[Auto-Scaler] 스케일 업: $current_instances → $new_instances${NC}"
        docker compose up -d --scale nginx=$new_instances --no-recreate
        sleep 10
    elif [[ $current_instances -gt $MIN_INSTANCES ]] && [[ $cpu_usage -lt $CPU_THRESHOLD_DOWN ]]; then
        new_instances=$((current_instances - 1))
        echo -e "${GREEN}[Auto-Scaler] 스케일 다운: $current_instances → $new_instances${NC}"
        docker compose up -d --scale nginx=$new_instances --no-recreate
        sleep 10
    fi

    sleep $CHECK_INTERVAL
done
EOF

chmod +x auto-scaler.sh

# ===== 10. Python 패키지 설치 =====
echo -e "${YELLOW}[10/15] Python 패키지 설치${NC}"

pip3 install flask requests pyyaml aiohttp 2>/dev/null || true

# ===== 11. 시스템 서비스 생성 =====
echo -e "${YELLOW}[11/15] Systemd 서비스 생성${NC}"

# Docker Stack 서비스
cat > /etc/systemd/system/docker-stack.service << EOF
[Unit]
Description=Docker Stack Services
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${WORK_DIR}
ExecStart=/usr/bin/docker compose up -d --scale nginx=2
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0
StandardOutput=journal

[Install]
WantedBy=multi-user.target
EOF

# Auto-scaler 서비스
cat > /etc/systemd/system/auto-scaler.service << EOF
[Unit]
Description=Docker Auto Scaler
After=docker-stack.service
Requires=docker-stack.service

[Service]
Type=simple
WorkingDirectory=${WORK_DIR}
ExecStart=${WORK_DIR}/auto-scaler.sh
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 서비스 활성화
systemctl daemon-reload
systemctl enable docker-stack
systemctl enable auto-scaler

# ===== 12. 헬스체크 스크립트 =====
echo -e "${YELLOW}[12/15] 헬스체크 스크립트 생성${NC}"

cat > /usr/local/bin/docker-health-check.sh << 'EOF'
#!/bin/bash
UNHEALTHY=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep -c "unhealthy\|Exited")
if [ $UNHEALTHY -gt 0 ]; then
    cd /root/workspace
    docker compose up -d --scale nginx=2
    echo "$(date): Restarted unhealthy containers" >> /var/log/docker-health.log
fi
EOF

chmod +x /usr/local/bin/docker-health-check.sh

# Cron 작업 추가
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/docker-health-check.sh") | crontab -

# ===== 13. 로그 로테이션 설정 =====
echo -e "${YELLOW}[13/15] 로그 로테이션 설정${NC}"

cat > /etc/logrotate.d/docker-containers << 'EOF'
/var/lib/docker/containers/*/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    maxsize 100M
}
EOF

# ===== 14. rc.local 설정 (부팅시 자동 시작) =====
echo -e "${YELLOW}[14/15] 부팅시 자동 시작 설정${NC}"

cat > /etc/rc.d/rc.local << 'EOF'
#!/bin/bash
# Docker 컨테이너 자동 시작
sleep 30
cd /root/workspace
/usr/bin/docker compose up -d --scale nginx=2 2>&1 | logger -t docker-stack
nohup /root/workspace/auto-scaler.sh > /var/log/auto-scaler.log 2>&1 &
exit 0
EOF

chmod +x /etc/rc.d/rc.local
systemctl enable rc-local 2>/dev/null || true

# ===== 15. 최종 설정 =====
echo -e "${YELLOW}[15/15] 최종 설정${NC}"

# hosts 파일 설정
echo "${NFS_SERVER_IP} nfs-server" >> /etc/hosts

# 서비스 재시작
systemctl restart docker

# ===== 완료 =====
echo ""
echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}    설치 완료!${NC}"
echo -e "${GREEN}================================================${NC}"
echo ""
echo -e "${YELLOW}서버 IP: $(hostname -I | awk '{print $1}')${NC}"
echo ""
echo "1. 컨테이너 시작:"
echo "   cd ${WORK_DIR}"
echo "   docker compose up -d --scale nginx=2"
echo ""
echo "2. 상태 확인:"
echo "   docker ps"
echo ""
echo "3. 접속 정보:"
echo "   - 웹: http://$(hostname -I | awk '{print $1}')"
echo "   - HAProxy Stats: http://$(hostname -I | awk '{print $1}')/haproxy-stats (admin/naver123)"
echo "   - Grafana: http://$(hostname -I | awk '{print $1}'):3000 (admin/naver123)"
echo "   - Prometheus: http://$(hostname -I | awk '{print $1}'):9090"
echo ""
echo "4. 자동 시작 서비스:"
echo "   systemctl status docker-stack"
echo "   systemctl status auto-scaler"
echo ""
echo -e "${GREEN}재부팅 후에도 자동으로 시작됩니다!${NC}"