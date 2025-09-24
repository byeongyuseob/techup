#!/bin/bash

# 완전 자동화 배포 스크립트
# 이 스크립트를 실행하면 모든 환경이 자동으로 구성됩니다.

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 포트 설정 파일 로드
source ./ports.conf

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}     완전 자동화 배포 스크립트 시작${NC}"
echo -e "${BLUE}================================================${NC}"

# 1. 기존 환경 정리
echo -e "\n${YELLOW}[1/10] 기존 환경 정리 중...${NC}"
docker compose down 2>/dev/null || true
pkill -f auto-scaler.sh 2>/dev/null || true
pkill -f alert-webhook.py 2>/dev/null || true
pkill -f docker-stats-exporter.py 2>/dev/null || true
sleep 2

# 2. 필수 디렉토리 생성
echo -e "\n${YELLOW}[2/10] 필수 디렉토리 생성 중...${NC}"
mkdir -p prometheus
mkdir -p alertmanager
mkdir -p haproxy
mkdir -p nginx
mkdir -p grafana/provisioning/dashboards
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/dashboards

# 3. docker-compose.yml 생성
echo -e "\n${YELLOW}[3/10] Docker Compose 파일 생성 중...${NC}"
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  haproxy:
    image: haproxytech/haproxy-alpine:2.8
    container_name: haproxy
    ports:
      - "${HAPROXY_HTTP_PORT}:80"
      - "${HAPROXY_STATS_PORT}:8404"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - nfs-shared:/mnt/nfs:rw
    networks:
      - load-balancer-net
    depends_on:
      - nginx
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/index.html:/usr/share/nginx/html/index.html:ro
      - nfs-shared:/mnt/nfs:rw
    expose:
      - "${NGINX_PORT}"
    networks:
      - load-balancer-net
    restart: unless-stopped
    deploy:
      replicas: ${INITIAL_INSTANCES}

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "${PROMETHEUS_PORT}:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml:ro
      - prometheus_data:/prometheus
    networks:
      - load-balancer-net
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "${NODE_EXPORTER_PORT}:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc|rootfs/var/lib/docker/containers|rootfs/var/lib/docker/overlay2|rootfs/run/docker/netns|rootfs/var/lib/docker/aufs)($$|/)'
    networks:
      - load-balancer-net
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    ports:
      - "${ALERTMANAGER_PORT}:9093"
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro
      - alertmanager_data:/alertmanager
    networks:
      - load-balancer-net
    restart: unless-stopped

  nginx-exporter:
    image: nginx/nginx-prometheus-exporter:latest
    container_name: nginx-exporter
    ports:
      - "${NGINX_EXPORTER_PORT}:9113"
    command:
      - --nginx.scrape-uri=http://haproxy/nginx-status
    networks:
      - load-balancer-net
    depends_on:
      - nginx
      - haproxy
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "${GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/etc/grafana/dashboards:ro
    networks:
      - load-balancer-net
    restart: unless-stopped

networks:
  load-balancer-net:
    driver: bridge

volumes:
  prometheus_data:
  alertmanager_data:
  grafana_data:
  nfs-shared:
    driver: local
    driver_opts:
      type: nfs
      o: addr=${NFS_SERVER_IP},rw,nolock,hard,intr
      device: ":${NFS_MOUNT_PATH}"
EOF

# docker-compose.yml에 포트 변수 치환
envsubst < docker-compose.yml > docker-compose.tmp && mv docker-compose.tmp docker-compose.yml

# 4. HAProxy 설정 생성
echo -e "\n${YELLOW}[4/10] HAProxy 설정 생성 중...${NC}"
cat > haproxy/haproxy.cfg << EOF
global
    log stdout local0
    maxconn 4096
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    stats enable
    stats uri /haproxy-stats
    stats refresh 10s

frontend http_front
    bind *:80
    acl is_stats path_beg /haproxy-stats
    acl is_nginx_status path_beg /nginx-status
    use_backend stats if is_stats
    use_backend nginx_status if is_nginx_status
    default_backend nginx-backend

backend stats
    stats enable
    stats uri /haproxy-stats
    stats refresh 10s
    stats show-legends
    stats show-node

backend nginx_status
    balance roundrobin
    server-template nginx- 1-20 nginx:${NGINX_PORT} check resolvers docker init-addr libc,none

