#!/usr/bin/env bash
#
# 🧰 system-toolkit.sh
# 通用系统管理工具 - 多功能交互版
# Author: yuuhe
# Version: 1.2
# ------------------------------------------

set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/413hy/config/main"
LOG_FILE="/tmp/system_toolkit_$(date +%F_%H-%M-%S).log"
VERSION="1.2"

# ----------- 颜色输出函数 -----------
blue()   { echo -e "\033[1;34m$*\033[0m"; }
green()  { echo -e "\033[1;32m$*\033[0m"; }
yellow() { echo -e "\033[1;33m$*\033[0m"; }
red()    { echo -e "\033[1;31m$*\033[0m"; }

# ----------- 环境检测 -----------
[[ $EUID -ne 0 ]] && { red "请以 root 身份运行"; exit 1; }
command -v curl >/dev/null 2>&1 || { red "缺少 curl，请先安装：apt install -y curl"; exit 1; }

# ----------- 检查更新 -----------
check_update() {
  local remote_version
  remote_version=$(curl -fsSL "$REPO_BASE/VERSION" 2>/dev/null || echo "unknown")
  if [[ "$remote_version" != "unknown" && "$remote_version" != "$VERSION" ]]; then
    yellow "检测到新版本: $remote_version（当前: $VERSION）"
    read -rp "是否更新？(y/N): " upd
    if [[ $upd =~ ^[Yy]$ ]]; then
      curl -fsSL "$REPO_BASE/system-toolkit.sh" -o "$0"
      green "✅ 已更新到最新版本，请重新运行 'yhe' 命令。"
      exit 0
    fi
  fi
}

# ----------- 执行远程脚本函数 -----------
run_remote_script() {
  local script_name="$1"
  local script_url="$REPO_BASE/$script_name"
  blue "正在加载脚本：$script_url"
  sleep 0.5
  bash <(curl -fsSL "$script_url") | tee -a "$LOG_FILE"
}

# ----------- 主菜单 -----------
show_menu() {
  clear
  echo "============================================"
  echo "      🧰 通用系统管理工具 (System Toolkit)"
  echo "============================================"
  echo " 1) 配置网卡（静态IP/DHCP）"
  echo " 2) 查看网卡信息"
  echo " 3) 解除系统限制（ulimit/sysctl等）"
  echo " 4) 清理系统数据（安全版）"
  echo " 5) 查看系统信息"
  echo " 6) 管理系统快照"
  echo " 7) 检查并更新脚本"
  echo " 0) 退出"
  echo "============================================"
}

# ----------- 主循环 -----------
check_update
while true; do
  show_menu
  read -rp "请输入操作编号 [0-7]: " choice
  case "$choice" in
    1) run_remote_script "netconfig.sh" ;;
    2) run_remote_script "check.sh" ;;
    3) run_remote_script "unlimit.sh" ;;
    4) run_remote_script "clean.sh" ;;
    5) run_remote_script "system.sh" ;;
    6) run_remote_script "timeshift.sh" ;;
    7)
      blue "正在更新主控脚本..."
      curl -fsSL "$REPO_BASE/system-toolkit.sh" -o "$0"
      green "✅ 更新完成，请重新运行。"
      exit 0
      ;;
    0)
      echo "👋 再见！"
      exit 0
      ;;
    *)
      red "无效选项，请重新输入。"
      ;;
  esac
  echo
  yellow "操作已完成，按回车返回主菜单..."
  read -r
done
