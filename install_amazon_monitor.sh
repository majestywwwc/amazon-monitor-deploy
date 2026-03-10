#!/usr/bin/env bash
# Amazon Monitor 一键安装 / 更新脚本
# 统一安装到 /opt/amazon_monitor

set -Eeuo pipefail

REPO_OWNER="majestywwwc"
REPO_NAME="amazon-monitor-deploy"
RELEASE_FILE="amazon_monitor_release.tar.gz"
RELEASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${RELEASE_FILE}"

INSTALL_DIR="/opt/amazon_monitor"
TMP_DIR="/tmp/amazon_monitor_install_$$"

CURRENT_USER="${SUDO_USER:-$USER}"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

cleanup() {
    rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

msg() {
    echo
    echo "=========================================="
    echo "$1"
    echo "=========================================="
}

pause() {
    echo
    read -r -p "按回车继续..."
}

normalize_shell_files() {
    local dir="$1"
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
        find "$dir" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    fi
}

install_docker() {
    msg "安装 Docker"

    $SUDO apt update
    $SUDO apt install -y ca-certificates curl

    # 清理旧配置，避免 signed-by 冲突
    $SUDO rm -f /etc/apt/sources.list.d/docker.list
    $SUDO rm -f /etc/apt/sources.list.d/docker.sources
    $SUDO rm -f /etc/apt/keyrings/docker.asc
    $SUDO rm -f /etc/apt/keyrings/docker.gpg

    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    $SUDO mv /tmp/docker.asc /etc/apt/keyrings/docker.asc
    $SUDO chmod a+r /etc/apt/keyrings/docker.asc

    $SUDO tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    $SUDO apt update
    $SUDO apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    $SUDO systemctl enable docker
    $SUDO systemctl start docker

    if ! getent group docker >/dev/null 2>&1; then
        $SUDO groupadd docker
    fi

    $SUDO usermod -aG docker "$CURRENT_USER" || true

    echo "[完成] Docker 已安装"
    $SUDO docker --version || true
    $SUDO docker compose version || true

    echo
    echo "[提示] 如果你当前用户刚加入 docker 组，重新登录 SSH 一次会更稳。"
}

deploy_release() {
    msg "下载并部署最新发布包"

    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"

    curl -L --fail -o "$RELEASE_FILE" "$RELEASE_URL"

    if [ ! -f "$RELEASE_FILE" ]; then
        echo "[失败] 发布包下载失败"
        exit 1
    fi

    tar xzf "$RELEASE_FILE"

    local package_root=""
    if [ -d "$TMP_DIR/amazon_monitor" ]; then
        package_root="$TMP_DIR/amazon_monitor"
    else
        package_root="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1 || true)"
        if [ -z "$package_root" ]; then
            package_root="$TMP_DIR"
        fi
    fi

    $SUDO mkdir -p "$INSTALL_DIR"
    $SUDO mkdir -p "$INSTALL_DIR/data"
    $SUDO mkdir -p "$INSTALL_DIR/output"
    $SUDO mkdir -p "$INSTALL_DIR/debug/worker1"
    $SUDO mkdir -p "$INSTALL_DIR/debug/worker2"
    $SUDO mkdir -p "$INSTALL_DIR/state/worker1"
    $SUDO mkdir -p "$INSTALL_DIR/state/worker2"
    $SUDO mkdir -p "$INSTALL_DIR/archive"

    # 核心文件覆盖更新
    for f in amazon_asin_monitor.py Dockerfile compose.yaml requirements.txt amazon_menu.sh README.md; do
        if [ -f "$package_root/$f" ]; then
            $SUDO cp "$package_root/$f" "$INSTALL_DIR/"
        fi
    done

    # 输入文件：如果现场已有 input_asins.xlsx，就保留；没有才从包里复制
    if [ ! -f "$INSTALL_DIR/data/input_asins.xlsx" ] && [ -f "$package_root/data/input_asins.xlsx" ]; then
        $SUDO cp "$package_root/data/input_asins.xlsx" "$INSTALL_DIR/data/"
    fi

    # 如果以后放模板，也会顺手复制
    if [ -f "$package_root/data/input_asins_template.xlsx" ]; then
        $SUDO cp "$package_root/data/input_asins_template.xlsx" "$INSTALL_DIR/data/" || true
    fi

    # 修复 shell 文件换行符并赋执行权限
    $SUDO bash -c "find '$INSTALL_DIR' -type f -name '*.sh' -exec sed -i 's/\r$//' {} \; 2>/dev/null || true"
    $SUDO bash -c "find '$INSTALL_DIR' -type f -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true"

    $SUDO chmod -R 777 "$INSTALL_DIR/output" "$INSTALL_DIR/debug" "$INSTALL_DIR/state" "$INSTALL_DIR/archive" || true
    $SUDO chown -R "$CURRENT_USER":"$CURRENT_USER" "$INSTALL_DIR" || true

    echo "[完成] 已部署到: $INSTALL_DIR"
}

show_next_steps() {
    msg "安装完成"
    echo "项目目录:"
    echo "  $INSTALL_DIR"
    echo
    echo "下一步:"
    echo "  cd $INSTALL_DIR"
    echo "  ./amazon_menu.sh"
    echo
    echo "如果刚装完 Docker，重新登录 SSH 一次更稳。"
}

main_menu() {
    clear
    echo "=========================================="
    echo " Amazon Monitor 安装 / 更新脚本"
    echo " 安装目录: $INSTALL_DIR"
    echo " 发布地址: $RELEASE_URL"
    echo "=========================================="
    echo "1. 只安装 Docker"
    echo "2. 只下载并部署最新发布包"
    echo "3. 安装 Docker + 下载并部署最新发布包"
    echo "0. 退出"
    echo "=========================================="
}

while true; do
    main_menu
    read -r -p "请输入选项编号: " choice
    echo

    case "$choice" in
        1)
            install_docker
            show_next_steps
            pause
            ;;
        2)
            deploy_release
            show_next_steps
            pause
            ;;
        3)
            install_docker
            deploy_release
            show_next_steps
            pause
            ;;
        0)
            echo "已退出"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入"
            pause
            ;;
    esac
done
