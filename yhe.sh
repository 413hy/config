#!/usr/bin/env bash
#
# 🧰 system-toolkit.sh v1.5.1
# 修復 unbound variable + 更穩健參數處理
# ------------------------------------------

set -euo pipefail

# ------------------------------------------
# 🔹 基礎定義
# ------------------------------------------
REPO_BASE="https://raw.githubusercontent.com/413hy/config/main"
VERSION="1.5.1"
SCRIPT_NAME="yhe.sh"
INSTALL_PATH="/usr/local/bin/system-toolkit"
YHE_PATH="/usr/local/bin/yhe"

# 日誌
TMP_LOG=$(mktemp "/tmp/system_toolkit.XXXXXX.log")
exec > >(tee -a "$TMP_LOG") 2>&1

# ------------------------------------------
# 🔹 顏色
# ------------------------------------------
blue()   { printf "\033[1;34m%s\033[0m\n" "$*"; }
green()  { printf "\033[1;32m%s\033[0m\n" "$*"; }
yellow() { printf "\033[1;33m%s\033[0m\n" "$*"; }
red()    { printf "\033[1;31m%s\033[0m\n" "$*"; }

# ------------------------------------------
# 🔹 工具函數
# ------------------------------------------
die() { red "❌ $1"; exit 1; }
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$TMP_LOG"; }

download() {
  local url="$1" dest="$2"
  curl -fsSL --connect-timeout 10 "$url" -o "$dest" || die "下載失敗: $url"
}

check_root() {
  [[ $EUID -eq 0 ]] || die "請以 root 身份運行"
}

ensure_curl() {
  command -v curl &>/dev/null && return 0
  yellow "curl 未安裝，正在自動安裝..."
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
    die "無法自動安裝 curl"
  fi
}

get_script_path() {
  local path="${BASH_SOURCE[0]}"
  [[ "$path" == "/dev/fd/"* || "$path" == "/proc/"* ]] && echo "TEMP" && return
  realpath "$path" 2>/dev/null || readlink -f "$path" 2>/dev/null || echo "$path"
}

install_self() {
  local temp=$(mktemp)
  download "$REPO_BASE/$SCRIPT_NAME" "$temp" || die "無法下載主腳本"
  install -m 755 "$temp" "$INSTALL_PATH"
  rm -f "$temp"
  green "腳本已更新至: $INSTALL_PATH"
}

check_update() {
  local remote_ver
  remote_ver=$(curl -fsSL --connect-timeout 5 "$REPO_BASE/VERSION" 2>/dev/null || echo "unknown")
  [[ "$remote_ver" == "$VERSION" || "$remote_ver" == "unknown" ]] && return 0

  yellow "檢測到新版本: $remote_ver（當前: $VERSION）"
  read -rp "是否更新？(y/N): " ans
  [[ "$ans" =~ ^[Yy]$ ]] || return 0

  blue "正在更新..."
  install_self
  register_command
  green "更新成功！重啟中..."
  mv "$TMP_LOG" "/var/log/system-toolkit_$(date +%F_%H%M%S).log" 2>/dev/null || true
  exec "$INSTALL_PATH" "$@"
}

register_command() {
  [[ -L "$YHE_PATH" && ! -e "$YHE_PATH" ]] && rm -f "$YHE_PATH"
  [[ -e "$YHE_PATH" ]] && return 0
  ln -sf "$INSTALL_PATH" "$YHE_PATH"
  green "快捷指令已創建: yhe"
  hash -r 2>/dev/null || true
}

# 關鍵修復：嚴格檢查參數
run_remote_script() {
  # 必須傳入參數
  [[ -z "${1:-}" ]] && { red "內部錯誤：run_remote_script 缺少參數"; return 1; }
  local name="$1"
  local url="$REPO_BASE/$name"
  local temp_script

  temp_script=$(mktemp) || die "無法創建臨時文件"
  blue "正在加載子腳本: $name"

  if download "$url" "$temp_script"; then
    bash "$temp_script" 2>&1 | tee -a "$TMP_LOG"
    rm -f "$temp_script"
  else
    red "下載失敗: $name"
    rm -f "$temp_script"
    return 1
  fi
}

show_menu() {
  clear
  cat << EOF
============================================
      通用系統管理工具 v$VERSION
============================================
 1) 配置網卡（靜態IP/DHCP）
 2) 查看網卡信息
 3) 解除系統限制（ulimit/sysctl）
 4) 清理系統數據（安全版）
 5) 查看系統信息
 6) 管理系统快照
 7) 強制更新腳本
 0) 退出
============================================
EOF
}

# ------------------------------------------
# 🔹 主邏輯
# ------------------------------------------
main() {
  check_root
  ensure_curl

  local current_path
  current_path=$(get_script_path)

  # 臨時運行 → 安裝本地
  if [[ "$current_path" == "TEMP" ]]; then
    yellow "檢測到臨時運行，正在安裝..."
    install_self
    register_command
    green "安裝完成！請使用 'yhe' 命令"
    mv "$TMP_LOG" "/var/log/system-toolkit_install_$(date +%F_%H%M%S).log" 2>/dev/null || true
    exec "$INSTALL_PATH" "$@"
  fi

  check_update
  register_command

  while true; do
    show_menu
    read -rp "請輸入選項 [0-7]: " choice
    case "$choice" in
      1) run_remote_script "netconfig.sh" ;;
      2) run_remote_script "check.sh" ;;
      3) run_remote_script "unlimit.sh" ;;
      4) run_remote_script "clean.sh" ;;
      5) run_remote_script "system.sh" ;;
      6) run_remote_script "timeshift.sh" ;;
      7)
        blue "正在強制更新..."
        install_self
        green "更新完成，請重新運行 yhe"
        exit 0
        ;;
      0)
        green "再見！"
        exit 0
        ;;
      *)
        red "無效選項，請重新輸入。"
        sleep 1
        ;;
    esac
    yellow "按回車鍵繼續..."
    read -r
  done
}

# 啟動
main "$@"
