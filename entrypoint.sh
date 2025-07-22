#!/bin/bash

# --- 1. 证书生成 (与之前相同) ---
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

# --- 2. 密码逻辑 ---
TTY_USER="root" # SSH 登录将使用 root 用户

if [ -n "$TTY_PASSWORD" ]; then
    echo ">> 使用环境变量 TTY_PASSWORD 中提供的固定密码。"
    FINAL_PASSWORD="$TTY_PASSWORD"
else
    FINAL_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    echo "========================================================================"
    echo ">> 未设置 TTY_PASSWORD，已生成一个随机密码。"
    echo "========================================================================"
    echo "    用户名: $TTY_USER"
    echo "    密  码: $FINAL_PASSWORD"
    echo "========================================================================"
fi

# --- 3. 启动服务 ---
echo ">> 正在启动核心服务..."

# 启动 HTTP ttyd 服务
ttyd -W -p 8080 -c "${TTY_USER}:${FINAL_PASSWORD}" "$@" &

# 启动 HTTPS ttyd 服务
ttyd -W -p 8443 --ssl --ssl-cert "$CERT_FILE" --ssl-key "$KEY_FILE" -c "${TTY_USER}:${FINAL_PASSWORD}" "$@" &

# 检查是否需要启动 SSH 服务
if [[ "${ENABLE_SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    echo ">> 检测到 ENABLE_SSH=true，正在启动 SSH 服务..."
    # 将密码应用到 root 用户，使其能通过 SSH 登录
    echo "${TTY_USER}:${FINAL_PASSWORD}" | chpasswd
    # 在后台启动 sshd 守护进程
    /usr/sbin/sshd -D &
    echo ">> SSH 服务正在监听内部端口 22"
fi

echo ">> Web 终端正在监听以下端口:"
echo "    - HTTP : 8080"
echo "    - HTTPS :  8443"

# 设置陷阱，在接收到停止信号时，杀掉所有后台子进程
trap 'kill $(jobs -p)' SIGTERM

# 等待任何一个后台进程退出，脚本就会随之退出
wait -n
