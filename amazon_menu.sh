#!/usr/bin/env bash
# Amazon Monitor 管理菜单（V1.5 单worker分批版）
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
    mkdir -p "$OUTPUT_DIR" "$OUTPUT_DIR/batches" "$DEBUG_DIR/worker1" "$STATE_DIR/worker1" "$ARCHIVE_DIR"
    chmod -R 777 "$OUTPUT_DIR" "$DEBUG_DIR" "$STATE_DIR" "$ARCHIVE_DIR" >/dev/null 2>&1 || true
}

human_duration() {
    local total_seconds="$1"

    if [ -z "${total_seconds:-}" ] || [ "$total_seconds" -lt 0 ] 2>/dev/null; then
        echo "未知"
        return
    fi

    local days=$((total_seconds / 86400))
    local hours=$(((total_seconds % 86400) / 3600))
    local mins=$(((total_seconds % 3600) / 60))
    local secs=$((total_seconds % 60))

    local result=""
    if [ "$days" -gt 0 ]; then
        result="${result}${days}天"
    fi
    if [ "$hours" -gt 0 ]; then
        result="${result}${hours}小时"
    fi
    if [ "$mins" -gt 0 ]; then
        result="${result}${mins}分"
    fi
    result="${result}${secs}秒"

    echo "$result"
}

show_worker_runtime() {
    local service="$1"
    local container_id=""
    local status=""
    local started_at=""
    local finished_at=""
    local now_ts=""
    local start_ts=""
    local finish_ts=""
    local duration=""

    container_id="$(compose_cmd ps -q "$service" 2>/dev/null | tail -n 1)"

    echo "========== ${service} 运行信息 =========="

    if [ -z "$container_id" ]; then
        echo "状态: 未找到容器"
        echo "用时: 未知"
        echo
        return
    fi

    status="$($SUDO docker inspect -f '{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")"
    started_at="$($SUDO docker inspect -f '{{.State.StartedAt}}' "$container_id" 2>/dev/null || true)"
    finished_at="$($SUDO docker inspect -f '{{.State.FinishedAt}}' "$container_id" 2>/dev/null || true)"

    echo "状态: $status"

    if [ -n "$started_at" ] && [ "$started_at" != "0001-01-01T00:00:00Z" ]; then
        start_ts="$(date -d "$started_at" +%s 2>/dev/null || echo "")"
    else
        start_ts=""
    fi

    if [ "$status" = "running" ]; then
        if [ -n "$start_ts" ]; then
            now_ts="$(date +%s)"
            duration=$((now_ts - start_ts))
            echo "已运行: $(human_duration "$duration")"
        else
            echo "已运行: 未知"
        fi
    elif [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
        if [ -n "$finished_at" ] && [ "$finished_at" != "0001-01-01T00:00:00Z" ]; then
            finish_ts="$(date -d "$finished_at" +%s 2>/dev/null || echo "")"
        else
            finish_ts=""
        fi

        if [ -n "$start_ts" ] && [ -n "$finish_ts" ]; then
            duration=$((finish_ts - start_ts))
            echo "总用时: $(human_duration "$duration")"
        else
            echo "总用时: 未知"
        fi
    else
        if [ -n "$start_ts" ]; then
            now_ts="$(date +%s)"
            duration=$((now_ts - start_ts))
            echo "运行时长: $(human_duration "$duration")"
        else
            echo "运行时长: 未知"
        fi
    fi

    echo
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

    for f in \
        "$OUTPUT_DIR"/final_results.xlsx \
        "$OUTPUT_DIR"/final_results.csv \
        "$OUTPUT_DIR"/failed_asins.csv \
        "$OUTPUT_DIR"/run_summary.json
    do
        if [ -f "$f" ]; then
            cp "$f" "$ARCHIVE_DIR/$(basename "$f")_${ts}"
            backed_up=1
        fi
    done

    if [ "$backed_up" -eq 1 ]; then
        echo "[信息] 已备份旧输出到: $ARCHIVE_DIR"
    else
        echo "[信息] 没有旧输出需要备份"
    fi
}

