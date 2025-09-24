#!/bin/bash

# 호스트 시스템에 NFS 자동 마운트 설정
# systemd mount unit을 사용하여 자동 재연결 구현

NFS_SERVER="${1:-192.168.0.200}"
NFS_PATH="${2:-/nfs/shared}"
MOUNT_POINT="/mnt/nfs-shared"

echo "NFS 자동 마운트 설정 시작..."

# 마운트 포인트 생성
mkdir -p ${MOUNT_POINT}

# systemd mount unit 생성
cat > /etc/systemd/system/mnt-nfs-shared.mount << EOF
[Unit]
Description=NFS Mount ${NFS_SERVER}:${NFS_PATH}
After=network-online.target
Wants=network-online.target

[Mount]
What=${NFS_SERVER}:${NFS_PATH}
Where=${MOUNT_POINT}
Type=nfs
Options=soft,timeo=100,retrans=3,retry=2,_netdev,auto

[Install]
WantedBy=multi-user.target
EOF

# automount unit 생성 (자동 재연결)
cat > /etc/systemd/system/mnt-nfs-shared.automount << EOF
[Unit]
Description=Automount NFS ${NFS_SERVER}:${NFS_PATH}
After=network-online.target
Wants=network-online.target

[Automount]
Where=${MOUNT_POINT}
TimeoutIdleSec=10

[Install]
WantedBy=multi-user.target
EOF

# systemd 리로드 및 서비스 활성화
systemctl daemon-reload
systemctl enable mnt-nfs-shared.automount
systemctl start mnt-nfs-shared.automount

echo "NFS 자동 마운트 설정 완료!"
echo "마운트 포인트: ${MOUNT_POINT}"
echo ""
echo "Docker Compose에서 사용하려면:"
echo "  volumes:"
echo "    - ${MOUNT_POINT}:/var/www/html/nfs"