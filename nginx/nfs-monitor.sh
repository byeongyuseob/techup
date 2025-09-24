#!/bin/bash

# NFS 모니터링 및 자동 재마운트 스크립트
# 백그라운드에서 실행되어 NFS 연결 상태를 모니터링합니다

NFS_SERVER="${NFS_SERVER_IP:-10.95.137.10}"
NFS_PATH="${NFS_EXPORT_PATH:-/nfs/shared}"
MOUNT_POINT="/var/www/html/nfs"
CHECK_INTERVAL=30  # 30초마다 체크

echo "NFS 모니터링 시작: ${NFS_SERVER}:${NFS_PATH}"

while true; do
    # 마운트 상태 확인
    if mountpoint -q ${MOUNT_POINT}; then
        # 마운트는 되어 있는데 실제로 접근 가능한지 확인
        if timeout 5 ls ${MOUNT_POINT} > /dev/null 2>&1; then
            # 정상 작동 중
            echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 정상"
        else
            # 마운트는 되어 있지만 접근 불가 (stale mount)
            echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS stale mount 감지, 재마운트 시도..."

            # 강제 언마운트
            umount -f ${MOUNT_POINT} 2>/dev/null || umount -l ${MOUNT_POINT} 2>/dev/null

            # NFS 서버 확인 후 재마운트
            if ping -c 1 -W 2 ${NFS_SERVER} > /dev/null 2>&1; then
                if mount -t nfs -o soft,timeo=100,retrans=3,retry=2,nolock,vers=3 ${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT}; then
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 재마운트 성공"
                else
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 재마운트 실패"
                fi
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 서버에 연결할 수 없음"
            fi
        fi
    else
        # 마운트되어 있지 않음
        echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 마운트 안됨, 마운트 시도..."

        if ping -c 1 -W 2 ${NFS_SERVER} > /dev/null 2>&1; then
            if mount -t nfs -o soft,timeo=100,retrans=3,retry=2,nolock,vers=3 ${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT}; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 마운트 성공"
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 마운트 실패"
            fi
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - NFS 서버에 연결할 수 없음"
        fi
    fi

    sleep ${CHECK_INTERVAL}
done