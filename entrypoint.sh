#!/bin/bash
set -e

# --- 辅助函数：生成动态 MOTD ---
generate_motd() {
    local MOTD_OUT="/etc/motd"
    local SHOW_SYS_INFO=${SHOW_MOTD_SYS_INFO:-true}
    
    # 颜色定义
    local C1="\033[01;32m" # 绿色
    local C2="\033[01;34m" # 蓝色
    local NC="\033[00m"    # 无颜色

    # 1. 基础模板合成 (原版风格增强)
    {
        echo -e "${C1}  _      __      __   __                      "
        echo -e " | | /| / /__  / /_ / /_ ___  ____ __ _ "
        echo -e " | |/ |/ // -_)/ __// __// -_)/ __//  ' \\"
        echo -e " |__/|__/ \\__/ \\__/ \\__/ \\__/ /_/  /_/_/_/${NC}"
        echo ""
        echo -e " Welcome to ${C2}Webterm-1.7${NC} (Powered by ttya)"
        echo ""
        
        # 系统状态检测
        if [ "$SHOW_SYS_INFO" = "true" ]; then
            local OS_VER=$(grep "PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
            local KERNEL=$(uname -sr)
            local ARCH=$(uname -m)
            local UPTIME=$(uptime -p | sed 's/up //')
            local MEM_INFO=$(free -h | awk '/Mem:/ {print $3 "/" $2}')
            local CPU_CORES=$(nproc)
            local LOAD=$(awk '{print $1, $2, $3}' /proc/loadavg)

            echo -e " ${C2}OS:${NC}      $OS_VER"
            echo -e " ${C2}Kernel:${NC}  $KERNEL"
            echo -e " ${C2}Arch:${NC}    $ARCH"
            echo -e " ${C2}Uptime:${NC}  $UPTIME"
            echo -e " ${C2}Memory:${NC}  $MEM_INFO"
            echo -e " ${C2}CPU:${NC}     $CPU_CORES cores (Load: $LOAD)"
            echo ""
        fi
        
        # 法律免责与原版提示
        echo " The programs included with the Debian GNU/Linux system are free software;"
        echo " the exact distribution terms for each program are described in the"
        echo " individual files in /usr/share/doc/*/copyright."
        echo ""
        echo " Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent"
        echo " permitted by applicable law."
    } > "$MOTD_OUT"

    # 2. 如果存在用户自定义配置文件，则进行“HTML式”合理解释
    # 默认检查路径: /etc/motd.custom
    local CUSTOM_CONF="${MOTD_CONFIG:-/etc/motd.custom}"
    if [ -f "$CUSTOM_CONF" ]; then
        echo ">> Interpreting custom MOTD configuration from $CUSTOM_CONF..."
        local TEMP_MOTD=$(mktemp)
        cp "$CUSTOM_CONF" "$TEMP_MOTD"
        
        # 变量替换逻辑 (符合 HTML 模板原理)
        sed -i "s/{{USER}}/${TARGET_USER}/g" "$TEMP_MOTD"
        sed -i "s/{{HOSTNAME}}/${CUSTOM_HOSTNAME:-$(hostname)}/g" "$TEMP_MOTD"
        sed -i "s/{{OS}}/${OS_VER}/g" "$TEMP_MOTD"
        sed -i "s/{{IP}}/$(hostname -I | awk '{print $1}')/g" "$TEMP_MOTD"
        
        # 如果用户配置文件不为空，则覆盖默认 MOTD
        mv "$TEMP_MOTD" "$MOTD_OUT"
    fi
}

# --- 0. 环境变量与端口配置 ---
SSH_PORT=${SSH_PORT:-22}
TTYA_HTTP_PORT=${TTYA_HTTP_PORT:-8080}
TTYA_HTTPS_PORT=${TTYA_HTTPS_PORT:-8443}
TTYA_TITLE=${TTYA_TITLE:-ttya}

# --- 1. 证书与主机名配置 ---
CERT_FILE="/etc/ssl/certs/ttya.crt"
KEY_FILE="/etc/ssl/private/ttya.key"
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

    # Make the variable available to login shells (e.g. SSH)
    if ! grep -q "^CUSTOM_HOSTNAME=" /etc/environment; then
        echo "CUSTOM_HOSTNAME=${CUSTOM_HOSTNAME}" >> /etc/environment
    fi
fi

# --- 1.8. 自定义软件包安装 ---
if [ -n "$INSTALL_PACKAGES" ]; then
    echo ">> Installing custom packages: ${INSTALL_PACKAGES}..."
    apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10
    apt-get install -y --no-install-recommends ${INSTALL_PACKAGES}
    apt-get clean && rm -rf /var/lib/apt/lists/*
    echo ">> Custom packages installed."
fi

# --- 1.9. 自定义启动脚本 ---
if [ -n "$RUN_SCRIPT" ] && [ -f "$RUN_SCRIPT" ]; then
    echo ">> Executing custom startup script: ${RUN_SCRIPT}..."
    /bin/bash "$RUN_SCRIPT"
    echo ">> Custom startup script finished."
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


# 2.3 自定义环境注入 (CUSTOM_HOSTNAME 等) -> 确保 .bashrc 加载它
if [ -n "$CUSTOM_HOSTNAME" ] || [ -n "$TERM" ]; then
    echo ">> Configuring custom environment for ${TARGET_USER}..."
    ENV_FILE="${USER_HOME}/.custom_env"
    echo "export TERM=xterm-256color" > "${ENV_FILE}"
    if [ -n "$CUSTOM_HOSTNAME" ]; then
        echo "export CUSTOM_HOSTNAME=${CUSTOM_HOSTNAME}" >> "${ENV_FILE}"
    fi
    
    # 确保文件归属正确
    if [ "$TARGET_USER" != "root" ]; then
        chown "${TARGET_USER}:${TARGET_USER}" "${ENV_FILE}"
    fi

    # 注入到 .bashrc (如果尚未存在)
    if ! grep -q ".custom_env" "${USER_HOME}/.bashrc"; then
        echo "" >> "${USER_HOME}/.bashrc"
        echo '# Load custom environment variables' >> "${USER_HOME}/.bashrc"
        echo '[ -f ~/.custom_env ] && . ~/.custom_env' >> "${USER_HOME}/.bashrc"
    fi
fi
if [ -n "$CUSTOM_HOSTNAME" ]; then
    if [[ "${USE_ZSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then
        # For Zsh (Oh My Zsh)
        echo ">> Configuring Zsh prompt for custom hostname..."
        cat >> "${USER_HOME}/.zshrc" <<EOF

# Custom hostname prompt override
if [ -n "\$CUSTOM_HOSTNAME" ]; then
  prompt_context() {
    echo -n "%n@\${CUSTOM_HOSTNAME}"
  }
fi
EOF
    else
        # For Bash
        echo ">> Configuring Bash prompt for custom hostname..."
        cat >> "${USER_HOME}/.bashrc" <<EOF

# Custom hostname prompt override
if [ -n "\$CUSTOM_HOSTNAME" ]; then
    PS1='\${debian_chroot:+(\$debian_chroot)}\[\033[01;32m\]\u@\${CUSTOM_HOSTNAME}\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi
EOF
    fi
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
    echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
fi
if [ -z "$PASSWD" ]; then
    FINAL_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 16)
    echo ">> No password provided. Generated random password for ${TARGET_USER}: ${FINAL_PASSWORD}"
else
    FINAL_PASSWORD="$PASSWD"
    echo ">> Using provided password for ${TARGET_USER}."
fi
echo "${TARGET_USER}:${FINAL_PASSWORD}" | chpasswd
if [ -n "$SSH_PUBKEY" ]; then mkdir -p "${USER_HOME}/.ssh"; echo "${SSH_PUBKEY}" >> "${USER_HOME}/.ssh/authorized_keys"; chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.ssh"; chmod 700 "${USER_HOME}/.ssh"; chmod 600 "${USER_HOME}/.ssh/authorized_keys"; fi

# 2.9 确保 .bashrc 被加载 (修复 runuser -l 可能跳过 .bashrc 的问题)
if [ ! -f "${USER_HOME}/.profile" ]; then
    echo ">> Creating default .profile for ${TARGET_USER}..."
    echo 'if [ -n "$BASH_VERSION" ]; then [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"; fi' > "${USER_HOME}/.profile"
    chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.profile"
else
    # 简单的幂等性检查：如果 .profile 里没有 source bashrc 的逻辑，追加它
    if ! grep -q ".bashrc" "${USER_HOME}/.profile"; then
        echo ">> Appending .bashrc sourcing to .profile..."
        echo 'if [ -n "$BASH_VERSION" ]; then [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"; fi' >> "${USER_HOME}/.profile"
    fi
fi


# --- 3. 服务配置与启动 ---
# 3.0 配置 MOTD 环境变量
# 将 MOTD 变量写入全局环境，以便 /etc/profile 中的 motd_gen.sh 能读取到
if [ -n "$MOTD" ]; then
    if ! grep -q "^MOTD=" /etc/environment; then
        echo "MOTD=${MOTD}" >> /etc/environment
    fi
fi
# 3.1 SSH 配置
sed -i "s/^#\? *Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
sed -i "s/^#\? *PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config
if [ "$TARGET_USER" != "root" ]; then
    sed -i "/^AllowUsers/d" /etc/ssh/sshd_config
    echo "AllowUsers ${TARGET_USER}" >> /etc/ssh/sshd_config
fi

# 3.3 核心服务启动
echo ">> Starting core services..."

# 根据 WEB_TERMINAL 变量决定是否启动 ttya
if [[ ! "${WEB_TERMINAL}" =~ ^([fF][aA][lL][sS][eE]|0|[nN][oO])$ ]]; then
    echo ">> Starting Web Terminal (ttya)..."
    
    # 诊断性信息
    echo ">> Current environment check:"
    id
    ls -l /usr/local/bin/ttya
    
    TTYA_OPTS=()
    [ -n "$TTYA_TITLE" ] && TTYA_OPTS+=("-L" "${TTYA_TITLE}")
    [ -n "$TTYA_FONT_SIZE" ] && TTYA_OPTS+=("-t" "fontSize=${TTYA_FONT_SIZE}")

    # 构建终端启动命令：改回 runuser -l 以防止 login 卡死
    # 配合 /etc/profile 中的 MOTD 打印和 .profile 修复，效果与 login 一致但更稳定
    TERM_CMD=("runuser" "-l" "$TARGET_USER")

    # 启动 HTTP 终端
    echo ">> ttya command (HTTP): ttya -W -p ${TTYA_HTTP_PORT} -c ${TARGET_USER}:**** ${TTYA_OPTS[@]} ${TERM_CMD[@]}"
    ttya -W -p "${TTYA_HTTP_PORT}" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${TTYA_OPTS[@]}" "${TERM_CMD[@]}" &
    
    # 启动 HTTPS 终端
    ttya -W -p "${TTYA_HTTPS_PORT}" --ssl --ssl-cert "$CERT_FILE" --ssl-key "$KEY_FILE" -c "${TARGET_USER}:${FINAL_PASSWORD}" "${TTYA_OPTS[@]}" "${TERM_CMD[@]}" &
    
    echo ">> Web Terminal (ttya) background processes started."
else
    echo ">> Web Terminal (ttya) is disabled."
fi

if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then 
    echo ">> Starting SSH server..."
    /usr/sbin/sshd -D & 
fi

# --- 4. 日志 ---

echo ">> Services are listening on:"
if [[ ! "${WEB_TERMINAL}" =~ ^([fF][aA][lL][sS][eE]|0|[nN][oO])$ ]]; then
    echo "    - Web Terminal (HTTP):  ${TTYA_HTTP_PORT}"
    echo "    - Web Terminal (HTTPS): ${TTYA_HTTPS_PORT}"
    if [ -n "$TTYA_TITLE" ]; then
        echo "    - Terminal Title:       ${TTYA_TITLE}"
    fi
fi
if [[ "${SSH}" =~ ^([yY][eE][sS]|[tT][rR][uU][eE]|1)$ ]]; then 
    echo "    - SSH:                  ${SSH_PORT}"
fi

trap 'kill $(jobs -p)' SIGTERM
wait -n
