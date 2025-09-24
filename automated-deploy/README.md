# 🚀 Monitoring Stack 자동 배포 시스템

완전 자동화된 모니터링 인프라 구축 솔루션

## 📋 개요

이 프로젝트는 **깡통 OS**에서 단 하나의 명령어로 전체 모니터링 스택을 자동 구축하는 스크립트입니다.

## 🎯 주요 기능

- ✅ **완전 자동화**: 수동 작업 없이 모든 과정 자동화
- ✅ **폐쇄망 지원**: Docker Registry 설정으로 인터넷 없이 배포 가능
- ✅ **원클릭 설치**: 단일 스크립트로 전체 스택 구축
- ✅ **모든 서비스 포함**: Prometheus, Grafana, MySQL, HAProxy 등 포함

## 🛠 포함된 서비스

| 서비스 | 포트 | 설명 |
|--------|------|------|
| HAProxy | 80, 8404 | 로드밸런서 & Stats |
| Nginx | 내부 | 웹 서버 |
| MySQL | 3306 | 데이터베이스 |
| Prometheus | 9090 | 메트릭 수집 |
| Grafana | 3000 | 모니터링 대시보드 |
| Alertmanager | 9093 | 알림 관리 |
| Node Exporter | 9100 | 시스템 메트릭 |
| cAdvisor | 8080 | 컨테이너 메트릭 |
| Portainer | 9000 | 컨테이너 관리 UI |

## 📦 시스템 요구사항

- **OS**: RHEL/CentOS 7+ 또는 Ubuntu 18.04+
- **RAM**: 최소 4GB (권장 8GB)
- **Disk**: 최소 20GB
- **권한**: root 권한 필요

## 🚀 빠른 시작

### 1. 코드 다운로드
```bash
git clone https://github.com/byeongyuseob/techup.git
cd techup/automated-deploy
```

### 2. 실행 권한 부여
```bash
chmod +x deploy.sh
```

### 3. 배포 실행
```bash
sudo ./deploy.sh
```

## 🔧 고급 설정

### Docker Registry 사용 (폐쇄망)

배포 시 Registry 옵션을 선택하고 주소 입력:
```
Docker Registry를 사용하시겠습니까? (y/n) y
Docker Registry 주소를 입력하세요: registry.example.com:5000
```

### NFS 연동

NFS 스토리지 사용 시:
```
NFS를 사용하시겠습니까? (y/n) y
NFS 서버 IP를 입력하세요: 10.0.0.100
NFS Export 경로를 입력하세요: /nfs/shared
```

## 📁 디렉토리 구조

```
/opt/monitoring-stack/
├── docker-compose.yml      # 메인 구성 파일
├── .env                    # 환경 변수
├── prometheus/            # Prometheus 설정
├── alertmanager/          # Alertmanager 설정
├── grafana/              # Grafana 설정
├── haproxy/              # HAProxy 설정
├── nginx/                # Nginx 설정
├── mysql/                # MySQL 초기화
└── web/                  # 웹 콘텐츠
```

## 📊 서비스 접속

배포 완료 후 다음 URL로 접속:

- **메인 대시보드**: http://[서버IP]
- **Grafana**: http://[서버IP]:3000 (admin/naver123)
- **Prometheus**: http://[서버IP]:9090
- **Alertmanager**: http://[서버IP]:9093
- **Portainer**: http://[서버IP]:9000
- **HAProxy Stats**: http://[서버IP]:8404/stats

## 🔍 유용한 명령어

```bash
# 서비스 상태 확인
cd /opt/monitoring-stack && docker-compose ps

# 로그 확인
docker-compose logs -f [서비스명]

# 서비스 재시작
docker-compose restart

# 서비스 중지
docker-compose down

# 서비스 시작
docker-compose up -d
```

## 🐛 문제 해결

### Docker 설치 실패
```bash
# YUM 캐시 정리
yum clean all
yum makecache
```

### 포트 충돌
```bash
# 사용 중인 포트 확인
netstat -tunlp | grep [포트번호]
```

### 서비스 시작 실패
```bash
# Docker 상태 확인
systemctl status docker

# Docker 재시작
systemctl restart docker
```

## 📝 라이센스

MIT License

## 👨‍💻 작성자

- GitHub: [@byeongyuseob](https://github.com/byeongyuseob)

## 🤝 기여

Issues와 Pull Requests는 언제나 환영합니다!