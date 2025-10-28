#!/usr/bin/env bash
#
# 🧰 system-toolkit.sh
# 通用系统管理工具 - 多功能交互版（全发行版兼容）
# Author: yuuhe
# Version: 1.3
# ------------------------------------------

set -euo pipefail

# ------------------------------------------
# 🔹 基础定义
# ------------------------------------------
REPO_BASE="https://raw.githubusercontent.com/413hy/config/main"
LOG_FILE="/tmp/system_toolkit_$(date +%F_%H-%M-%S).log"
VERSION="1.3"
YHE_PATH="/usr/local/bin/yhe"
SCRIPT_PATH="$(realpath "$0")"

# ------------------------------------------
# 🔹 颜色输出函数
# ------------------------------------------
blue()   { echo -e "\033[1;34m$*\033[0m"; }
green()  { echo -e "\033[1;32m$*\033[0m"; }
yellow() { echo -e "\033[1;33m$*\033[0m"; }
red()    { echo -e "\033[1;31m$*\033[0m"; }

# ------------------------------------------
# 🔹 环境检测与依赖安装（多发行版兼容）
# ------------------------------------------
check_env() {
  [[ $EUID -ne 0 ]] && { red "请以 root 身份运行"; exit 1; }

  if ! command -v curl &>/dev/null; then
    yellow "curl 未安装，正在尝试自动安装..."
    if command -v apt &>/dev/null; then
      apt update -y && apt install -y curl
    elif command -v dnf &>/dev/null; then
      dnf install -y curl
    elif command -v yum &>/dev/null; then
      yum install -y curl
    elif command -v pacman &>/dev/null; then
      pacman -Sy --noconfirm curl
    elif command -v apk &>/dev/null; then
      apk add --no-cache curl
    else
      red "无法自动安装 curl，请手动安装后重试。"
      exit 1
    fi
  fi
}

# ------------------------------------------
# 🔹 自动注册快捷命令 yhe
# ------------------------------------------
register_command() {
  # 检查旧的坏符号链接
  if [[ -L "$YHE_PATH" && ! -e "$YHE_PATH" ]]; then
    yellow "检测到无效的 yhe 链接，正在修复..."
    rm -f "$YHE_PATH"
  fi

  if [[ ! -f "$YHE_PATH" ]]; then
    echo
    yellow "🔧 正在注册快捷命令 yhe..."
    ln -sf "$SCRIPT_PATH" "$YHE_PATH"
    chmod +x "$YHE_PATH"
    green "✅ 已创建快捷命令：yhe"
    green "现在可以立即输入 'yhe' 使用！"
    echo

    # 确保新环境立刻识别 yhe 命令
    hash -r 2>/dev/null || true
  fi
}


# ------------------------------------------
# 🔹 检查更新
# ------------------------------------------
check_update() {
  local remote_version
  remote_version=$(curl -fsSL "$REPO_BASE/VERSION" 2>/dev/null || echo "unknown")
  if [[ "$remote_version" != "unknown" && "$remote_version" != "$VERSION" ]]; then
    yellow "检测到新版本: $remote_version（当前版本: $VERSION）"
    read -rp "是否更新到最新版本？(y/N): " upd
    if [[ $upd =~ ^[Yy]$ ]]; then
      curl -fsSL "$REPO_BASE/system-toolkit.sh" -o "$0"
      green "✅ 已更新到最新版本，请重新运行 'yhe' 命令。"
      exit 0
    fi
  fi
}

# ------------------------------------------
# 🔹 执行远程脚本
# ------------------------------------------
run_remote_script() {
  local script_name="$1"
  local script_url="$REPO_BASE/$script_name"

  blue "🌐 正在加载脚本：$script_url"
  if curl -fsSL "$script_url" >/dev/null 2>&1; then
    bash <(curl -fsSL "$script_url") | tee -a "$LOG_FILE"
  else
    red "❌ 无法加载脚本：$script_url"
  fi
}

# ------------------------------------------
# 🔹 主菜单
# ------------------------------------------
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

# ------------------------------------------
# 🔹 主执行逻辑
# ------------------------------------------
check_env
register_command
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
