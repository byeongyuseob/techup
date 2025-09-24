#!/bin/bash

# Configuration
MIN_REPLICAS=2
MAX_REPLICAS=5
SCALE_OUT_CPU_THRESHOLD=25  # 매우 낮게 설정
SCALE_IN_CPU_THRESHOLD=5    # 매우 낮게 설정
COOLDOWN_PERIOD=20           # 스케일링 후 대기 시간(초)

# State
LAST_SCALE_TIME=0
STATE_FILE="/tmp/scaler.state"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_current_replicas() {
    # 실행 중인 nginx 컨테이너 수
    docker ps --filter "name=nginx" --format "{{.Names}}" | grep -E "nginx[0-9]+" | wc -l
}

get_avg_cpu() {
    # docker stats를 사용해서 nginx 컨테이너들의 평균 CPU 사용률 구하기
    local cpu_sum=0
    local count=0

    for container in $(docker ps --filter "name=nginx" --format "{{.Names}}"); do
        # CPU 퍼센테이지 가져오기 (% 제거)
        cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" $container | sed 's/%//')
        if [ ! -z "$cpu" ]; then
            # 정수로 변환
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
    log "🔧 Scaling nginx containers to $new_count"

    # 현재 실행 중인 nginx 개수
    local current_count=$(get_current_replicas)

    if [ $new_count -gt $current_count ]; then
        # Scale out - 새 컨테이너 추가
        for ((i=$((current_count+1)); i<=$new_count; i++)); do
            log "  Adding nginx$i container"
            docker run -d --name nginx$i \
                --network workspace_webnet \
                -v /root/workspace/web:/var/www/html \
                -v workspace_nfs-shared:/var/www/html/nfs \
                workspace-nginx1
        done
    elif [ $new_count -lt $current_count ]; then
        # Scale in - 컨테이너 제거
        for ((i=$current_count; i>$new_count; i--)); do
            log "  Removing nginx$i container"
            docker stop nginx$i && docker rm nginx$i
        done
    fi

    # HAProxy 재시작해서 백엔드 업데이트
    log "  Restarting HAProxy to update backends"
    docker restart haproxy >/dev/null 2>&1

    update_cooldown
    log "✅ Scaling completed. Current replicas: $new_count"
}

# Main loop
log "🚀 Auto-scaler started"
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