# HAProxy Dynamic Load Balancer

Docker Compose 기반 HAProxy 로드밸런서와 동적 스케일링 시스템

## 구성 요소

- **HAProxy**: 로드밸런서 (포트 80)
- **Nginx**: 웹서버 (PHP 지원, 동적 스케일링)
- **MySQL**: 데이터베이스

## 사용법

### 1. 시스템 시작
```bash
docker compose up -d --scale nginx=2
```

### 2. 오토스케일러 실행
```bash
./auto-scaler.sh &
```

### 3. 웹 접속
- **메인 페이지**: http://localhost/
- **HAProxy 통계**: http://localhost/haproxy-stats (admin/admin123)

### 4. 부하 테스트
```bash
# 스케일 아웃 테스트
docker exec workspace-nginx-1 stress -c 2 --timeout 60s

# 로드밸런싱 테스트
./test-lb.sh
```

## 스케일링 설정

- **최소/최대 복제본**: 2-6개
- **스케일 아웃 임계값**: CPU 20%
- **스케일 인 임계값**: CPU 5%
- **쿨다운**: 15초

## 파일 구조

```
.
├── docker-compose.yml      # 메인 설정
├── auto-scaler.sh         # 자동 스케일링 스크립트
├── test-lb.sh             # 로드밸런싱 테스트 스크립트
├── haproxy/
│   └── haproxy.cfg        # HAProxy 설정
├── nginx/                 # Nginx 이미지 빌드
├── mysql/                 # MySQL 초기화 스크립트
└── web/                   # 웹 파일들
```