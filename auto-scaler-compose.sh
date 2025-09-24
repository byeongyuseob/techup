#!/bin/bash

# Configuration
MIN_REPLICAS=2
MAX_REPLICAS=6
SCALE_OUT_CPU_THRESHOLD=20  # 테스트를 위해 낮게 설정
SCALE_IN_CPU_THRESHOLD=5   # 테스트를 위해 낮게 설정
COOLDOWN_PERIOD=15          # 스케일링 후 대기 시간(초)

# State
LAST_SCALE_TIME=0
STATE_FILE="/tmp/scaler-compose.state"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_current_replicas() {
    # Docker Compose로 실행 중인 nginx 컨테이너 수
    docker compose -f docker-compose-scale.yml ps nginx 2>/dev/null | grep -c "nginx-"
}

get_avg_cpu() {
    # nginx 컨테이너들의 평균 CPU 사용률
    local cpu_sum=0
    local count=0

    for container in $(docker compose -f docker-compose-scale.yml ps nginx --quiet 2>/dev/null); do
        cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" $container 2>/dev/null | sed 's/%//')
        if [ ! -z "$cpu" ]; then
            cpu_int=$(echo "$cpu" | cut -d'.' -f1)
            cpu_sum=$((cpu_sum + cpu_int))
            count=$((count + 1))
        fi
    done

    if [ $count -eq 0 ]; then
        echo "0"
    else
        echo $((cpu_sum / count))
    fi
}

check_cooldown() {
    if [ -f "$STATE_FILE" ]; then
        LAST_SCALE_TIME=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
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
    local new_count=$1
    log "🔧 Scaling nginx to $new_count replicas"

    # Docker Compose scale command
    docker compose -f /root/workspace/docker-compose-scale.yml up -d --scale nginx=$new_count --no-recreate

    update_cooldown
    log "✅ Scaling completed. Current replicas: $new_count"
}

# Main loop
log "🚀 Auto-scaler (Docker Compose version) started"
log "   Thresholds: CPU Out=$SCALE_OUT_CPU_THRESHOLD%, In=$SCALE_IN_CPU_THRESHOLD%"
log "   Replicas: Min=$MIN_REPLICAS, Max=$MAX_REPLICAS"
log "   Cooldown: ${COOLDOWN_PERIOD}s"

while true; do
    CURRENT_REPLICAS=$(get_current_replicas)
    AVG_CPU=$(get_avg_cpu)

    log "📊 Status: Replicas=$CURRENT_REPLICAS, Avg CPU=${AVG_CPU}%"

    # Check cooldown
    if ! check_cooldown; then
        log "   ⏳ In cooldown period, waiting..."
        sleep 5
        continue
    fi

    # Scaling decision
    if [ $AVG_CPU -gt $SCALE_OUT_CPU_THRESHOLD ] && [ $CURRENT_REPLICAS -lt $MAX_REPLICAS ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
        log "📈 SCALE OUT triggered! CPU ${AVG_CPU}% > ${SCALE_OUT_CPU_THRESHOLD}%"
        scale_nginx $NEW_REPLICAS

    elif [ $AVG_CPU -lt $SCALE_IN_CPU_THRESHOLD ] && [ $CURRENT_REPLICAS -gt $MIN_REPLICAS ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
        log "📉 SCALE IN triggered! CPU ${AVG_CPU}% < ${SCALE_IN_CPU_THRESHOLD}%"
        scale_nginx $NEW_REPLICAS
    else
        log "   ✔️ No scaling needed"
    fi

    sleep 5
done