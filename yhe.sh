#!/usr/bin/env bash
#
# 🧰 yhe.sh v1.5.1
# 修复 unbound variable + 更稳健参数处理
# ------------------------------------------

set -euo pipefail

# ------------------------------------------
# 🔹 基础定义
# ------------------------------------------
REPO_BASE="https://raw.githubusercontent.com/413hy/config/main"
VERSION="1.5.1"
SCRIPT_NAME="yhe.sh"
INSTALL_PATH="/usr/local/bin/yhe"
YHE_PATH="/usr/local/bin/yhe"

# 日志
TMP_LOG=$(mktemp "/tmp/yhe.XXXXXX.log")
exec > >(tee -a "$TMP_LOG") 2>&1

# ------------------------------------------
# 🔹 颜色输出
# ------------------------------------------
blue()   { printf "\033[1;34m%s\033[0m\n" "$*"; }
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[1;31m%s\033[0m\n" "$*"; }

# ------------------------------------------
# 🔹 工具函数
# ------------------------------------------
die() { red "❌ $1"; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$TMP_LOG"; }

download() {
  local url="$1" dest="$2"
  curl -fsSL --connect-timeout 10 "$url" -o "$dest" || die "下载失败: $url"
}

check_root() {
  [[ $EUID -eq 0 ]] || die "请以 root 用户运行"
}

ensure_curl() {
  command -v curl &>/dev/null && return 0
  yellow "curl 未安装，正在自动安装..."
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
    die "无法自动安装 curl，请手动安装"
  fi
}

get_script_path() {
  local path="${BASH_SOURCE[0]}"
  [[ "$path" == "/dev/fd/"* || "$path" == "/proc/"* ]] && echo "TEMP" && return
  realpath "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || echo "$path"
}

install_self() {
  local temp=$(mktemp)
  download "$REPO_BASE/$SCRIPT_NAME" "$temp" || die "无法下载主脚本"
  install -m 755 "$temp" "$INSTALL_PATH"
  rm -f "$temp"
  green "脚本已安装至: $INSTALL_PATH"
}

check_update() {
  local remote_ver
  remote_ver=$(curl -fsSL --connect-timeout 5 "$REPO_BASE/VERSION" 2>/dev/null || echo "unknown")
  [[ "$remote_ver" == "$VERSION" || "$remote_ver" == "unknown" ]] && return 0

  yellow "检测到新版本: $remote_ver（当前: $VERSION）"
  read -rp "是否更新？(y/N): " ans
  [[ "$ans" =~ ^[Yy]$ ]] || return 0

  blue "正在更新..."
  install_self
  register_command
  green "更新成功！重启中..."
  mv "$TMP_LOG" "/var/log/yhe_$(date +%F_%H%M%S).log" 2>/dev/null || true
  exec "$INSTALL_PATH" "$@"
}

register_command() {
  [[ -L "$YHE_PATH" && ! -e "$YHE_PATH" ]] && rm -f "$YHE_PATH"
  [[ -e "$YHE_PATH" ]] && return 0
  ln -sf "$INSTALL_PATH" "$YHE_PATH"
  green "快捷指令已创建: yhe"
  hash -r 2>/dev/null || true
}

run_remote_script() {
  [[ -z "${1:-}" ]] && { red "内部错误：run_remote_script 缺少参数"; return 1; }
  local name="$1"
  local url="$REPO_BASE/$name"
  local temp_script

  temp_script=$(mktemp) || die "无法创建临时文件"
  blue "正在加载子脚本: $name"

  if download "$url" "$temp_script"; then
    bash "$temp_script" 2>&1 | tee -a "$TMP_LOG"
    rm -f "$temp_script"
  else
    red "下载失败: $name"
    rm -f "$temp_script"
    return 1
  fi
}

show_menu() {
  clear
  cat << EOF
============================================
      通用系统管理工具 v$VERSION
============================================
 1) 配置网卡（静态IP/DHCP）
 2) 查看网卡信息
 3) 解除系统限制（ulimit/sysctl）
 4) 清理系统数据（安全版）
 5) 查看系统信息
 6) 管理系统快照
 7) 切换系统镜像源
 8) 强制更新脚本
 0) 退出
============================================
EOF
}

# ------------------------------------------
# 🔹 主逻辑
# ------------------------------------------
main() {
  check_root
  ensure_curl

  local current_path
  current_path=$(get_script_path)

  # 临时运行 → 安装本地
  if [[ "$current_path" == "TEMP" ]]; then
    yellow "检测到临时运行，正在安装..."
    install_self
    register_command
    green "安装完成！请使用 'yhe' 命令"
    mv "$TMP_LOG" "/var/log/yhe_install_$(date +%F_%H%M%S).log" 2>/dev/null || true
    exec "$INSTALL_PATH" "$@"
  fi

  check_update
  register_command

  while true; do
    show_menu
    read -rp "请输入选项 [0-8]: " choice
    case "$choice" in
      1) run_remote_script "netconfig.sh" ;;
      2) run_remote_script "check.sh" ;;
      3) run_remote_script "unlimit.sh" ;;
      4) run_remote_script "clean.sh" ;;
      5) run_remote_script "system.sh" ;;
      6) run_remote_script "timeshift.sh" ;;
      7) run_remote_script "mirrors.sh" ;;
      8)
        blue "正在强制更新..."
        install_self
        green "更新完成，请重新运行 yhe"
        exit 0
        ;;
      0)
        green "再见！"
        exit 0
        ;;
      *)
        red "无效选项，请重新输入"
        sleep 1
        ;;
    esac
    yellow "按回车键继续..."
    read -r
  done
}

# 启动
main "$@"
