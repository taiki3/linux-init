#!/usr/bin/env bash
set -euo pipefail

TARGET_USER="yoshinaka"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEtSn9l9+s7fheMDXKZV3QC8333CQyq3h3SDCFNcnWC0 yoshinaka_ED25519"

# root権限でない場合はsudoで再実行
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        echo "[INFO] Elevating privileges with sudo..."
        exec sudo bash "$0" "$@"
    else
        echo "[ERROR] This script must be run as root (and sudo is not installed)." >&2
        exit 1
    fi
fi

echo "==> Starting user initialization for '${TARGET_USER}'..."

# 1. 必須パッケージ (sudo, curl, ca-certificates, tar) の確認・インストール
MISSING_PKGS=()
command -v sudo >/dev/null 2>&1 || MISSING_PKGS+=(sudo)
command -v curl >/dev/null 2>&1 || MISSING_PKGS+=(curl ca-certificates)
command -v tar  >/dev/null 2>&1 || MISSING_PKGS+=(tar)

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    echo "==> Installing required packages: ${MISSING_PKGS[*]}..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y "${MISSING_PKGS[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "${MISSING_PKGS[@]}"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "${MISSING_PKGS[@]}"
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm "${MISSING_PKGS[@]}"
    elif command -v zypper >/dev/null 2>&1; then
        zypper --non-interactive install "${MISSING_PKGS[@]}"
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache "${MISSING_PKGS[@]}"
    else
        echo "[ERROR] Could not find a supported package manager to install: ${MISSING_PKGS[*]}" >&2
        exit 1
    fi
fi

# 2. ユーザー作成
DEFAULT_SHELL="/bin/bash"
if [[ ! -x "$DEFAULT_SHELL" ]]; then
    DEFAULT_SHELL="/bin/sh"
fi

if id "$TARGET_USER" >/dev/null 2>&1; then
    echo "==> User '${TARGET_USER}' already exists. Updating configuration..."
    usermod -s "$DEFAULT_SHELL" "$TARGET_USER" || true
else
    echo "==> Creating user '${TARGET_USER}'..."
    useradd -m -s "$DEFAULT_SHELL" "$TARGET_USER"
    # パスワードログインを無効化しつつアカウントロック(!)によるSSH拒否を回避
    usermod -p '*' "$TARGET_USER" || true
fi

# sudo / wheel グループが存在すれば追加
if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$TARGET_USER"
fi
if getent group wheel >/dev/null 2>&1; then
    usermod -aG wheel "$TARGET_USER"
fi

# 3. パスワードなしsudo設定 (/etc/sudoers.d/)
echo "==> Configuring passwordless sudo..."
mkdir -p /etc/sudoers.d
SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}"
echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
chown root:root "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

if command -v visudo >/dev/null 2>&1; then
    if ! visudo -cf "$SUDOERS_FILE" >/dev/null; then
        rm -f "$SUDOERS_FILE"
        echo "[ERROR] Failed to validate sudoers file." >&2
        exit 1
    fi
fi

# 4. SSH公開鍵の設定
echo "==> Configuring SSH authorized_keys..."
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$USER_HOME" ]]; then
    USER_HOME="/home/${TARGET_USER}"
fi

SSH_DIR="${USER_HOME}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

mkdir -p "$SSH_DIR"
touch "$AUTH_KEYS"

# 公開鍵の本体部分(2フィールド目)で重複チェックして追加
PUBKEY_BODY="$(echo "$SSH_PUBKEY" | awk '{print $2}')"
if ! grep -qF "$PUBKEY_BODY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$SSH_PUBKEY" >> "$AUTH_KEYS"
    echo "    Added SSH public key."
else
    echo "    SSH public key already registered."
fi

chmod 700 "$SSH_DIR"
chmod 600 "$AUTH_KEYS"
chown -R "${TARGET_USER}:${TARGET_USER}" "$SSH_DIR"

# SELinux環境(RHEL系など)の場合にコンテキストを修復
if command -v restorecon >/dev/null 2>&1; then
    restorecon -Rv "$SSH_DIR" >/dev/null 2>&1 || true
fi

# 5. ~/.local/bin の PATH 設定
echo "==> Ensuring ~/.local/bin is in PATH..."
mkdir -p "${USER_HOME}/.local/bin"
chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.local"

for rc_file in "${USER_HOME}/.bashrc" "${USER_HOME}/.profile"; do
    touch "$rc_file"
    if ! grep -qF '.local/bin' "$rc_file" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$rc_file"
    fi
    chown "${TARGET_USER}:${TARGET_USER}" "$rc_file"
done

# 6. Herdr のインストール
echo "==> Installing Herdr for '${TARGET_USER}'..."
su - "$TARGET_USER" -c 'export PATH="$HOME/.local/bin:$PATH"; curl -fsSL https://herdr.dev/install.sh | sh'

# 7. Claude Code のインストール
echo "==> Installing Claude Code for '${TARGET_USER}'..."
su - "$TARGET_USER" -c 'export PATH="$HOME/.local/bin:$PATH"; curl -fsSL https://claude.ai/install.sh | bash'

# 8. OOM・ハング防止設定 (ユニファイドメモリ / LLMクラスタ環境向け)
echo "==> Configuring OOM & hang protection (earlyoom, sysctl, sshd OOM guard)..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get install -y earlyoom || true
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y earlyoom || true
fi

if command -v earlyoom >/dev/null 2>&1; then
    cat > /etc/default/earlyoom <<'EOF'
EARLYOOM_ARGS="-m 2,1 -s 100,100 -r 60 --avoid '(^|/)(init|systemd|sshd|herdr|bash|tmux|dockerd|containerd)$' --prefer '(^|/)(tf-dsv41|tensorfold|vllm|python|python3|zig)'"
EOF
    systemctl enable --now earlyoom >/dev/null 2>&1 || true
    systemctl restart earlyoom >/dev/null 2>&1 || true
fi

cat > /etc/sysctl.d/99-hang-protection.conf <<'EOF'
vm.admin_reserve_kbytes = 524288
vm.swappiness = 1
kernel.panic = 10
kernel.panic_on_oops = 1
kernel.softlockup_panic = 1
kernel.hung_task_panic = 1
kernel.hung_task_timeout_secs = 60
EOF
sysctl --system >/dev/null 2>&1 || true

mkdir -p /etc/systemd/system/ssh.service.d
cat > /etc/systemd/system/ssh.service.d/oom-protect.conf <<'EOF'
[Service]
OOMScoreAdjust=-1000
EOF
systemctl daemon-reload >/dev/null 2>&1 || true

echo "==> Done! Setup summary:"
echo "    User        : ${TARGET_USER}"
echo "    Home        : ${USER_HOME}"
echo "    Sudoers     : ${SUDOERS_FILE} (NOPASSWD)"
echo "    Auth Keys   : ${AUTH_KEYS}"
echo "    Herdr       : $(su - "$TARGET_USER" -c 'export PATH="$HOME/.local/bin:$PATH"; command -v herdr || echo "installed in ~/.local/bin"')"
echo "    Claude Code : $(su - "$TARGET_USER" -c 'export PATH="$HOME/.local/bin:$PATH"; command -v claude || echo "installed in ~/.local/bin"')"
