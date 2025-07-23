# 步骤 1: 选择基础镜像
FROM debian:bookworm-slim

# 添加镜像元数据
LABEL maintainer="ailing2416" version="1.1" description="Debian with Web Terminal and optional SSH Server"

# 步骤 2: 安装软件
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    # 新增了 openssh-server
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
    # 赋予 ttyd 执行权限
    chmod +x /usr/local/bin/ttyd && \
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 步骤 3: 配置 SSH 服务
# 允许 root 用户通过密码登录，并生成主机密钥
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    ssh-keygen -A

# 步骤 4: 启用 Bash Tab 补全
RUN echo '\n# Enable bash-completion\n. /usr/share/bash-completion/bash_completion' >> /root/.bashrc

# 步骤 5: 复制并配置入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 步骤 6: 配置容器运行时
# 暴露三个端口: 8080 (HTTP), 8443 (HTTPS), 22 (SSH)
EXPOSE 8080 8443 22
# 定义容器的入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# 定义传递给入口脚本的默认命令
CMD ["bash"]