backend nginx-backend
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server-template nginx- 1-20 nginx:${NGINX_PORT} check resolvers docker init-addr libc,none

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

frontend stats
    bind *:8404
    option http-use-htx
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s
EOF

# 5. Nginx 설정 생성
echo -e "\n${YELLOW}[5/10] Nginx 설정 생성 중...${NC}"
cat > nginx/nginx.conf << 'EOF'
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
    keepalive_timeout 65;

    server {
        listen 8080;
        server_name _;

        location / {
            root /usr/share/nginx/html;
            index index.html;
        }

        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        location /nginx-status {
            stub_status;
            access_log off;
        }
    }
}
EOF

cat > nginx/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Nginx Load Balancing Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 50px; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #333; }
        .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Nginx Auto-Scaling Demo</h1>
        <div class="info">
            <p><strong>Container Hostname:</strong> <span id="hostname"></span></p>
            <p><strong>Container IP:</strong> <span id="ip"></span></p>
            <p><strong>Current Time:</strong> <span id="time"></span></p>
        </div>
    </div>
    <script>
        document.getElementById('hostname').innerText = location.hostname;
        document.getElementById('time').innerText = new Date().toLocaleString();
    </script>
</body>
</html>
EOF

# 6. Prometheus 설정 생성
echo -e "\n${YELLOW}[6/10] Prometheus 설정 생성 중...${NC}"
cat > prometheus/prometheus.yml << EOF
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

  - job_name: 'nginx'
    static_configs:
      - targets: ['nginx-exporter:9113']

  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:8404']

  - job_name: 'docker-stats'
    static_configs:
      - targets: ['host.docker.internal:${DOCKER_STATS_PORT}']

  - job_name: 'alertmanager'
    static_configs:
      - targets: ['alertmanager:9093']
EOF

cat > prometheus/alert.rules.yml << EOF
groups:
  - name: auto-scaling
    interval: 10s
    rules:
      - alert: HighCPUUsage
        expr: rate(container_cpu_usage_seconds_total[1m]) * 100 > ${CPU_THRESHOLD_UP}
        for: 30s
        labels:
          severity: warning
          action: scale_up
        annotations:
          summary: "High CPU usage detected"
          description: "CPU usage is above ${CPU_THRESHOLD_UP}% for more than 30 seconds"

      - alert: LowCPUUsage
        expr: rate(container_cpu_usage_seconds_total[1m]) * 100 < ${CPU_THRESHOLD_DOWN}
        for: 1m
        labels:
          severity: info
          action: scale_down
        annotations:
          summary: "Low CPU usage detected"
          description: "CPU usage is below ${CPU_THRESHOLD_DOWN}% for more than 1 minute"

      - alert: NginxHighConnectionCount
        expr: nginx_connections_active > 10
        for: 30s
        labels:
          severity: warning
        annotations:
          summary: "High number of active connections"
          description: "Nginx has more than 10 active connections"

      - alert: NginxDown
        expr: up{job="nginx"} == 0
        for: 30s
        labels:
          severity: critical
        annotations:
          summary: "Nginx exporter is down"
          description: "Nginx exporter has been down for more than 30 seconds"

      - alert: AutoScalingTriggered
        expr: changes(nginx_up[5m]) > 0
        labels:
          severity: info
        annotations:
          summary: "Auto-scaling event detected"
          description: "Number of Nginx instances has changed"
EOF

# 7. AlertManager 설정 생성
echo -e "\n${YELLOW}[7/10] AlertManager 설정 생성 중...${NC}"
cat > alertmanager/alertmanager.yml << EOF
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'webhook-receiver'

receivers:
  - name: 'webhook-receiver'
    webhook_configs:
      - url: 'http://host.docker.internal:${ALERT_WEBHOOK_PORT}/alert'
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF

# 8. Grafana 설정 생성
echo -e "\n${YELLOW}[8/10] Grafana 설정 생성 중...${NC}"
cat > grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
EOF

cat > grafana/provisioning/dashboards/dashboard.yml << EOF
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

