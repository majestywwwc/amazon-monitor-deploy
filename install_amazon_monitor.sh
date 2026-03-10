#!/usr/bin/env bash
# Amazon Monitor 一键安装脚本
# 用于全新 Ubuntu 服务器
# 会安装 Docker，下载最新发布包，解压部署

set -e

REPO_OWNER="majestywwwc"
REPO_NAME="amazon-monitor-deploy"
RELEASE_FILE="amazon_monitor_release.tar.gz"

RELEASE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download/${RELEASE_FILE}"

INSTALL_BASE="/home/${USER}"
INSTALL_DIR="${INSTALL_BASE}/amazon_monitor_release"

echo "=========================================="
echo " Amazon Monitor 一键安装脚本"
echo "=========================================="
echo "当前用户: ${USER}"
echo "安装目录: ${INSTALL_DIR}"
echo "发布包地址: ${RELEASE_URL}"
echo "=========================================="
echo

if [ "$(id -u)" -eq 0 ]; then
    echo "请不要直接用 root 运行这个脚本。"
    echo "请使用你的普通用户运行，例如 amazon_a。"
    exit 1
fi

sudo -v

install_docker() {
    echo "========== 安装 Docker =========="

    sudo apt update
    sudo apt install -y ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    sudo mv /tmp/docker.asc /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl start docker

    if ! getent group docker >/dev/null 2>&1; then
        sudo groupadd docker
    fi

    sudo usermod -aG docker "$USER"

    echo
    echo "[完成] Docker 安装成功"
    docker --version || true
    sudo docker compose version || true
    echo
    echo "[提示] 组权限刚刚更新。安装完成后请重新登录 SSH 一次，再继续用 docker。"
}

download_and_extract() {
    echo "========== 下载并部署最新发布包 =========="

    mkdir -p "${INSTALL_BASE}"
    cd "${INSTALL_BASE}"

    rm -f "${RELEASE_FILE}"
    curl -L -o "${RELEASE_FILE}" "${RELEASE_URL}"

    if [ ! -f "${RELEASE_FILE}" ]; then
        echo "[失败] 发布包下载失败"
        exit 1
    fi

    echo "[完成] 发布包下载成功：${INSTALL_BASE}/${RELEASE_FILE}"

    rm -rf "${INSTALL_DIR}"
    tar xzf "${RELEASE_FILE}"

    # 自动兼容 pkg 目录名
    if [ -d "${INSTALL_BASE}/amazon_monitor_release_pkg" ]; then
        mv "${INSTALL_BASE}/amazon_monitor_release_pkg" "${INSTALL_DIR}"
    fi

    if [ ! -d "${INSTALL_DIR}" ]; then
        echo "[失败] 解压后没有找到安装目录"
        exit 1
    fi

    mkdir -p "${INSTALL_DIR}/output"
    mkdir -p "${INSTALL_DIR}/debug/worker1"
    mkdir -p "${INSTALL_DIR}/debug/worker2"
    mkdir -p "${INSTALL_DIR}/state/worker1"
    mkdir -p "${INSTALL_DIR}/state/worker2"

    chmod -R 777 "${INSTALL_DIR}/output" "${INSTALL_DIR}/debug" "${INSTALL_DIR}/state" || true

    echo "[完成] 已部署到：${INSTALL_DIR}"
}

show_next_steps() {
    echo
    echo "=========================================="
    echo " 安装完成"
    echo "=========================================="
    echo "下一步："
    echo "1. 重新登录 SSH（很重要，刷新 docker 组权限）"
    echo "2. 进入目录："
    echo "   cd ${INSTALL_DIR}"
    echo "3. 运行菜单："
    echo "   ./amazon_menu.sh"
    echo "=========================================="
}

main() {
    echo "请选择操作："
    echo "1. 只安装 Docker"
    echo "2. 只下载并部署最新发布包"
    echo "3. 安装 Docker + 下载并部署最新发布包"
    echo "0. 退出"
    echo
    read -r -p "请输入选项编号: " choice
    echo

    case "$choice" in
        1)
            install_docker
            show_next_steps
            ;;
        2)
            download_and_extract
            show_next_steps
            ;;
        3)
            install_docker
            download_and_extract
            show_next_steps
            ;;
        0)
            echo "已退出"
            exit 0
            ;;
        *)
            echo "无效选项"
            exit 1
            ;;
    esac
}

main