# 步骤 1: 选择基础镜像
FROM debian:trixie-slim

# 添加镜像元数据
LABEL maintainer="ailing2416" version="1.6.0" description="Debian with Web Terminal, and optional SSH Server"

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
    # 下载 ttyd 二进制文件
    curl -L https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 -o /usr/local/bin/ttyd && \
    # 赋予 ttyd 执行权限
    chmod +x /usr/local/bin/ttyd && \
    # 清理 apt 缓存
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 步骤 3: 配置 SSH 服务
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    ssh-keygen -A

# 步骤 4: 启用 Bash Tab 补全
RUN echo '\n# Enable bash-completion\n. /usr/share/bash-completion/bash_completion' >> /root/.bashrc

# 步骤 5: 配置终端配色
COPY .bashrc_colors /root/.bashrc_colors
RUN cat /root/.bashrc_colors >> /root/.bashrc

# 步骤 6: 配置 MOTD 和自定义主机名显示
RUN echo '\n# Display the Message of the Day on login' >> /etc/profile && \
    echo 'cat /etc/motd' >> /etc/profile && \
    echo '\n# Set custom hostname in shell prompt if specified' >> /etc/profile && \
    echo 'if [ -n "$CUSTOM_HOSTNAME" ]; then' >> /etc/profile && \
    echo '    PS1="${debian_chroot:+($debian_chroot)}\\[\\033[01;32m\\]\\u@${CUSTOM_HOSTNAME}\\[\\033[00m\\]:\\[\\033[01;34m\\]\\w\\[\\033[00m\\]\\$ "' >> /etc/profile && \
    echo 'fi' >> /etc/profile

# 步骤 7: 复制并配置入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 步骤 8: 配置容器运行时
# 注意: EXPOSE 仅为元数据，实际端口由 entrypoint.sh 中的变量和 docker run -p 参数决定
EXPOSE 8080 8443 22
# 定义容器的入口点
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# 定义传递给入口脚本的默认命令
CMD ["bash"]