cat > grafana/dashboards/unified-dashboard.json << 'EOF'
{
  "dashboard": {
    "id": null,
    "uid": "unified-dashboard",
    "title": "통합 모니터링 대시보드",
    "panels": [
      {
        "id": 1,
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "type": "graph",
        "title": "Nginx 활성 연결 수",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "nginx_connections_active",
            "refId": "A"
          }
        ]
      },
      {
        "id": 2,
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
        "type": "graph",
        "title": "CPU 사용률",
        "datasource": "Prometheus",
        "targets": [
          {
            "expr": "rate(container_cpu_usage_seconds_total[1m]) * 100",
            "refId": "A"
          }
        ]
      },
      {
        "id": 3,
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
        "type": "alert-list",
        "title": "활성 알람",
        "options": {
          "showOptions": "current",
          "maxItems": 10,
          "sortOrder": 1,
          "dashboardAlerts": false,
          "alertName": "",
          "dashboardTitle": "",
          "tags": []
        }
      }
    ],
    "time": {"from": "now-1h", "to": "now"},
    "timepicker": {},
    "timezone": "",
    "schemaVersion": 27,
    "version": 0
  }
}
EOF

# 9. 지원 스크립트 생성
echo -e "\n${YELLOW}[9/10] 지원 스크립트 생성 중...${NC}"

# Auto-scaler 스크립트
cat > auto-scaler.sh << 'EOF'
#!/bin/bash

source ./ports.conf

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}[Auto-Scaler] 오토스케일러 시작${NC}"
echo -e "${GREEN}[Auto-Scaler] 설정: MIN=$MIN_INSTANCES, MAX=$MAX_INSTANCES${NC}"
echo -e "${GREEN}[Auto-Scaler] CPU: UP>$CPU_THRESHOLD_UP%, DOWN<$CPU_THRESHOLD_DOWN%${NC}"
echo -e "${GREEN}[Auto-Scaler] 요청: UP>$REQ_THRESHOLD_UP/s, DOWN<$REQ_THRESHOLD_DOWN/s${NC}"

while true; do
    # 현재 Nginx 인스턴스 수
    current_instances=$(docker ps --filter "name=nginx" --format "{{.Names}}" | wc -l)

    # CPU 사용률 확인 (Prometheus에서)
    cpu_usage=$(curl -s "http://localhost:9090/api/v1/query?query=avg(rate(container_cpu_usage_seconds_total[1m]))*100" | \
                grep -o '"value":\[[0-9.]*,"[0-9.]*"' | \
                sed 's/.*,"\([0-9.]*\)".*/\1/' | \
                cut -d. -f1)

    # 요청 속도 확인 (HAProxy 메트릭)
    req_rate=$(curl -s "http://localhost:8404/metrics" | \
               grep "haproxy_backend_http_requests_total" | \
               grep "nginx-backend" | \
               awk '{print $2}' | \
               head -1)

    # 기본값 설정
    cpu_usage=${cpu_usage:-0}
    req_rate=${req_rate:-0}

    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] 현재 상태: 인스턴스=$current_instances, CPU=$cpu_usage%, 요청=$req_rate/s${NC}"

    # 스케일 업 조건
    if [[ $current_instances -lt $MAX_INSTANCES ]] && \
       ([[ $cpu_usage -gt $CPU_THRESHOLD_UP ]] || [[ ${req_rate%.*} -gt $REQ_THRESHOLD_UP ]]); then
        new_instances=$((current_instances + 1))
        echo -e "${RED}[Auto-Scaler] 스케일 업: $current_instances → $new_instances${NC}"
        docker compose up -d --scale nginx=$new_instances --no-recreate
        sleep 10  # 안정화 대기

    # 스케일 다운 조건
    elif [[ $current_instances -gt $MIN_INSTANCES ]] && \
         [[ $cpu_usage -lt $CPU_THRESHOLD_DOWN ]] && \
         [[ ${req_rate%.*} -lt $REQ_THRESHOLD_DOWN ]]; then
        new_instances=$((current_instances - 1))
        echo -e "${GREEN}[Auto-Scaler] 스케일 다운: $current_instances → $new_instances${NC}"
        docker compose up -d --scale nginx=$new_instances --no-recreate
        sleep 10  # 안정화 대기
    fi

    sleep $CHECK_INTERVAL
done
EOF
chmod +x auto-scaler.sh

# Alert webhook 스크립트
cat > alert-webhook.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, request, jsonify
from datetime import datetime
import json

app = Flask(__name__)

