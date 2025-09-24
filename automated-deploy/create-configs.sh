#!/bin/bash

#############################################
# create-configs.sh
# 모든 설정 파일 생성 스크립트
#############################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}[3/5] 설정 파일 생성 시작${NC}"

# 작업 디렉토리 설정
WORK_DIR="/opt/monitoring-stack"
mkdir -p $WORK_DIR
cd $WORK_DIR

# 디렉토리 구조 생성
echo -e "${YELLOW}디렉토리 구조 생성...${NC}"
mkdir -p \
    prometheus \
    alertmanager \
    grafana/{provisioning/{datasources,dashboards},dashboards} \
    haproxy \
    nginx \
    mysql \
    web \
    scripts

# .env 파일 생성
echo -e "${YELLOW}.env 파일 생성...${NC}"
cat > .env << 'EOF'
# Docker Compose 환경 설정
NFS_SERVER_IP=10.95.137.10
NFS_EXPORT_PATH=/nfs/shared
MYSQL_ROOT_PASSWORD=naver123
MYSQL_DATABASE=testdb
GF_SECURITY_ADMIN_USER=admin
GF_SECURITY_ADMIN_PASSWORD=naver123
EOF

# Docker Compose 파일 생성
echo -e "${YELLOW}docker-compose.yml 생성...${NC}"
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
    image: nginx:alpine
    container_name: nginx
    volumes:
      - ./web:/usr/share/nginx/html
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      webnet:
        aliases:
          - nginx-backend
    restart: unless-stopped

  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
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
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'
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
      - alertmanager_data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    networks:
      - webnet
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GF_SECURITY_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
      - GF_INSTALL_PLUGINS=
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    networks:
      - webnet
    depends_on:
      - prometheus
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
    networks:
      - webnet
    restart: unless-stopped

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    privileged: true
    devices:
      - /dev/kmsg
    networks:
      - webnet
    restart: unless-stopped

  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    ports:
      - "9000:9000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - portainer_data:/data
    networks:
      - webnet
    restart: unless-stopped

volumes:
  mysql_data:
  prometheus_data:
  grafana_data:
  alertmanager_data:
  portainer_data:

networks:
  webnet:
    driver: bridge
EOF

# Prometheus 설정
echo -e "${YELLOW}Prometheus 설정 생성...${NC}"
cat > prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - "alert.rules.yml"

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'mysql'
    static_configs:
      - targets: ['mysql:3306']

  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:8404']
EOF

# Alert Rules
cat > prometheus/alert.rules.yml << 'EOF'
groups:
  - name: system_alerts
    rules:
      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage is above 80% (current value: {{ $value }}%)"

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is above 80% (current value: {{ $value }}%)"

      - alert: DiskSpaceRunningOut
        expr: (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 20
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk space running out on {{ $labels.instance }}"
          description: "Disk space available is less than 20% (current value: {{ $value }}%)"

      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.job }} is down"
          description: "{{ $labels.instance }} of job {{ $labels.job }} has been down for more than 1 minute"
EOF

# Alertmanager 설정
echo -e "${YELLOW}Alertmanager 설정 생성...${NC}"
cat > alertmanager/alertmanager.yml << 'EOF'
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://host.docker.internal:5001/webhook'
        send_resolved: true
EOF

# HAProxy 설정
echo -e "${YELLOW}HAProxy 설정 생성...${NC}"
cat > haproxy/haproxy.cfg << 'EOF'
global
    log stdout local0
    maxconn 4096

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend web_frontend
    bind *:80
    stats enable
    stats uri /haproxy-stats
    stats refresh 10s
    default_backend web_backend

backend web_backend
    balance roundrobin
    option httpchk GET /
    server nginx1 nginx:80 check

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-node
    stats auth admin:admin
EOF

# Nginx 설정
echo -e "${YELLOW}Nginx 설정 생성...${NC}"
cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    server {
        listen 80;
        server_name localhost;

        root /usr/share/nginx/html;
        index index.html index.htm;

        location / {
            try_files $uri $uri/ =404;
        }

        location /nginx_status {
            stub_status on;
            access_log off;
            allow all;
        }
    }
}
EOF

# MySQL 초기화 스크립트
echo -e "${YELLOW}MySQL 초기화 스크립트 생성...${NC}"
cat > mysql/init.sql << 'EOF'
CREATE DATABASE IF NOT EXISTS testdb;
USE testdb;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (username, email) VALUES
    ('admin', 'admin@example.com'),
    ('user1', 'user1@example.com'),
    ('user2', 'user2@example.com');
EOF

# 웹 페이지 생성
echo -e "${YELLOW}웹 페이지 생성...${NC}"
cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Monitoring Stack</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            margin: 0;
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        h1 {
            text-align: center;
            font-size: 3em;
            margin-bottom: 30px;
        }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 40px;
        }
        .service-card {
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            transition: transform 0.3s;
        }
        .service-card:hover {
            transform: translateY(-5px);
            background: rgba(255, 255, 255, 0.2);
        }
        .service-card h3 {
            margin-bottom: 10px;
        }
        .service-card a {
            color: #ffd700;
            text-decoration: none;
            font-weight: bold;
        }
        .status {
            margin-top: 20px;
            padding: 10px;
            background: rgba(0, 255, 0, 0.2);
            border-radius: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Monitoring Stack Dashboard</h1>

        <div class="status">
            <h2>System Status: ✅ All Services Running</h2>
        </div>

        <div class="services">
            <div class="service-card">
                <h3>📊 Grafana</h3>
                <p>Data Visualization</p>
                <a href="http://localhost:3000" target="_blank">Open Grafana →</a>
            </div>

            <div class="service-card">
                <h3>📈 Prometheus</h3>
                <p>Metrics Collection</p>
                <a href="http://localhost:9090" target="_blank">Open Prometheus →</a>
            </div>

            <div class="service-card">
                <h3>🔔 Alertmanager</h3>
                <p>Alert Management</p>
                <a href="http://localhost:9093" target="_blank">Open Alertmanager →</a>
            </div>

            <div class="service-card">
                <h3>🐳 Portainer</h3>
                <p>Container Management</p>
                <a href="http://localhost:9000" target="_blank">Open Portainer →</a>
            </div>

            <div class="service-card">
                <h3>⚖️ HAProxy Stats</h3>
                <p>Load Balancer Stats</p>
                <a href="http://localhost:8404/stats" target="_blank">View Stats →</a>
            </div>

            <div class="service-card">
                <h3>📊 Node Exporter</h3>
                <p>System Metrics</p>
                <a href="http://localhost:9100/metrics" target="_blank">View Metrics →</a>
            </div>
        </div>
    </div>
</body>
</html>
EOF

# Grafana Provisioning 설정
echo -e "${YELLOW}Grafana Provisioning 설정 생성...${NC}"
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

cat > grafana/provisioning/dashboards/dashboard.yml << 'EOF'
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF

echo -e "${GREEN}✅ 설정 파일 생성 완료${NC}"