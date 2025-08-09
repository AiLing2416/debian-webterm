#!/bin/bash

# --- 1. 证书生成 ---
CERT_FILE="/etc/ssl/certs/ttyd.crt"
KEY_FILE="/etc/ssl/private/ttyd.key"
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
  echo ">> 正在生成自签名 TLS 证书..."
  mkdir -p /etc/ssl/private
  openssl req -x509 -newkey rsa:4096 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=localhost"
  echo ">> 证书生成完毕。"
else
  echo ">> 检测到已存在的 TLS 证书，跳过生成步骤。"
fi

# --- 2. 用户和密码逻辑 ---
TARGET_USER="${TTY_USER:-root}"
USER_HOME="/root" # 默认为 root 的家目录

if [ "$TARGET_USER" != "root" ]; then
    USER_HOME="/home/${TARGET_USER}"
    echo ">> 检测到 TTY_USER=${TARGET_USER}，将创建非 root 用户。"
    useradd -m -d "${USER_HOME}" -s /bin/bash "$TARGET_USER"
    adduser "$TARGET_USER" sudo
    echo ">> 用户 ${TARGET_USER} 创建成功并已添加到 sudo 组。"
    echo '\n# Enable bash-completion\n. /usr/share/bash-completion/bash_completion' >> "${USER_HOME}/.bashrc"

    if [[ "${SUDO_NOPASSWD}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
        echo ">> 检测到 SUDO_NOPASSWD=true，为用户 ${TARGET_USER} 配置免密 sudo。"
        SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"
        echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
        chmod 440 "${SUDOERS_FILE}"
    fi
fi

if [ -n "$TTY_PASSWORD" ]; then
    echo ">> 使用环境变量 TTY_PASSWORD 中提供的固定密码。"
    FINAL_PASSWORD="$TTY_PASSWORD"
else
    FINAL_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    echo "========================================================================"
    echo ">> 未设置 TTY_PASSWORD，已生成一个随机密码。"
    echo "========================================================================"
    echo "    用户名: $TARGET_USER"
    echo "    密  码: $FINAL_PASSWORD"
    echo "========================================================================"
fi

echo "${TARGET_USER}:${FINAL_PASSWORD}" | chpasswd
echo ">> 已为用户 ${TARGET_USER} 设置密码。"

# --- 3. 启动服务 ---
echo ">> 正在启动核心服务..."

# 启动 ttyd 服务
LOGIN_CMD=("$@")
if [ "$TARGET_USER" != "root" ]; then
    LOGIN_CMD=("login" "-f" "$TARGET_USER")
fi
ttyd -W -p 8080 -c "${TARGET_USER}:${FINAL_PASSWORD}" "${LOGIN_CMD[@]}" &
ttyd -W -p 8443 --ssl --ssl-cert "$CERT_FILE" --ssl-key "$KEY_FILE" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${LOGIN_CMD[@]}" &

# 检查是否需要启动 SSH 服务
if [[ "${ENABLE_SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    echo ">> 检测到 ENABLE_SSH=true，正在启动 SSH 服务..."
    if [ "$TARGET_USER" != "root" ]; then
        echo "AllowUsers ${TARGET_USER}" >> /etc/ssh/sshd_config
    fi
    /usr/sbin/sshd -D &
    echo ">> SSH 服务正在监听内部端口 22"
fi

echo ">> 服务正在监听以下端口:"
echo "    - Web 终端 (HTTP)      : 8080"
echo "    - Web 终端 (HTTPS)     : 8443"
if [[ "${ENABLE_SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    echo "    - SSH                  : 22"
fi

# 设置陷阱，在接收到停止信号时，杀掉所有后台子进程
trap 'kill $(jobs -p)' SIGTERM

# 等待任何一个后台进程退出，脚本就会随之退出
wait -n
