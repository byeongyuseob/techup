#!/bin/bash

# 오토스케일링 설정
MIN_INSTANCES=2
MAX_INSTANCES=10
CPU_THRESHOLD_UP=10    # stress -c 1 정도에도 반응하도록 아주 낮춤
CPU_THRESHOLD_DOWN=5   # 매우 낮은 임계치
REQ_THRESHOLD_UP=10    # 요청 임계치도 낮춤
REQ_THRESHOLD_DOWN=5   # 요청 임계치도 낮춤
CHECK_INTERVAL=10      # 더 빠른 반응을 위해 10초로 단축

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