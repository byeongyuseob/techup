#!/bin/bash

# 기본 2개 인스턴스로 시작하는 스크립트

echo "🧹 기존 컨테이너 정리..."
docker compose down

echo ""
echo "🚀 Docker Compose 시작 (nginx 2개 인스턴스)"
docker compose up -d --scale nginx=2

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
echo "  - 최소: 2개, 최대: 10개"
echo "  - CPU 임계치: >10% (Scale UP), <5% (Scale DOWN)"
echo "  - 체크 간격: 10초"
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