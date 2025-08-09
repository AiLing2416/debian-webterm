# 步骤 1: 选择基础镜像
FROM debian:trixie-slim

# 添加镜像元数据
LABEL maintainer="ailing2416" version="1.4" description="Debian with Web Terminal, File Browser, and optional SSH Server"

# 步骤 2: 安装软件
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y \
    openssl \
    openssh-server \
    curl \
    wget \
    git \
    vim \
    nano \
    bash \
    htop \
    net-tools \
    dnsutils \
    procps \
    sudo \
    jq \
    unzip \
    zip \
    iproute2 \
    iputils-ping \
    bash-completion \
    traceroute \
    lsof \
    man-db && \
    # 下载 ttyd 二进制文件
    curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o /usr/local/bin/ttyd && \
    # 赋予 ttyd 和 miniserve 执行权限
    chmod +x /usr/local/bin/ttyd && \
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 步骤 3: 配置 SSH 服务
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
