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

# --- 1.5. 主机名配置 ---
if [ -n "$CUSTOM_HOSTNAME" ]; then
    echo ">> 检测到 CUSTOM_HOSTNAME=${CUSTOM_HOSTNAME}，正在设置主机名..."
    hostname "${CUSTOM_HOSTNAME}"
    echo ">> 主机名已设置为: $(hostname)"
fi

# --- 2. 用户和密码逻辑 ---
TARGET_USER="${USER:-root}"
USER_HOME="/root" # 默认为 root 的家目录

if [ "$TARGET_USER" != "root" ]; then
    USER_HOME="/home/${TARGET_USER}"
    echo ">> 检测到 USER=${TARGET_USER}，将创建非 root 用户。"
    useradd -m -d "${USER_HOME}" -s /bin/bash "$TARGET_USER"
    adduser "$TARGET_USER" sudo
    echo ">> 用户 ${TARGET_USER} 创建成功并已添加到 sudo 组。"
    printf '\n# Enable bash-completion\n. /usr/share/bash-completion/bash_completion' >> "${USER_HOME}/.bashrc"

    if [[ "${SUDO_NOPASSWD}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
        echo ">> 检测到 SUDO_NOPASSWD=true，为用户 ${TARGET_USER} 配置免密 sudo。"
        SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"
        echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
        chmod 440 "${SUDOERS_FILE}"
    fi
fi

if [ -n "$PASSWORD" ]; then
    echo ">> 使用环境变量 PASSWORD 中提供的固定密码。"
    FINAL_PASSWORD="$PASSWORD"
else
    FINAL_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    echo "========================================================================"
    echo ">> 未设置 PASSWORD，已生成一个随机密码。"
    echo "========================================================================"
    echo "    用户名: $TARGET_USER"
    echo "    密  码: $FINAL_PASSWORD"
    echo "========================================================================"
fi

echo "${TARGET_USER}:${FINAL_PASSWORD}" | chpasswd
echo ">> 已为用户 ${TARGET_USER} 设置密码。"

# --- 2.5. 配置 SSH 公钥 ---
if [ -n "$SSH_PUBKEY" ]; then
    echo ">> 检测到 SSH_PUBKEY，正在为用户 ${TARGET_USER} 配置密钥认证..."
    mkdir -p "${USER_HOME}/.ssh"
    echo "${SSH_PUBKEY}" >> "${USER_HOME}/.ssh/authorized_keys"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    chmod 600 "${USER_HOME}/.ssh/authorized_keys"
    echo ">> SSH 公钥配置完成。"
fi


# --- 3. 启动服务 ---
echo ">> 正在启动核心服务..."

# 启动 ttyd 服务
LOGIN_CMD=("login" "-f" "$TARGET_USER")
ttyd -W -p 8080 -c "${TARGET_USER}:${FINAL_PASSWORD}" "${LOGIN_CMD[@]}" &
ttyd -W -p 8443 --ssl --ssl-cert "$CERT_FILE" --ssl-key "$KEY_FILE" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${LOGIN_CMD[@]}" &

# --- 新增: 启动 miniserve 文件浏览器服务 ---
echo ">> 正在启动 Web 文件浏览器 (miniserve)..."
# -u 启用上传, --auth 设置认证, -p 设置端口, 最后是服务目录
miniserve -u --auth "${TARGET_USER}:${FINAL_PASSWORD}" -p 8081 "${USER_HOME}" &
# --- 修正: 此处 --tls-key 应指向 $KEY_FILE 而非 $CERT_FILE ---
miniserve -u --auth "${TARGET_USER}:${FINAL_PASSWORD}" -p 8444 --tls-cert "$CERT_FILE" --tls-key "$KEY_FILE" "${USER_HOME}" &

# 检查是否需要启动 SSH 服务
if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    echo ">> 检测到 SSH=true，正在启动 SSH 服务..."
    if [ "$TARGET_USER" != "root" ]; then
        echo "AllowUsers ${TARGET_USER}" >> /etc/ssh/sshd_config
    fi
    /usr/sbin/sshd -D &
fi

# --- 4. 启动后台保活服务 ---
if [ -n "$KEEPALIVE_HOSTS" ]; then
    echo ">> 检测到 KEEPALIVE_HOSTS，正在启动后台保活服务..."
    (
        sleep 10
        IFS=',' read -ra HOST_ARRAY <<< "$KEEPALIVE_HOSTS"
        HOST_COUNT=${#HOST_ARRAY[@]}
        CURRENT_HOST_INDEX=0
        echo ">> 将通过 curl 对以下主机进行保活: ${HOST_ARRAY[*]}"
        while true; do
            if [ $HOST_COUNT -gt 0 ]; then
                host=${HOST_ARRAY[$CURRENT_HOST_INDEX]}
                echo ">> 正在保活主机: $host"
                if ! curl -s -o /dev/null --fail "$host"; then
                    echo -e "\033[33m[WARNING]\033[0m 保活主机 $host 失败，请检查网络或 URL。"
                fi
                CURRENT_HOST_INDEX=$(( (CURRENT_HOST_INDEX + 1) % HOST_COUNT ))
            fi
            echo ">> 保活任务完成，将等待 ${KEEPALIVE_INTERVAL:-300} 秒后继续..."
            sleep "${KEEPALIVE_INTERVAL:-300}"
        done
    ) &
fi


echo ">> 服务正在监听以下端口:"
echo "    - Web 终端 (HTTP)      : 8080"
echo "    - Web 终端 (HTTPS)     : 8443"
echo "    - 文件浏览器 (HTTP)    : 8081"
echo "    - 文件浏览器 (HTTPS)   : 8444"
if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    echo "    - SSH                  : 22"
fi

trap 'kill $(jobs -p)' SIGTERM
wait -n
