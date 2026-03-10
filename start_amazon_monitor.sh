#!/usr/bin/env bash
# Amazon Monitor 跳板脚本
# 放在 /home/ubuntu/，登录后可直接运行

set -e

PROJECT_DIR="/opt/amazon_monitor"
MENU_SCRIPT="$PROJECT_DIR/amazon_menu.sh"

echo "=========================================="
echo " Amazon Monitor 跳板脚本"
echo "=========================================="
echo "项目目录: $PROJECT_DIR"
echo

if [ ! -d "$PROJECT_DIR" ]; then
    echo "[失败] 项目目录不存在: $PROJECT_DIR"
    exit 1
fi

if [ ! -f "$MENU_SCRIPT" ]; then
    echo "[失败] 菜单脚本不存在: $MENU_SCRIPT"
    exit 1
fi

# 顺手修复菜单脚本换行和执行权限
sed -i 's/\r$//' "$MENU_SCRIPT" 2>/dev/null || true
chmod +x "$MENU_SCRIPT" 2>/dev/null || true

cd "$PROJECT_DIR"
exec bash "$MENU_SCRIPT"
