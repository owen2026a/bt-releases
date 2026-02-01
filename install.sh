#!/bin/bash
# BT Panel 安装脚本
# 用法: curl -sSL https://raw.githubusercontent.com/owen2026a/bt-releases/main/install.sh | sudo bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 配置
APP_DIR="/www/bt"
DATA_DIR="/www/bt/data"
BACKUP_DIR="/www/bt/backup"
BINARY_PATH="/www/bt/bt"
SERVICE_NAME="bt"
VERSION_URL="https://raw.githubusercontent.com/owen2026a/bt-releases/main/version.json"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}       BT Panel 安装脚本${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用 root 用户运行此脚本${NC}"
    echo "使用方法: sudo bash install.sh"
    exit 1
fi

# 检查系统
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}错误: 不支持的操作系统${NC}"
    exit 1
fi

. /etc/os-release
echo -e "${GREEN}检测到系统: ${ID} ${VERSION_ID}${NC}"

# 创建目录
echo -e "${YELLOW}创建应用目录...${NC}"
mkdir -p "$APP_DIR" "$DATA_DIR" "$BACKUP_DIR"
chmod 700 "$APP_DIR" "$DATA_DIR" "$BACKUP_DIR"
chown root:root "$APP_DIR" "$DATA_DIR" "$BACKUP_DIR"

# 获取版本信息
echo -e "${YELLOW}获取最新版本信息...${NC}"
VERSION_INFO=$(curl -s "$VERSION_URL")
if [ -z "$VERSION_INFO" ]; then
    echo -e "${RED}错误: 无法获取版本信息${NC}"
    exit 1
fi

LATEST_VERSION=$(echo "$VERSION_INFO" | grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
DOWNLOAD_URL=$(echo "$VERSION_INFO" | grep -o '"download_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
CHECKSUM=$(echo "$VERSION_INFO" | grep -o '"checksum"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)
TEMPLATES_URL=$(echo "$VERSION_INFO" | grep -o '"templates_url"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)

echo -e "${GREEN}最新版本: ${LATEST_VERSION}${NC}"

# 下载程序
echo -e "${YELLOW}下载程序文件...${NC}"
TMP_FILE="/tmp/bt_download"
curl -L -o "$TMP_FILE" "$DOWNLOAD_URL"

# 下载模板文件
echo -e "${YELLOW}下载模板文件...${NC}"
TEMPLATES_TAR="/tmp/bt_templates.tar.gz"
if [ -n "$TEMPLATES_URL" ]; then
    curl -L -o "$TEMPLATES_TAR" "$TEMPLATES_URL"
fi

if [ ! -f "$TMP_FILE" ]; then
    echo -e "${RED}错误: 下载失败${NC}"
    exit 1
fi

# 校验文件
if [ -n "$CHECKSUM" ]; then
    echo -e "${YELLOW}校验文件完整性...${NC}"
    EXPECTED_HASH=$(echo "$CHECKSUM" | sed 's/sha256://')
    ACTUAL_HASH=$(sha256sum "$TMP_FILE" | awk '{print $1}')
    
    if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
        echo -e "${RED}错误: 文件校验失败${NC}"
        echo "期望: $EXPECTED_HASH"
        echo "实际: $ACTUAL_HASH"
        rm -f "$TMP_FILE"
        exit 1
    fi
    echo -e "${GREEN}文件校验通过${NC}"
fi

# 停止现有服务
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "${YELLOW}停止现有服务...${NC}"
    systemctl stop "$SERVICE_NAME"
fi

# 备份旧版本
if [ -f "$BINARY_PATH" ]; then
    echo -e "${YELLOW}备份旧版本...${NC}"
    OLD_VERSION=$("$BINARY_PATH" -version 2>/dev/null || echo "unknown")
    cp "$BINARY_PATH" "$BACKUP_DIR/bt_${OLD_VERSION}_$(date +%Y%m%d%H%M%S)"
fi

# 安装新版本
echo -e "${YELLOW}安装新版本...${NC}"
mv "$TMP_FILE" "$BINARY_PATH"
chmod 755 "$BINARY_PATH"
chown root:root "$BINARY_PATH"

# 安装模板文件
if [ -f "$TEMPLATES_TAR" ]; then
    echo -e "${YELLOW}安装模板文件...${NC}"
    rm -rf "$APP_DIR/templates"
    tar -xzf "$TEMPLATES_TAR" -C "$APP_DIR"
    chown -R root:root "$APP_DIR/templates"
    chmod -R 755 "$APP_DIR/templates"
    rm -f "$TEMPLATES_TAR"
fi

# 创建 systemd 服务
echo -e "${YELLOW}配置 systemd 服务...${NC}"
cat > /etc/systemd/system/bt.service << 'EOF'
[Unit]
Description=BT Panel - Server Management Panel
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/www/bt
ExecStart=/www/bt/bt
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

# 环境变量
Environment=PORT=8099

[Install]
WantedBy=multi-user.target
EOF

# 重载 systemd
systemctl daemon-reload

# 启动服务
echo -e "${YELLOW}启动服务...${NC}"
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# 等待服务启动
sleep 3

# 检查服务状态
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}       安装完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "版本: ${GREEN}${LATEST_VERSION}${NC}"
    echo -e "访问地址: ${GREEN}https://服务器IP:8099${NC}"
    echo ""
    echo -e "默认账号: ${YELLOW}admin${NC}"
    echo -e "默认密码: ${YELLOW}admin123${NC}"
    echo ""
    echo -e "${RED}重要: 请立即登录并修改默认密码！${NC}"
    echo ""
    echo "常用命令:"
    echo "  systemctl status bt    # 查看状态"
    echo "  systemctl restart bt   # 重启服务"
    echo "  systemctl stop bt      # 停止服务"
    echo "  journalctl -u bt -f    # 查看日志"
else
    echo -e "${RED}错误: 服务启动失败${NC}"
    echo "请检查日志: journalctl -u bt -n 50"
    exit 1
fi
