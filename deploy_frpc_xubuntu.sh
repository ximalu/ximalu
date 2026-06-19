#!/bin/bash
# deploy_frpc_xubuntu.sh — 一键在 Xubuntu 上部署 frpc 客户端，通过 frp 隧道远程 SSH 管理
# 用法: curl -s https://raw.githubusercontent.com/ximalu/ximalu/main/deploy_frpc_xubuntu.sh | bash
# 注意：需要 sudo 权限，运行时会问一次密码

set -euo pipefail

# ============================================================
# 配置（已预设，直接运行即可）
# ============================================================
SERVER_ADDR="124.222.120.126"
SERVER_PORT="7000"
AUTH_TOKEN="jNsxN23Io89r69F7LqvkQfx9bB5jAq9OIzAFOvepyF65XKO8xESRfmbaUpwGmzDl"
REMOTE_SSH_PORT="10023"           # 远程 SSH 端口（10022 已被路由器占用）
LOCAL_SSH_PORT="22"
FRP_VERSION="0.69.1"              # 与服务端版本一致
# ============================================================

# 检查 root
if [ "$EUID" -ne 0 ]; then
    echo "请以 root 身份运行（sudo !!）"
    exit 1
fi

echo "========================================"
echo "  Xubuntu frpc 一键部署"
echo "  服务器: ${SERVER_ADDR}:${SERVER_PORT}"
echo "  远程SSH端口: ${REMOTE_SSH_PORT}"
echo "========================================"

# 1. 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  FRP_ARCH="amd64" ;;
    aarch64) FRP_ARCH="arm64" ;;
    armv7l)  FRP_ARCH="arm" ;;
    *)
        echo "不支持的架构: $ARCH"
        exit 1
        ;;
esac
echo "[1/5] 架构: ${ARCH} → frp_linux_${FRP_ARCH}"

# 2. 下载 frp
INSTALL_DIR="/opt/frp"
FRP_FILE="frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_FILE}"

if [ -f "$INSTALL_DIR/frpc" ] && [ "$($INSTALL_DIR/frpc --version 2>/dev/null)" == "$FRP_VERSION" ]; then
    echo "[2/5] frpc v${FRP_VERSION} 已安装，跳过下载"
else
    echo "[2/5] 下载 frp v${FRP_VERSION}..."
    if command -v curl &>/dev/null; then
        curl -L -o "/tmp/${FRP_FILE}" "$DOWNLOAD_URL"
    elif command -v wget &>/dev/null; then
        wget -O "/tmp/${FRP_FILE}" "$DOWNLOAD_URL"
    else
        echo "需要 curl 或 wget"
        exit 1
    fi
    echo "解压到 ${INSTALL_DIR}..."
    mkdir -p "$INSTALL_DIR"
    tar -xzf "/tmp/${FRP_FILE}" -C "/tmp/"
    cp "/tmp/frp_${FRP_VERSION}_linux_${FRP_ARCH}/frpc" "$INSTALL_DIR/frpc"
    chmod +x "$INSTALL_DIR/frpc"
    rm -rf "/tmp/${FRP_FILE}" "/tmp/frp_${FRP_VERSION}_linux_${FRP_ARCH}"
    echo "frpc 安装完成"
fi

# 3. 创建 frpc 配置
echo "[3/5] 创建 frpc 配置文件..."
mkdir -p /etc/frp
cat > /etc/frp/frpc.toml <<EOF
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}

auth.method = "token"
auth.token = "${AUTH_TOKEN}"

log.to = "console"
log.level = "info"

[[proxies]]
name = "xubuntu-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${LOCAL_SSH_PORT}
remotePort = ${REMOTE_SSH_PORT}
EOF
echo "    /etc/frp/frpc.toml 已创建"

# 4. 创建 systemd 服务
echo "[4/5] 创建 systemd 服务..."
cat > /etc/systemd/system/frpc.service <<'SERVICE'
[Unit]
Description=frp client (Xubuntu)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/opt/frp/frpc -c /etc/frp/frpc.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable frpc
systemctl restart frpc

# 5. 验证
echo "[5/5] 验证服务状态..."
sleep 2
if systemctl is-active --quiet frpc; then
    echo ""
    echo "========================================"
    echo "  ✅ 部署成功！frpc 正在运行"
    echo "  远程管理命令："
    echo "    ssh -p ${REMOTE_SSH_PORT} your_user@${SERVER_ADDR}"
    echo "========================================"
    systemctl status frpc --no-pager -l | head -8
else
    echo "❌ 启动失败，查看日志："
    journalctl -u frpc --no-pager -n 20
    exit 1
fi
