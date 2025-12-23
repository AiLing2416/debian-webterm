# 步骤 1: 选择基础镜像
FROM debian:trixie-slim

# 添加镜像元数据
LABEL maintainer="ailing2416" version="1.7.0" description="Debian with Web Terminal (ttya), File Transfer, and optional SSH Server"

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
    zsh \
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
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 步骤 3: 下载 ttya 二进制文件（支持多架构）
ARG TARGETARCH
RUN if [ -z "$TARGETARCH" ]; then \
    ARCH=$(uname -m); \
    case "$ARCH" in \
    x86_64) TTYA_ARCH="amd64" ;; \
    aarch64) TTYA_ARCH="arm64" ;; \
    armv7l) TTYA_ARCH="armv7" ;; \
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac; \
    else \
    case "$TARGETARCH" in \
    amd64) TTYA_ARCH="amd64" ;; \
    arm64) TTYA_ARCH="arm64" ;; \
    arm) TTYA_ARCH="armv7" ;; \
    *) echo "Unsupported architecture: $TARGETARCH" && exit 1 ;; \
    esac; \
    fi && \
    echo "Downloading ttya for architecture: $TTYA_ARCH" && \
    curl -L "https://github.com/AiLing2416/ttya/releases/download/v1.8.0/ttya-${TTYA_ARCH}" -o /usr/local/bin/ttya && \
    chmod +x /usr/local/bin/ttya

# 步骤 4: 配置 SSH 服务
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    ssh-keygen -A

# 步骤 5: 启用 Bash Tab 补全
RUN echo '\n# Enable bash-completion\n. /usr/share/bash-completion/bash_completion' >> /root/.bashrc

# 步骤 6: 配置终端配色
COPY .bashrc_colors /root/.bashrc_colors
RUN cat /root/.bashrc_colors >> /root/.bashrc

# 步骤 7: 配置动态 MOTD 系统
COPY motd_gen.sh /usr/local/bin/motd_gen.sh
RUN chmod +x /usr/local/bin/motd_gen.sh && \
    mkdir -p /etc/webterm && \
    echo '/usr/local/bin/motd_gen.sh' >> /etc/profile

# 步骤 7.1: 配置 PAM (保留用于 SSH 等其他 login 场景的稳定性)
RUN sed -i '/pam_systemd.so/d' /etc/pam.d/login && \
    sed -i '/pam_audit.so/d' /etc/pam.d/login && \
    sed -i '/pam_loginuid.so/d' /etc/pam.d/login

# 步骤 8: 复制并配置入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 步骤 9: 配置容器运行时
# 注意: EXPOSE 仅为元数据，实际端口由 entrypoint.sh 中的变量和 docker run -p 参数决定
EXPOSE 8080 8443 22
# 定义容器的入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# 定义传递给入口脚本的默认命令
CMD ["bash"]
