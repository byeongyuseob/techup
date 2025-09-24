#!/bin/bash

# PHP-FPM 시작
service php8.1-fpm start

# NFS 마운트 설정
# 환경변수가 없으면 기본값 사용
NFS_SERVER="${NFS_SERVER_IP:-10.95.137.10}"
NFS_PATH="${NFS_EXPORT_PATH:-/nfs/shared}"
MOUNT_POINT="/var/www/html/nfs"

# 마운트 포인트 생성
mkdir -p ${MOUNT_POINT}

# NFS 마운트 시도
echo "Attempting to mount NFS from ${NFS_SERVER}:${NFS_PATH} to ${MOUNT_POINT}..."

# NFS 서버 연결 가능 여부 확인
echo "Checking NFS server ${NFS_SERVER}..."
if ping -c 1 -W 2 ${NFS_SERVER} > /dev/null 2>&1; then
    echo "NFS server ${NFS_SERVER} is reachable via ping"

    # NFS 서비스가 실제로 실행 중인지 확인 (포트 2049)
    if timeout 2 bash -c "echo > /dev/tcp/${NFS_SERVER}/2049" 2>/dev/null; then
        echo "NFS service is running on ${NFS_SERVER}"

        # 마운트 시도 (타임아웃 짧게 설정)
        if timeout 5 mount -t nfs -o soft,timeo=20,retrans=1,nolock,vers=3 ${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT} 2>/dev/null; then
            echo "NFS mounted successfully"

            # 실제로 마운트 되었는지 확인
            if mountpoint -q ${MOUNT_POINT}; then
                echo "NFS mount verified at ${MOUNT_POINT}"

                # 테스트 파일 작성
                if echo "NFS mount test at $(date)" > ${MOUNT_POINT}/.mount_test 2>/dev/null; then
                    echo "NFS mount is writable"
                    rm -f ${MOUNT_POINT}/.mount_test
                else
                    echo "WARNING: NFS mount is read-only or not accessible"
                fi
            else
                echo "WARNING: Mount command succeeded but mount point not active"
            fi
        else
            echo "Failed to mount NFS. Running without NFS mount."
        fi
    else
        echo "NFS service is not running on ${NFS_SERVER}:2049. Running without NFS mount."
    fi
else
    echo "NFS server ${NFS_SERVER} is not reachable. Running without NFS mount."
fi

# NFS 모니터링 백그라운드 실행 (옵션)
if [ -f /nfs-monitor.sh ]; then
    echo "NFS 모니터링 스크립트 시작..."
    /nfs-monitor.sh >> /var/log/nfs-monitor.log 2>&1 &
fi

# Nginx 시작
nginx -g "daemon off;"