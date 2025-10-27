#!/usr/bin/env bash
# ===========================================
# 🚀 Universal Snapshot Manager
# Author: Yuuhe + GPT-5
# ===========================================

set -e

# 检测系统类型
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
}

# 安装快照工具
install_snapshot_tool() {
    echo "🔍 检测系统并准备安装快照管理工具..."
    case "$DISTRO" in
        ubuntu|debian)
            sudo apt update -y
            sudo apt install -y timeshift
            TOOL="timeshift"
            ;;
        arch|manjaro)
            if ! command -v yay >/dev/null 2>&1; then
                echo "⚙️ 正在安装 AUR 助手 yay..."
                sudo pacman -S --needed --noconfirm git base-devel
                git clone https://aur.archlinux.org/yay.git /tmp/yay
                (cd /tmp/yay && makepkg -si --noconfirm)
            fi
            yay -S --noconfirm timeshift
            TOOL="timeshift"
            ;;
        fedora|centos|rhel)
            sudo dnf install -y snapper
            TOOL="snapper"
            ;;
        *)
            echo "❌ 无法识别的系统类型，请手动安装 timeshift 或 snapper。"
            exit 1
            ;;
    esac
    echo "✅ 已安装快照工具：$TOOL"
}

# 创建快照
create_snapshot() {
    echo "🧱 创建系统快照..."
    if [ "$TOOL" = "timeshift" ]; then
        sudo timeshift --create --comments "Manual snapshot $(date +%F_%T)" --tags D
    elif [ "$TOOL" = "snapper" ]; then
        sudo snapper create -c pre -d "Manual snapshot $(date +%F_%T)"
    fi
    echo "✅ 快照创建完成！"
}

# 列出快照
list_snapshots() {
    echo "📜 当前系统快照："
    if [ "$TOOL" = "timeshift" ]; then
        sudo timeshift --list
    elif [ "$TOOL" = "snapper" ]; then
        sudo snapper list
    fi
}

# 恢复快照
restore_snapshot() {
    echo "⚠️ 注意：恢复操作将覆盖系统文件！"
    read -p "确认要继续吗？(y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        if [ "$TOOL" = "timeshift" ]; then
            sudo timeshift --restore
        elif [ "$TOOL" = "snapper" ]; then
            read -p "请输入要恢复的快照编号: " ID
            sudo snapper undochange $ID..0
        fi
        echo "✅ 系统已恢复。建议重启。"
    else
        echo "⏹️ 已取消操作。"
    fi
}

# 删除快照
delete_snapshot() {
    echo "🧹 删除快照："
    if [ "$TOOL" = "timeshift" ]; then
        sudo timeshift --list
        read -p "请输入要删除的快照标签（如 D-2025-10-27_12-30-00）: " ID
        sudo timeshift --delete --snapshot $ID
    elif [ "$TOOL" = "snapper" ]; then
        sudo snapper list
        read -p "请输入要删除的快照编号: " ID
        sudo snapper delete $ID
    fi
    echo "✅ 已删除选定快照。"
}

# 主菜单
main_menu() {
    detect_distro
    echo "==========================================="
    echo "🧭 通用系统快照管理工具"
    echo "系统检测到：$DISTRO"
    echo "==========================================="
    echo "1️⃣ 安装快照工具"
    echo "2️⃣ 创建系统快照"
    echo "3️⃣ 恢复系统快照"
    echo "4️⃣ 查看快照列表"
    echo "5️⃣ 删除快照"
    echo "0️⃣ 退出"
    echo "-------------------------------------------"
    read -p "请选择操作: " choice
    case $choice in
        1) install_snapshot_tool ;;
        2) create_snapshot ;;
        3) restore_snapshot ;;
        4) list_snapshots ;;
        5) delete_snapshot ;;
        0) echo "👋 再见！"; exit 0 ;;
        *) echo "❌ 无效选项，请重新输入。" ;;
    esac
    echo
    read -p "是否返回主菜单？(y/N): " back
    [[ "$back" =~ ^[Yy]$ ]] && main_menu
}

main_menu
