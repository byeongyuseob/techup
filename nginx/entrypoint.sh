#!/bin/sh

# NFS 마운트 설정
NFS_SERVER="10.95.137.10"
NFS_PATH="/nfs/shared"
MOUNT_POINT="/var/www/html/nfs"

# 마운트 포인트 생성
mkdir -p ${MOUNT_POINT}

# NFS 마운트 시도
echo "Attempting to mount NFS from ${NFS_SERVER}:${NFS_PATH} to ${MOUNT_POINT}..."

# NFS 서버 연결 가능 여부 확인
if ping -c 1 -W 2 ${NFS_SERVER} > /dev/null 2>&1; then
    echo "NFS server ${NFS_SERVER} is reachable"

    # showmount로 export 확인
    if showmount -e ${NFS_SERVER} > /dev/null 2>&1; then
        echo "NFS exports available on ${NFS_SERVER}"

        # 마운트 시도
        if mount -t nfs -o nolock,vers=3 ${NFS_SERVER}:${NFS_PATH} ${MOUNT_POINT}; then
            echo "NFS mounted successfully"

            # 테스트 파일 작성
            if echo "NFS mount test at $(date)" > ${MOUNT_POINT}/.mount_test 2>/dev/null; then
                echo "NFS mount is writable"
                rm -f ${MOUNT_POINT}/.mount_test
            else
                echo "WARNING: NFS mount is read-only or not accessible"
            fi
        else
            echo "Failed to mount NFS. Running without NFS mount."
        fi
    else
        echo "Cannot access NFS exports on ${NFS_SERVER}. Running without NFS mount."
    fi
else
    echo "NFS server ${NFS_SERVER} is not reachable. Running without NFS mount."
fi

# nginx 시작
echo "Starting nginx..."
exec nginx -g 'daemon off;'