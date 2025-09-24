# 📦 폐쇄망 완전 오프라인 배포 가이드

## 🎯 준비된 내용

### 1. **complete-install.sh** - 원터치 설치 스크립트
- SELinux/방화벽 자동 비활성화
- 모든 필수 패키지 설치
- Docker/Docker Compose 설치
- 시스템 최적화
- 자동 시작 서비스 설정
- 모든 설정 파일 자동 생성

### 2. **offline-prepare.sh** - 오프라인 패키지 준비
- 모든 RPM 패키지 다운로드
- Docker 이미지 저장
- Python 패키지 다운로드
- 전체 압축 파일 생성

## 📋 필요한 YUM 패키지 (complete-install.sh에서 자동 설치)

### Docker 관련
```
docker-ce
docker-ce-cli
containerd.io
docker-compose-plugin
```

### 시스템 도구
```
yum-utils
device-mapper-persistent-data
lvm2
wget curl git vim
net-tools bind-utils telnet nmap-ncat
htop iotop sysstat
bash-completion tmux screen tree
unzip bzip2 rsync chrony
jq bc dos2unix lsof
tcpdump traceroute mtr socat
```

### NFS 관련
```
nfs-utils
rpcbind
```

### Python/개발
```
python3
python3-pip
gcc make
openssl openssl-devel
```

## 🐳 필요한 Docker 이미지

```bash
# 기본 이미지
ubuntu:22.04
mysql:8.0
haproxy:2.8
python:3.9-slim

# 모니터링 스택
prom/prometheus:latest
grafana/grafana:latest
prom/alertmanager:latest
prom/node-exporter:latest
nginx/nginx-prometheus-exporter:latest
```

## 🚀 온라인 환경에서 실행 (현재 서버)

```bash
# 원터치 설치 (인터넷 연결 필요)
cd /root/workspace
chmod +x complete-install.sh
./complete-install.sh
```

## 📦 오프라인 배포 준비 (인터넷 있는 서버에서)

```bash
# 오프라인 패키지 준비
cd /root/workspace
chmod +x offline-prepare.sh
./offline-prepare.sh

# 생성되는 파일: /root/offline-packages.tar.gz (약 2GB)
```

## 🔒 폐쇄망 서버 배포

### Step 1: 파일 이동
```bash
# USB/CD로 offline-packages.tar.gz 복사
# 폐쇄망 서버의 /root로 이동
```

### Step 2: 압축 해제
```bash
cd /root
tar xzf offline-packages.tar.gz
cd offline-packages
```

### Step 3: 오프라인 설치
```bash
./offline-install.sh      # RPM, Docker 이미지, Python 패키지 설치
cd /root/workspace
./complete-install.sh      # 전체 시스템 설정
```

### Step 4: 서비스 시작
```bash
docker compose up -d --scale nginx=2
nohup ./auto-scaler.sh &
```

## ⚙️ 자동 설정되는 항목

### 시스템 설정
- ✅ SELinux 비활성화
- ✅ 방화벽 완전 비활성화
- ✅ 커널 파라미터 최적화
- ✅ ulimit 설정
- ✅ 로그 로테이션

### 서비스 자동 시작
- ✅ docker.service
- ✅ docker-stack.service (컨테이너 자동 시작)
- ✅ auto-scaler.service (오토스케일러)
- ✅ rc.local (부팅시 실행)
- ✅ crontab (헬스체크)

### 네트워크
- ✅ NFS 마운트 (10.95.137.5:/nfs/shared)
- ✅ Docker 네트워크
- ✅ hosts 파일

## 🔑 접속 정보

### 모든 비밀번호: **naver123**

| 서비스 | URL | 계정 |
|--------|-----|------|
| 웹 애플리케이션 | http://서버IP | - |
| HAProxy Stats | http://서버IP/haproxy-stats | admin/naver123 |
| Grafana | http://서버IP:3000 | admin/naver123 |
| Prometheus | http://서버IP:9090 | - |
| AlertManager | http://서버IP:9093 | - |
| MySQL | 서버IP:3306 | root/naver123 |

## ❗ 수동으로 해야 할 작업

### 1. NFS 서버 확인
```bash
# NFS 서버(10.95.137.5)에서 export 확인
showmount -e 10.95.137.5

# 만약 다른 경로면 docker-compose.yml 수정
vi /root/workspace/docker-compose.yml
# device: ":/nfs/shared" 부분 수정
```

### 2. 서버 재부팅 후 확인
```bash
# 자동 시작 확인
systemctl status docker-stack
systemctl status auto-scaler
docker ps
```

### 3. 문제 발생시
```bash
# 로그 확인
journalctl -u docker-stack -f
journalctl -u auto-scaler -f
docker compose logs -f

# 수동 시작
cd /root/workspace
docker compose up -d --scale nginx=2
./auto-scaler.sh &
```

## 📊 확인 명령어

```bash
# 컨테이너 상태
docker ps

# 시스템 리소스
docker stats

# 네트워크 연결
netstat -tulpn

# NFS 마운트
mount | grep nfs

# 서비스 상태
systemctl status docker-stack auto-scaler

# 로드 밸런싱 테스트
for i in {1..10}; do curl http://localhost/hostname.php; echo; done
```

## 🎯 최종 체크리스트

- [ ] complete-install.sh 실행 완료
- [ ] Docker 서비스 실행 중
- [ ] 모든 컨테이너 Running 상태
- [ ] 웹 페이지 접속 가능
- [ ] Grafana 접속 가능
- [ ] NFS 마운트 확인
- [ ] 오토스케일러 동작 확인
- [ ] 재부팅 후 자동 시작 확인

---

**모든 설정이 자동화되어 있습니다!**
문제 발생시 `/var/log/docker-install.log` 확인