start_worker() {
    echo "========== 启动单 worker =========="
    check_env || return 1
    ensure_paths

    if [ ! -f "$INPUT_FILE" ]; then
        echo "[失败] 输入文件不存在，无法启动"
        return 1
    fi

    backup_old_outputs

    echo "[步骤] 停止旧容器..."
    compose_cmd down

    echo "[步骤] 启动单 worker..."
    compose_cmd up -d

    echo "[完成] 单 worker 已启动"
}

rebuild_and_start() {
    echo "========== 重建镜像并启动单 worker =========="
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

    echo "[步骤] 启动单 worker..."
    compose_cmd up -d

    echo "[完成] 重建并启动完成"
}

stop_worker() {
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

show_worker_logs() {
    show_worker_runtime "worker1"
    echo "========== worker1 日志 =========="
    compose_cmd logs --tail=200 -f worker1
}

import_input_file() {
    ensure_paths
    echo "========== 导入输入文件 =========="

    if [ ! -f "$IMPORT_SOURCE" ]; then
        echo "[失败] 找不到导入源文件: $IMPORT_SOURCE"
        return 1
    fi

    cp "$IMPORT_SOURCE" "$INPUT_FILE"
    chmod 666 "$INPUT_FILE" >/dev/null 2>&1 || true
    echo "[完成] 已导入到: $INPUT_FILE"
}

export_outputs() {
    ensure_paths
    echo "========== 导出结果 =========="

    local found=0
    for f in \
        "$OUTPUT_DIR/final_results.xlsx" \
        "$OUTPUT_DIR/final_results.csv" \
        "$OUTPUT_DIR/failed_asins.csv" \
        "$OUTPUT_DIR/run_summary.json"
    do
        if [ -f "$f" ]; then
            cp "$f" "$EXPORT_DIR/"
            found=1
        fi
    done

    if [ "$found" -eq 1 ]; then
        chmod 666 "$EXPORT_DIR"/final_results.* "$EXPORT_DIR"/failed_asins.csv "$EXPORT_DIR"/run_summary.json >/dev/null 2>&1 || true
        echo "[完成] 已导出到: $EXPORT_DIR"
        ls -lh "$EXPORT_DIR"/final_results.* "$EXPORT_DIR"/failed_asins.csv "$EXPORT_DIR"/run_summary.json 2>/dev/null || true
    else
        echo "[提示] 当前没有可导出的最终结果文件"
    fi
}

open_project_dir() {
    echo "项目目录: $PROJECT_DIR"
    echo "你可以手动查看以下目录："
    echo "  输入:  $PROJECT_DIR/data"
    echo "  输出:  $PROJECT_DIR/output"
    echo "  调试:  $PROJECT_DIR/debug"
    echo "  状态:  $PROJECT_DIR/state"
    echo "  备份:  $PROJECT_DIR/archive"
}

main_menu() {
    ensure_paths
    while true; do
        clear
        echo "========================================"
        echo " Amazon Monitor 管理菜单（单worker分批版）"
        echo " 项目目录: $PROJECT_DIR"
        echo "========================================"
        echo "1) 环境检查"
        echo "2) 导入 input_asins.xlsx"
        echo "3) 启动单 worker"
        echo "4) 重建镜像并启动单 worker"
        echo "5) 停止任务"
        echo "6) 查看状态"
        echo "7) 查看 worker 日志"
        echo "8) 导出最终结果到 /home/ubuntu"
        echo "9) 查看项目目录说明"
        echo "0) 退出"
        echo "========================================"
        read -r -p "请选择 [0-9]: " choice

        case "$choice" in
            1)
                clear
                check_env
                pause
                ;;
            2)
                clear
                import_input_file
                pause
                ;;
            3)
                clear
                start_worker
                pause
                ;;
            4)
                clear
                rebuild_and_start
                pause
                ;;
            5)
                clear
                stop_worker
                pause
                ;;
            6)
                clear
                show_status
                pause
                ;;
            7)
                clear
                show_worker_logs
                ;;
            8)
                clear
                export_outputs
                pause
                ;;
            9)
                clear
                open_project_dir
                pause
                ;;
            0)
                echo "退出。"
                exit 0
                ;;
            *)
                echo "无效选择"
                sleep 1
                ;;
        esac
    done
}

main_menu
