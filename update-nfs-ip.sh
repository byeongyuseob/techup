#!/bin/bash

# NFS 서버 IP 변경 스크립트
# 사용법: ./update-nfs-ip.sh <새로운_IP>

if [ $# -eq 0 ]; then
    echo "사용법: $0 <새로운_NFS_서버_IP>"
    echo "예시: $0 192.168.0.240"
    exit 1
fi

NEW_IP=$1
OLD_IP="192.168.0.200"

echo "NFS 서버 IP를 $OLD_IP 에서 $NEW_IP 로 변경합니다..."

# nginx/start.sh 수정
if [ -f nginx/start.sh ]; then
    sed -i "s/NFS_SERVER=\"$OLD_IP\"/NFS_SERVER=\"$NEW_IP\"/g" nginx/start.sh
    echo "✅ nginx/start.sh 수정 완료"
fi

# multi-exporter.py 수정
if [ -f multi-exporter.py ]; then
    sed -i "s/self.nfs_server = \"$OLD_IP\"/self.nfs_server = \"$NEW_IP\"/g" multi-exporter.py
    echo "✅ multi-exporter.py 수정 완료"
fi

# nfs-monitor.py 수정 (있는 경우)
if [ -f nfs-monitor.py ]; then
    sed -i "s/self.nfs_server = \"$OLD_IP\"/self.nfs_server = \"$NEW_IP\"/g" nfs-monitor.py
    echo "✅ nfs-monitor.py 수정 완료"
fi

echo ""
echo "변경 완료! 다음 명령으로 컨테이너를 재시작하세요:"
echo "  docker compose build nginx"
echo "  docker compose restart nginx multi-exporter"