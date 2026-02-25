#!/bin/bash

# 1. 权限与参数检查
if [ "$EUID" -ne 0 ]; then 
  echo "错误：请以 root 权限运行此脚本 (例如使用 sudo)"
  exit 1
fi

PUBKEY_URL=$1
if [ -z "$PUBKEY_URL" ]; then
  echo "错误：未提供公钥的下载链接。"
  echo "用法示例: curl -sL <脚本地址> | sudo bash -s <公钥地址>"
  exit 1
fi

echo "--- 1. 开始拉取公钥并配置权限 ---"

# 默认将公钥配置给当前执行脚本的用户（通常是 root）
# 如果你需要配置给特定非 root 用户，可以硬编码替换 USER_HOME (如 USER_HOME="/home/ubuntu")
USER_HOME=$HOME  
SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# 从外网拉取公钥并追加到 authorized_keys (避免覆盖已有公钥)
if curl -sSL --fail "$PUBKEY_URL" >> "$AUTH_KEYS"; then
    echo "✅ 公钥成功拉取并写入 $AUTH_KEYS"
else
    echo "❌ 错误：无法从 $PUBKEY_URL 拉取公钥，请检查网络或链接是否正确。"
    exit 1
fi
chmod 600 "$AUTH_KEYS"

echo "--- 2. 开始安全加固 sshd_config ---"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
echo "已备份原始配置至 /etc/ssh/sshd_config.bak"

modify_config() {
    local key=$1
    local value=$2
    if grep -q "^#*$key" /etc/ssh/sshd_config; then
        sed -i "s/^#*$key.*/$key $value/" /etc/ssh/sshd_config
    else
        echo "$key $value" >> /etc/ssh/sshd_config
    fi
}

modify_config "PasswordAuthentication" "no"
modify_config "PubkeyAuthentication" "yes"
modify_config "PermitRootLogin" "prohibit-password" 
# 兼容新老版本 Linux 的交互式认证禁用
modify_config "ChallengeResponseAuthentication" "no"
modify_config "KbdInteractiveAuthentication" "no" 

# 语法检查
if ! sshd -t; then
    echo "❌ 检测到配置语法错误，正在回滚配置..."
    mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    exit 1
fi

echo "--- 3. 重启 SSH 服务 ---"
# 兼容各大发行版的服务重启指令
if systemctl is-active --quiet sshd; then
    systemctl restart sshd
elif systemctl is-active --quiet ssh; then
    systemctl restart ssh
else
    service sshd restart || service ssh restart
fi

echo "🎉 配置完成！密码登录已禁用，现仅支持你提供的公钥登录。"