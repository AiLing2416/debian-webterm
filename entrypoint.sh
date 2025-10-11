#!/bin/bash
set -e

# --- 0. 环境变量与端口配置 ---
SSH_PORT=${SSH_PORT:-22}
TTYD_HTTP_PORT=${TTYD_HTTP_PORT:-8080}
TTYD_HTTPS_PORT=${TTYD_HTTPS_PORT:-8443}

# --- 1. 证书与主机名配置 ---
CERT_FILE="/etc/ssl/certs/ttyd.crt"
KEY_FILE="/etc/ssl/private/ttyd.key"
if [[ ! "${WEB_TERMINAL}" =~ ^([fF][aA][lL][sS][eE]|0|[nN][oO])$ ]]; then
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
      echo ">> Generating self-signed TLS certificate for Web Terminal..."
      mkdir -p /etc/ssl/private
      openssl req -x509 -newkey rsa:4096 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=localhost"
    fi
fi

if [ -n "$CUSTOM_HOSTNAME" ]; then
    echo ">> Configuring custom hostname: ${CUSTOM_HOSTNAME}..."
    if hostname "${CUSTOM_HOSTNAME}"; then
        echo ">> System hostname successfully set to: $(hostname)"
    else
        echo -e "\033[33m[WARNING]\033[0m Failed to set system hostname. Container may lack 'SYS_ADMIN' capability. Current hostname: $(hostname)"
    fi
    echo ">> Shell prompt will be updated to display '${CUSTOM_HOSTNAME}' upon login."
fi

