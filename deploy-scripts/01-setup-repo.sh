#!/bin/bash

#############################################
# 01-setup-repo.sh
# YUM Repository 및 기본 환경 설정 스크립트
#############################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  YUM Repository 설정 스크립트${NC}"
echo -e "${GREEN}========================================${NC}"

# OS 버전 확인
if [ -f /etc/redhat-release ]; then
    OS_VERSION=$(cat /etc/redhat-release)
    echo -e "${GREEN}OS 확인: $OS_VERSION${NC}"
else
    echo -e "${RED}RedHat 계열 OS가 아닙니다.${NC}"
    exit 1
fi

# 1. 기본 YUM Repository 설정
echo -e "\n${YELLOW}[1/5] YUM Repository 설정...${NC}"

# CentOS 7
if [[ "$OS_VERSION" == *"CentOS"* ]] && [[ "$OS_VERSION" == *"7"* ]]; then
    cat > /etc/yum.repos.d/CentOS-Base.repo << 'EOF'
[base]
name=CentOS-$releasever - Base
baseurl=http://mirror.centos.org/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-$releasever - Updates
baseurl=http://mirror.centos.org/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-$releasever - Extras
baseurl=http://mirror.centos.org/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
fi

# Rocky Linux 8/9 or RHEL 8/9
if [[ "$OS_VERSION" == *"Rocky"* ]] || [[ "$OS_VERSION" == *"Red Hat"* ]] || [[ "$OS_VERSION" == *"CentOS"* && "$OS_VERSION" == *"8"* ]]; then
    # DNF 사용
    if command -v dnf &> /dev/null; then
        echo -e "${GREEN}DNF 패키지 매니저 감지${NC}"
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
else
    PKG_MANAGER="yum"
fi

# 2. EPEL Repository 설치
echo -e "\n${YELLOW}[2/5] EPEL Repository 설치...${NC}"
$PKG_MANAGER install -y epel-release || {
    # EPEL 수동 설치 (RHEL의 경우)
    if [[ "$OS_VERSION" == *"Red Hat"* ]]; then
        if [[ "$OS_VERSION" == *"8"* ]]; then
            rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
        elif [[ "$OS_VERSION" == *"9"* ]]; then
            rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
        fi
    fi
}

# 3. Docker Repository 설정
echo -e "\n${YELLOW}[3/5] Docker Repository 설정...${NC}"
$PKG_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo 2>/dev/null || {
    $PKG_MANAGER install -y yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
}

# 4. 시스템 업데이트
echo -e "\n${YELLOW}[4/5] 시스템 패키지 업데이트...${NC}"
$PKG_MANAGER update -y

# 5. 필수 패키지 설치
echo -e "\n${YELLOW}[5/5] 필수 기본 패키지 설치...${NC}"
$PKG_MANAGER install -y \
    wget \
    curl \
    git \
    vim \
    net-tools \
    bind-utils \
    telnet \
    unzip \
    tar \
    ca-certificates \
    lsb-release \
    gnupg

echo -e "\n${GREEN}✅ Repository 설정 완료!${NC}"