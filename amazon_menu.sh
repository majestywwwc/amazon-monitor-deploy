#!/usr/bin/env bash
# Amazon Monitor 管理菜单
# 统一项目目录: /opt/amazon_monitor

set -u

PROJECT_DIR="/opt/amazon_monitor"
INPUT_FILE="$PROJECT_DIR/data/input_asins.xlsx"
IMPORT_SOURCE="/home/ubuntu/input_asins.xlsx"
OUTPUT_DIR="$PROJECT_DIR/output"
DEBUG_DIR="$PROJECT_DIR/debug"
STATE_DIR="$PROJECT_DIR/state"
ARCHIVE_DIR="$PROJECT_DIR/archive"
EXPORT_DIR="/home/ubuntu"

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

compose_cmd() {
    cd "$PROJECT_DIR" || exit 1
    $SUDO docker compose "$@"
}

pause() {
    echo
    read -r -p "按回车继续..."
}

ensure_paths() {
    mkdir -p "$OUTPUT_DIR" "$DEBUG_DIR/worker1" "$DEBUG_DIR/worker2" "$STATE_DIR/worker1" "$STATE_DIR/worker2" "$ARCHIVE_DIR"
    chmod -R 777 "$OUTPUT_DIR" "$DEBUG_DIR" "$STATE_DIR" "$ARCHIVE_DIR" >/dev/null 2>&1 || true
}

check_env() {
    echo "========== 环境检查 =========="
    echo "项目目录: $PROJECT_DIR"
    echo "当前输入文件: $INPUT_FILE"
    echo "导入源文件: $IMPORT_SOURCE"
    echo

    if [ ! -d "$PROJECT_DIR" ]; then
        echo "[失败] 项目目录不存在"
        return 1
    fi

    if [ ! -f "$PROJECT_DIR/compose.yaml" ]; then
        echo "[失败] compose.yaml 不存在"
        return 1
    fi

    if [ ! -f "$PROJECT_DIR/amazon_asin_monitor.py" ]; then
        echo "[失败] amazon_asin_monitor.py 不存在"
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo "[失败] docker 未安装"
        return 1
    fi

    echo "[成功] docker 已安装: $(docker --version 2>/dev/null)"
    echo "[成功] compose 版本: $(docker compose version 2>/dev/null)"

    if [ -f "$INPUT_FILE" ]; then
        echo "[成功] 当前输入文件存在"
    else
        echo "[提示] 当前输入文件不存在: $INPUT_FILE"
    fi

    if [ -f "$IMPORT_SOURCE" ]; then
        echo "[成功] 可导入源文件存在"
    else
        echo "[提示] 可导入源文件不存在: $IMPORT_SOURCE"
    fi

    echo
    return 0
}

backup_old_outputs() {
    ensure_paths
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local backed_up=0

    for f in "$OUTPUT_DIR"/result_worker*.xlsx; do
        if [ -f "$f" ]; then
            cp "$f" "$ARCHIVE_DIR/$(basename "${f%.xlsx}")_${ts}.xlsx"
            backed_up=1
        fi
    done

    if [ "$backed_up" -eq 1 ]; then
        echo "[信息] 已备份旧输出到: $ARCHIVE_DIR"
    else
        echo "[信息] 没有旧输出需要备份"
    fi
}

start_workers() {
    echo "========== 启动双 worker =========="
    check_env || return 1
    ensure_paths

    if [ ! -f "$INPUT_FILE" ]; then
        echo "[失败] 输入文件不存在，无法启动"
        return 1
    fi

    backup_old_outputs

    echo "[步骤] 停止旧容器..."
    compose_cmd down

    echo "[步骤] 启动双 worker..."
    compose_cmd up -d

    echo "[完成] 双 worker 已启动"
}

rebuild_and_start() {
    echo "========== 重建镜像并启动双 worker =========="
    check_env || return 1
    ensure_paths

    if [ ! -f "$INPUT_FILE" ]; then
        echo "[失败] 输入文件不存在，无法启动"
        return 1
    fi

    backup_old_outputs

    echo "[步骤] 停止旧容器..."
    compose_cmd down

    echo "[步骤] 重建镜像（可能需要几分钟）..."
    compose_cmd build --no-cache

    echo "[步骤] 启动双 worker..."
    compose_cmd up -d

    echo "[完成] 重建并启动完成"
}

stop_workers() {
    echo "========== 停止任务 =========="
    compose_cmd down
    echo "[完成] 已停止"
}

show_status() {
    echo "========== 当前状态 =========="
    compose_cmd ps
    echo
    echo "========== 输出文件 =========="
    ls -lh "$OUTPUT_DIR" 2>/dev/null || true
}

show_worker1_logs() {
    echo "========== worker1 日志 =========="
    compose_cmd logs -f worker1
}

show_worker2_logs() {
    echo "========== worker2 日志 =========="
    compose_cmd logs -f worker2
}

show_outputs() {
    echo "========== 输出目录 =========="
    ls -lh "$OUTPUT_DIR" 2>/dev/null || true
    echo
    echo "========== 归档目录 =========="
    ls -lh "$ARCHIVE_DIR" 2>/dev/null || true
}

package_outputs() {
    ensure_paths
    local ts pkg_file
    ts="$(date +%Y%m%d_%H%M%S)"
    pkg_file="$EXPORT_DIR/amazon_outputs_${ts}.tar.gz"

    if ls "$OUTPUT_DIR"/result_worker*.xlsx >/dev/null 2>&1; then
        tar czf "$pkg_file" -C "$OUTPUT_DIR" .
        echo "[完成] 已打包输出结果到: $pkg_file"
        ls -lh "$pkg_file" 2>/dev/null || true
    else
        echo "[提示] 当前没有可打包的输出文件"
    fi
}

import_asin_file() {
    echo "========== 导入ASIN文件 =========="

    if [ ! -f "$IMPORT_SOURCE" ]; then
        echo "[失败] 没找到导入源文件: $IMPORT_SOURCE"
        return 1
    fi

    mkdir -p "$PROJECT_DIR/data"

    cp "$IMPORT_SOURCE" "$INPUT_FILE"

    echo "[完成] 已导入输入文件"
    echo "来源: $IMPORT_SOURCE"
    echo "目标: $INPUT_FILE"
    ls -lh "$INPUT_FILE" 2>/dev/null || true
}

menu() {
    clear
    echo "=========================================="
    echo " Amazon 监控系统菜单"
    echo " 项目目录: $PROJECT_DIR"
    echo "=========================================="
    echo "1. 检查环境"
    echo "2. 启动双 worker"
    echo "3. 重建镜像并启动双 worker"
    echo "4. 停止任务"
    echo "5. 查看运行状态"
    echo "6. 查看 worker1 日志"
    echo "7. 查看 worker2 日志"
    echo "8. 查看输出文件"
    echo "9. 打包输出结果到 /home/ubuntu"
    echo "10. 导入ASIN文件"
    echo "0. 退出"
    echo "=========================================="
}

while true; do
    menu
    read -r -p "请输入选项编号: " choice
    echo

    case "$choice" in
        1)
            check_env
            pause
            ;;
        2)
            start_workers
            pause
            ;;
        3)
            rebuild_and_start
            pause
            ;;
        4)
            stop_workers
            pause
            ;;
        5)
            show_status
            pause
            ;;
        6)
            show_worker1_logs
            ;;
        7)
            show_worker2_logs
            ;;
        8)
            show_outputs
            pause
            ;;
        9)
            package_outputs
            pause
            ;;
        10)
            import_asin_file
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
