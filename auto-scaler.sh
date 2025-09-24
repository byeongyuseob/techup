#!/bin/bash

# Configuration
MIN_REPLICAS=2
MAX_REPLICAS=6
SCALE_OUT_CPU_THRESHOLD=30  # 테스트를 위해 낮게 설정
SCALE_IN_CPU_THRESHOLD=10   # 테스트를 위해 낮게 설정
SCALE_OUT_MEM_THRESHOLD=40  # 테스트를 위해 낮게 설정
SCALE_IN_MEM_THRESHOLD=15   # 테스트를 위해 낮게 설정
COOLDOWN_PERIOD=30           # 스케일링 후 대기 시간(초)
PROMETHEUS_URL="http://localhost:9090"

# State file
STATE_FILE="/tmp/scaler.state"
LAST_SCALE_TIME=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_current_replicas() {
    docker ps --filter "name=nginx" --format "{{.Names}}" | grep -E "nginx[0-9]+" | wc -l
}

get_cpu_usage() {
    # cAdvisor를 통해 nginx 컨테이너들의 평균 CPU 사용률 조회
    curl -s "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode 'query=avg(rate(container_cpu_usage_seconds_total{name=~"nginx.*"}[30s])) * 100' \
        | grep -oP '"value":\[.*?,"\K[0-9.]+' | head -1
}

get_memory_usage() {
    # cAdvisor를 통해 nginx 컨테이너들의 평균 메모리 사용률 조회
    curl -s "${PROMETHEUS_URL}/api/v1/query" \
        --data-urlencode 'query=avg(container_memory_usage_bytes{name=~"nginx.*"} / container_spec_memory_limit_bytes{name=~"nginx.*"}) * 100' \
        | grep -oP '"value":\[.*?,"\K[0-9.]+' | head -1
}

check_cooldown() {
    if [ -f "$STATE_FILE" ]; then
        LAST_SCALE_TIME=$(cat "$STATE_FILE")
    fi

    CURRENT_TIME=$(date +%s)
    TIME_DIFF=$((CURRENT_TIME - LAST_SCALE_TIME))

    if [ $TIME_DIFF -lt $COOLDOWN_PERIOD ]; then
        return 1  # Still in cooldown
    fi
    return 0  # Not in cooldown
}

update_cooldown() {
    date +%s > "$STATE_FILE"
}

scale_nginx() {
    local target_replicas=$1
    log "Scaling nginx to $target_replicas replicas"

    # Docker Compose scale 명령
    cd /root/workspace
    docker-compose up -d --scale nginx1=${target_replicas} --scale nginx2=${target_replicas} --no-recreate

    # HAProxy 백엔드 업데이트를 위해 재시작
    docker-compose restart haproxy

    update_cooldown
    log "Scaling completed. New replica count: $target_replicas"
}

# Main loop
log "Auto-scaler started with thresholds: CPU(out:${SCALE_OUT_CPU_THRESHOLD}%/in:${SCALE_IN_CPU_THRESHOLD}%), MEM(out:${SCALE_OUT_MEM_THRESHOLD}%/in:${SCALE_IN_MEM_THRESHOLD}%)"

while true; do
    CURRENT_REPLICAS=$(get_current_replicas)
    CPU_USAGE=$(get_cpu_usage)
    MEM_USAGE=$(get_memory_usage)

    # 메트릭이 비어있으면 기본값 설정
    if [ -z "$CPU_USAGE" ]; then CPU_USAGE="0"; fi
    if [ -z "$MEM_USAGE" ]; then MEM_USAGE="0"; fi

    log "Current state - Replicas: $CURRENT_REPLICAS, CPU: ${CPU_USAGE}%, Memory: ${MEM_USAGE}%"

    # Check if cooldown period has passed
    if ! check_cooldown; then
        log "In cooldown period, skipping scaling decision"
        sleep 10
        continue
    fi

    # Scale out decision
    if (( $(echo "$CPU_USAGE > $SCALE_OUT_CPU_THRESHOLD" | bc -l) )) || \
       (( $(echo "$MEM_USAGE > $SCALE_OUT_MEM_THRESHOLD" | bc -l) )); then
        if [ $CURRENT_REPLICAS -lt $MAX_REPLICAS ]; then
            NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
            log "SCALE OUT triggered - CPU: ${CPU_USAGE}%, MEM: ${MEM_USAGE}%"
            scale_nginx $NEW_REPLICAS
        else
            log "Already at maximum replicas ($MAX_REPLICAS)"
        fi

    # Scale in decision
    elif (( $(echo "$CPU_USAGE < $SCALE_IN_CPU_THRESHOLD" | bc -l) )) && \
         (( $(echo "$MEM_USAGE < $SCALE_IN_MEM_THRESHOLD" | bc -l) )); then
        if [ $CURRENT_REPLICAS -gt $MIN_REPLICAS ]; then
            NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
            log "SCALE IN triggered - CPU: ${CPU_USAGE}%, MEM: ${MEM_USAGE}%"
            scale_nginx $NEW_REPLICAS
        else
            log "Already at minimum replicas ($MIN_REPLICAS)"
        fi
    fi

    sleep 10
done