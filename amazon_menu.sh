#!/usr/bin/env bash
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