@app.route('/alert', methods=['POST'])
def receive_alert():
    try:
        data = request.json
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        for alert in data.get('alerts', []):
            status = alert.get('status', 'unknown')
            alert_name = alert.get('labels', {}).get('alertname', 'unknown')
            severity = alert.get('labels', {}).get('severity', 'unknown')
            description = alert.get('annotations', {}).get('description', 'No description')

            # 색상 코드
            color = '\033[0;32m' if status == 'resolved' else '\033[0;31m'
            nc = '\033[0m'

            print(f"{color}[{timestamp}] Alert: {alert_name}{nc}")
            print(f"  Status: {status}")
            print(f"  Severity: {severity}")
            print(f"  Description: {description}")
            print("-" * 50)

        return jsonify({"status": "success"}), 200
    except Exception as e:
        print(f"Error processing alert: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    print("Alert Webhook Server started on port 8082")
    app.run(host='0.0.0.0', port=8082)
EOF
chmod +x alert-webhook.py

# Docker stats exporter
cat > docker-stats-exporter.py << 'EOF'
#!/usr/bin/env python3
import json
import time
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/metrics':
            try:
                result = subprocess.run(
                    ['docker', 'stats', '--no-stream', '--format', 'json'],
                    capture_output=True,
                    text=True
                )

                metrics = []
                for line in result.stdout.strip().split('\n'):
                    if line:
                        data = json.loads(line)
                        container = data['Name'].replace('-', '_')
                        cpu = data['CPUPerc'].replace('%', '')
                        mem = data['MemUsage'].split('/')[0]

                        metrics.append(f'docker_cpu_percent{{container="{container}"}} {cpu}')
                        metrics.append(f'docker_memory_usage{{container="{container}"}} {len(mem)}')

                response = '\n'.join(metrics)
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.end_headers()
                self.wfile.write(response.encode())
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(str(e).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        return  # Suppress logs

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8081), MetricsHandler)
    print('Docker Stats Exporter started on port 8081')
    server.serve_forever()
EOF
chmod +x docker-stats-exporter.py

# 시작 스크립트
cat > start.sh << 'EOF'
#!/bin/bash

source ./ports.conf

echo "🧹 기존 컨테이너 정리..."
docker compose down

echo ""
echo "🚀 Docker Compose 시작 (nginx ${INITIAL_INSTANCES}개 인스턴스)"
docker compose up -d --scale nginx=${INITIAL_INSTANCES}

echo ""
echo "⏳ 서비스 안정화 대기 (10초)..."
sleep 10

echo ""
echo "✅ 현재 실행 중인 nginx 인스턴스:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|nginx"

echo ""
echo "🔄 Auto-scaler 재시작..."
pkill -f auto-scaler.sh 2>/dev/null
sleep 1
nohup ./auto-scaler.sh > /var/log/auto-scaler.log 2>&1 &
echo "✅ Auto-scaler 시작됨 (로그: /var/log/auto-scaler.log)"

echo ""
echo "==============================================="
echo "📊 Auto-scaling 설정:"
echo "  - 최소: ${MIN_INSTANCES}개, 최대: ${MAX_INSTANCES}개"
echo "  - CPU 임계치: >${CPU_THRESHOLD_UP}% (Scale UP), <${CPU_THRESHOLD_DOWN}% (Scale DOWN)"
echo "  - 체크 간격: ${CHECK_INTERVAL}초"
echo ""
echo "🧪 테스트 명령어:"
echo "  docker exec -it workspace-nginx-1 stress -c 1"
echo "  → 이 명령어만으로도 Auto-scaling 발생!"
echo ""
echo "📍 모니터링 URL:"
echo "  - HAProxy: http://localhost/haproxy-stats"
echo "  - Grafana: http://localhost:3000"
echo "  - Prometheus: http://localhost:9090"
echo "==============================================="
EOF
chmod +x start.sh

# 10. 백그라운드 서비스 시작
echo -e "\n${YELLOW}[10/10] 백그라운드 서비스 시작 중...${NC}"

# Alert webhook 시작
nohup python3 alert-webhook.py > /var/log/alert-webhook.log 2>&1 &
echo -e "${GREEN}✓ Alert Webhook 시작됨${NC}"

