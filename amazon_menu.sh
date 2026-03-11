#!/usr/bin/env bash
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
        echo "8) 导出表格文件"
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
