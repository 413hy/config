#!/usr/bin/env bash
#
# system-toolkit.sh
# 通用系统管理主控脚本（交互菜单版）
# Author: yuuhe
# Version: 1.0
# ------------------------------------------

set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/413hy/config/main"  # 你的GitHub仓库路径
LOG_FILE="/tmp/system_toolkit_$(date +%F_%H-%M-%S).log"

# 输出美观的颜色函数
blue(){ echo -e "\e[34m$*\e[0m"; }
green(){ echo -e "\e[32m$*\e[0m"; }
yellow(){ echo -e "\e[33m$*\e[0m"; }
red(){ echo -e "\e[31m$*\e[0m"; }

# 检查root
if [[ $EUID -ne 0 ]]; then
  red "请以 root 或使用 sudo 运行此脚本。"
  exit 1
fi

# 主菜单
show_menu(){
  clear
  echo "============================================"
  echo "      🧰 通用系统管理工具 (System Toolkit)"
  echo "============================================"
  echo " 1) 配置网卡（静态IP/DHCP）"
  echo " 2) 查看网卡信息"
  echo " 3) 解除系统限制（ulimit/sysctl等）"
  echo " 4) 清理系统数据（安全版）"
  echo " 5) 检查系统信息"
  echo " 6) 生成快照"
  echo " 7) 更新本脚本"
  echo " 0) 退出"
  echo "============================================"
}

# 执行远程脚本
run_remote_script(){
  local name="$1"
  local url="$REPO_BASE/$name"
  blue "正在下载并执行脚本：$url"
  sleep 1
  bash <(curl -fsSL "$url") | tee -a "$LOG_FILE"
}

# 主循环
while true; do
  show_menu
  read -rp "请选择操作 [0-6]: " choice
  case "$choice" in
    1)
      run_remote_script "netconfig.sh"     # 配置网卡脚本
      ;;
    2)
      run_remote_script "check.sh"     # 配置网卡脚本
      ;;
    3)
      run_remote_script "system.sh"       # 查看系统信息脚本
      ;;
    4)
      run_remote_script "ulimit.sh"        # 解除系统限制脚本
      ;;
    5)
      run_remote_script "clean.sh" # 安全清理脚本
      ;;
    6)
      run_remote_script "timeshift.sh"  # 系统状态检查脚本
      ;;
    7)
      echo
      blue "正在更新主控脚本自身..."
      curl -fsSL "$REPO_BASE/system-toolkit.sh" -o "$0"
      green "更新完成，请重新运行本脚本。"
      exit 0
      ;;
    0)
      echo "退出程序，再见 👋"
      exit 0
      ;;
    *)
      red "无效选项，请重新输入。"
      ;;
  esac

  echo
  yellow "操作已完成，按回车键返回主菜单..."
  read -r
done