# Docker stats exporter 시작
nohup python3 docker-stats-exporter.py > /var/log/docker-stats-exporter.log 2>&1 &
echo -e "${GREEN}✓ Docker Stats Exporter 시작됨${NC}"

# Docker Compose 시작
echo -e "\n${BLUE}Docker Compose 시작 중...${NC}"
docker compose up -d --scale nginx=${INITIAL_INSTANCES}

# 서비스 안정화 대기
echo -e "\n${YELLOW}서비스 안정화 대기 (15초)...${NC}"
sleep 15

# Auto-scaler는 수동으로 시작
echo -e "\n${YELLOW}Auto-scaler는 수동으로 시작하세요:${NC}"
echo "  ./auto-scaler.sh &"
echo "  또는"
echo "  nohup ./auto-scaler.sh > /var/log/auto-scaler.log 2>&1 &"

# 상태 확인
echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}                배포 완료!${NC}"
echo -e "${BLUE}================================================${NC}"

echo -e "\n${GREEN}실행 중인 컨테이너:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n${GREEN}서비스 접속 정보:${NC}"
echo "  - HAProxy Stats: http://localhost:${HAPROXY_HTTP_PORT}/haproxy-stats"
echo "  - Grafana: http://localhost:${GRAFANA_PORT} (admin/admin)"
echo "  - Prometheus: http://localhost:${PROMETHEUS_PORT}"
echo "  - AlertManager: http://localhost:${ALERTMANAGER_PORT}"

echo -e "\n${GREEN}로그 확인:${NC}"
echo "  - Auto-scaler: tail -f /var/log/auto-scaler.log"
echo "  - Alert Webhook: tail -f /var/log/alert-webhook.log"
echo "  - Docker Stats: tail -f /var/log/docker-stats-exporter.log"

# 11. Auto-scaler 자동 시작
echo -e "\n${YELLOW}[11/12] Auto-scaler 자동 시작 중...${NC}"
nohup ./auto-scaler.sh > /var/log/auto-scaler.log 2>&1 &
echo -e "${GREEN}✓ Auto-scaler 시작됨${NC}"
sleep 5

# 12. 배포 검증 테스트 실행
echo -e "\n${YELLOW}[12/12] 배포 검증 테스트 실행 중...${NC}"

# 테스트 결과 저장
TESTS_PASSED=0
TESTS_FAILED=0

# 테스트 함수
run_test() {
    local test_name="$1"
    local test_command="$2"

    echo -ne "${YELLOW}[TEST] ${test_name}...${NC} "

    if eval "$test_command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

echo -e "\n${BLUE}1. 컨테이너 상태 확인${NC}"
run_test "HAProxy 컨테이너" "docker ps | grep -q haproxy"
run_test "Prometheus 컨테이너" "docker ps | grep -q prometheus"
run_test "Grafana 컨테이너" "docker ps | grep -q grafana"
run_test "AlertManager 컨테이너" "docker ps | grep -q alertmanager"
run_test "Node Exporter 컨테이너" "docker ps | grep -q node-exporter"
run_test "Nginx Exporter 컨테이너" "docker ps | grep -q nginx-exporter"
run_test "Nginx 컨테이너 (최소 ${MIN_INSTANCES}개)" "[ $(docker ps --filter 'name=nginx' --format '{{.Names}}' | wc -l) -ge ${MIN_INSTANCES} ]"

echo -e "\n${BLUE}2. 서비스 접근성 확인${NC}"
run_test "HAProxy HTTP (포트 ${HAPROXY_HTTP_PORT})" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${HAPROXY_HTTP_PORT} | grep -q '200'"
run_test "HAProxy Stats (포트 ${HAPROXY_STATS_PORT})" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${HAPROXY_STATS_PORT}/stats | grep -q '200'"
run_test "Prometheus (포트 ${PROMETHEUS_PORT})" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PROMETHEUS_PORT}/-/ready | grep -q '200'"
run_test "Grafana (포트 ${GRAFANA_PORT})" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${GRAFANA_PORT}/api/health | grep -q '200'"
run_test "AlertManager (포트 ${ALERTMANAGER_PORT})" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${ALERTMANAGER_PORT}/-/ready | grep -q '200'"