# --- 1.8. 自定义软件包安装 ---
if [ -n "$INSTALL_PACKAGES" ]; then
    echo ">> Installing custom packages: ${INSTALL_PACKAGES}..."
    apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10
    apt-get install -y --no-install-recommends ${INSTALL_PACKAGES}
    apt-get clean && rm -rf /var/lib/apt/lists/*
    echo ">> Custom packages installed."
fi

# --- 2. 用户和环境设置 ---
CLEANED_USER=$(echo "${USER}" | tr -d '"')
TARGET_USER="${CLEANED_USER:-root}"
USER_HOME="/root"
DEFAULT_SHELL="/bin/bash"

if [[ "${USE_ZSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    DEFAULT_SHELL="/bin/zsh"
fi

if [ "$TARGET_USER" != "root" ]; then
    USER_HOME="/home/${TARGET_USER}"
    if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
        useradd -m -d "${USER_HOME}" -s "${DEFAULT_SHELL}" "$TARGET_USER"
        adduser "$TARGET_USER" sudo
        echo ">> User ${TARGET_USER} created with shell ${DEFAULT_SHELL}."
    fi
else
    if [[ "${USE_ZSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
        chsh -s /bin/zsh root
    fi
fi

# 2.1 为目标用户安装 Zsh / Oh My Zsh
if [[ "${USE_ZSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
    if [ ! -d "${USER_HOME}/.oh-my-zsh" ]; then
        echo ">> Setting up Zsh and Oh My Zsh for ${TARGET_USER}..."
        sudo -u "${TARGET_USER}" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) -s --unattended"
        echo "ZSH_THEME=\"agnoster\"" >> "${USER_HOME}/.zshrc"
        echo ">> Zsh setup complete."
    fi
fi

# 2.2 为目标用户配置 .bashrc
printf '\n. /usr/share/bash-completion/bash_completion\n' >> "${USER_HOME}/.bashrc"
cat /root/.bashrc_colors >> "${USER_HOME}/.bashrc"
if [ "$TARGET_USER" != "root" ]; then
    chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.bashrc"
fi

# 2.3 为目标用户拉取 Dotfiles
if [ -n "$DOTFILES_GIT_REPO" ]; then
    echo ">> Installing dotfiles from ${DOTFILES_GIT_REPO} for ${TARGET_USER}..."
    DOTFILES_DIR=$(mktemp -d)
    if git clone --depth=1 "${DOTFILES_GIT_REPO}" "${DOTFILES_DIR}"; then
        sudo -u "${TARGET_USER}" rsync -a --exclude=".git/" "${DOTFILES_DIR}/" "${USER_HOME}/"
        echo ">> Dotfiles installed successfully."
    else
        echo -e "\033[33m[WARNING]\033[0m Failed to clone dotfiles repository."
    fi
    rm -rf "${DOTFILES_DIR}"
fi

# --- 2.8. 密码和公钥 ---
if [[ "${SUDO_NOPASSWD}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ && "$TARGET_USER" != "root" ]]; then
    SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"
    # 【修正】将 NOPWD: 修正为正确的 NOPASSWD:
    echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
fi
if [ -n "$PASSWORD" ]; then FINAL_PASSWORD="$PASSWORD"; else FINAL_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16); echo ">> Generated random password for ${TARGET_USER}: ${FINAL_PASSWORD}"; fi
echo "${TARGET_USER}:${FINAL_PASSWORD}" | chpasswd
if [ -n "$SSH_PUBKEY" ]; then mkdir -p "${USER_HOME}/.ssh"; echo "${SSH_PUBKEY}" >> "${USER_HOME}/.ssh/authorized_keys"; chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.ssh"; chmod 700 "${USER_HOME}/.ssh"; chmod 600 "${USER_HOME}/.ssh/authorized_keys"; fi

# --- 3. 服务配置与启动 ---
# 3.1 SSH 配置
sed -i "s/^#\? *Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
sed -i "s/^#\? *PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
if [ "$TARGET_USER" != "root" ]; then
    sed -i "/^AllowUsers/d" /etc/ssh/sshd_config
    echo "AllowUsers ${TARGET_USER}" >> /etc/ssh/sshd_config
fi

# 3.3 核心服务启动
echo ">> Starting core services..."

# 【新增】根据 WEB_TERMINAL 变量决定是否启动 ttyd
if [[ ! "${WEB_TERMINAL}" =~ ^([fF][aA][lL][sS][eE]|0|[nN][oO])$ ]]; then
    echo ">> Starting Web Terminal (ttyd)..."
    LOGIN_CMD=("runuser" "-l" "$TARGET_USER")
    TTYD_OPTS=()
    if [ -n "$TTYD_FONT_SIZE" ]; then TTYD_OPTS+=("-t" "fontSize=${TTYD_FONT_SIZE}"); fi
    ttyd -W -p "${TTYD_HTTP_PORT}" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${TTYD_OPTS[@]}" "${LOGIN_CMD[@]}" &
    ttyd -W -p "${TTYD_HTTPS_PORT}" --ssl --ssl-cert "$CERT_FILE" --ssl-key "$KEY_FILE" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${TTYD_OPTS[@]}" "${LOGIN_CMD[@]}" &
else
    echo ">> Web Terminal (ttyd) is disabled."
fi

if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then 
    echo ">> Starting SSH server..."
    /usr/sbin/sshd -D & 
fi

# --- 4. 保活与日志 ---
if [ -n "$KEEPALIVE_HOSTS" ]; then ( sleep 10; IFS=',' read -ra HOST_ARRAY <<< "$KEEPALIVE_HOSTS"; while true; do for host in "${HOST_ARRAY[@]}"; do curl -s -o /dev/null --fail "$host" || echo -e "\033[33m[WARNING]\033[0m Keep-alive for $host failed."; done; sleep "${KEEPALIVE_INTERVAL:-300}"; done ) & fi

echo ">> Services are listening on:"
if [[ ! "${WEB_TERMINAL}" =~ ^([fF][aA][lL][sS][eE]|0|[nN][oO])$ ]]; then
    echo "    - Web Terminal (HTTP):  ${TTYD_HTTP_PORT}"
    echo "    - Web Terminal (HTTPS): ${TTYD_HTTPS_PORT}"
fi
if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then 
    echo "    - SSH:                  ${SSH_PORT}"
fi

trap 'kill $(jobs -p)' SIGTERM
wait -n