echo -e "\n${BLUE}3. 메트릭 수집 확인${NC}"
run_test "Node Exporter 메트릭" "curl -s http://localhost:${NODE_EXPORTER_PORT}/metrics | grep -q 'node_'"
run_test "Nginx Exporter 메트릭" "curl -s http://localhost:${NGINX_EXPORTER_PORT}/metrics | grep -q 'nginx_'"
run_test "HAProxy 메트릭" "curl -s http://localhost:${HAPROXY_STATS_PORT}/metrics | grep -q 'haproxy_'"
run_test "Docker Stats 메트릭" "curl -s http://localhost:${DOCKER_STATS_PORT}/metrics | grep -q 'docker_'"

echo -e "\n${BLUE}4. Prometheus 타겟 상태 확인${NC}"
run_test "Prometheus 자체 타겟" "curl -s http://localhost:${PROMETHEUS_PORT}/api/v1/targets | grep -q '\"health\":\"up\"'"

echo -e "\n${BLUE}5. 프로세스 상태 확인${NC}"
run_test "Auto-scaler 프로세스" "pgrep -f auto-scaler.sh > /dev/null"
run_test "Alert Webhook 프로세스" "pgrep -f alert-webhook.py > /dev/null"
run_test "Docker Stats Exporter 프로세스" "pgrep -f docker-stats-exporter.py > /dev/null"

echo -e "\n${BLUE}6. 로드 밸런싱 테스트${NC}"
echo -e "${YELLOW}10개 요청을 통한 로드 밸런싱 확인...${NC}"
RESPONSES=""
for i in {1..10}; do
    RESPONSE=$(curl -s http://localhost:${HAPROXY_HTTP_PORT} | grep -o 'workspace-nginx-[0-9]*' | head -1 2>/dev/null || echo "")
    if [ -n "$RESPONSE" ]; then
        RESPONSES="${RESPONSES}${RESPONSE}\n"
    fi
done

if [ -n "$RESPONSES" ]; then
    UNIQUE_BACKENDS=$(echo -e "$RESPONSES" | sort -u | wc -l)
    if [ "$UNIQUE_BACKENDS" -gt 1 ]; then
        echo -e "${GREEN}✓ 로드 밸런싱 작동 확인 (${UNIQUE_BACKENDS}개 백엔드 사용)${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${YELLOW}⚠ 단일 백엔드만 응답${NC}"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${RED}✗ 로드 밸런싱 테스트 실패${NC}"
    ((TESTS_FAILED++))
fi

echo -e "\n${BLUE}================================================${NC}"
echo -e "${BLUE}                최종 결과${NC}"
echo -e "${BLUE}================================================${NC}"

echo -e "\n${GREEN}실행 중인 컨테이너:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n${GREEN}서비스 접속 정보:${NC}"
echo "  - HAProxy Stats: http://localhost:${HAPROXY_HTTP_PORT}/haproxy-stats"
echo "  - Grafana: http://localhost:${GRAFANA_PORT} (admin/admin)"
echo "  - Prometheus: http://localhost:${PROMETHEUS_PORT}"
echo "  - AlertManager: http://localhost:${ALERTMANAGER_PORT}"

echo -e "\n${GREEN}로그 확인:${NC}"
echo "  - Auto-scaler: tail -f /var/log/auto-scaler.log"
echo "  - Alert Webhook: tail -f /var/log/alert-webhook.log"
echo "  - Docker Stats: tail -f /var/log/docker-stats-exporter.log"

echo -e "\n${BLUE}테스트 결과:${NC}"
echo -e "${GREEN}통과: ${TESTS_PASSED}개${NC}"
echo -e "${RED}실패: ${TESTS_FAILED}개${NC}"

if [ "$TESTS_FAILED" -eq 0 ]; then
    echo -e "\n${GREEN}🎉 배포 및 검증 완료! 시스템이 정상 작동 중입니다.${NC}"
    echo -e "\n${YELLOW}스케일링 테스트:${NC}"
    echo "  docker exec -it workspace-nginx-1 stress --cpu 2 --timeout 30s"
    exit 0
else
    echo -e "\n${RED}⚠️ 일부 테스트 실패. 로그를 확인하세요.${NC}"
    echo -e "\n${YELLOW}디버깅 명령어:${NC}"
    echo "  docker logs haproxy"
    echo "  docker logs prometheus"
    echo "  docker logs grafana"
    echo "  tail -f /var/log/auto-scaler.log"
    exit 1
fi