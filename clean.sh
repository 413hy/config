#!/usr/bin/env bash
#
# clean-system-safe.sh
# 安全版系统清理脚本（移除“重装/彻底重置”选项）
# 适用：Debian/Ubuntu/CentOS/Arch/Fedora/Alpine 等
# 说明：只做安全范围内的清理，避免移除系统关键组件或卸载所有包
#
set -euo pipefail
LOG_FILE="/tmp/system_clean_safe_$(date +%F_%H-%M-%S).log"

# ---------- helpers ----------
_info(){ printf "\e[1;34m[INFO]\e[0m %s\n" "$*" | tee -a "$LOG_FILE"; }
_warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$*" | tee -a "$LOG_FILE"; }
_err(){ printf "\e[1;31m[ERROR]\e[0m %s\n" "$*" | tee -a "$LOG_FILE"; }
_confirm(){ read -rp "$1 (y/N): " ans; [[ $ans =~ ^[Yy]$ ]]; }

# ---------- pre-checks ----------
if [[ $EUID -ne 0 ]]; then
  _err "请以 root 或 sudo 运行此脚本。"
  exit 1
fi

. /etc/os-release 2>/dev/null || true
OS="${ID:-unknown}"
PRETTY="${PRETTY_NAME:-$OS}"
_info "检测到系统: $PRETTY"

cat <<'MSG'

===========================================
     安全版系统清理脚本（3 级）
     1) 基础清理：清理缓存、临时文件、journal
     2) 进阶清理：结束非关键用户进程、释放端口、清理残留包缓存
     3) 深度清理：清理用户缓存、家目录临时文件、旧日志
===========================================
注意：
- 本脚本**不会**卸载核心系统包或删除 /etc 下的系统配置。
- 在关键服务器上运行前请先备份或在测试环境验证。
- 日志保存在：$LOG_FILE
MSG

# ---------- choose level ----------
read -rp "请选择清理等级 (1-3，默认1): " LEVEL
LEVEL="${LEVEL:-1}"
if [[ ! "$LEVEL" =~ ^[1-3]$ ]]; then
  _err "无效选择，退出。"
  exit 1
fi

if ! _confirm "确认要执行等级 $LEVEL 的清理操作？请确认已备份重要数据"; then
  _info "已取消"
  exit 0
fi

_info "开始执行清理（等级 $LEVEL）。日志： $LOG_FILE"
sleep 1

# ---------- safe lists ----------
# 不要结束或触碰的服务/程序（简要）
SAFE_PROCS_REGEX="sshd|systemd|init|kthreadd|kworker|cron|rsyslog|journald|NetworkManager|dhclient|dhcpcd|dbus|polkitd|Xorg|gdm|lightdm|sshd"

# ---------- Level 1: 基础清理 ----------
if [[ $LEVEL -ge 1 ]]; then
  _info "【Level 1】基础清理：释放内存缓存、清空临时目录、清理包缓存、压缩/回收日志"
  # 释放 pagecache / dentries / inodes
  if [[ -w /proc/sys/vm/drop_caches ]]; then
    sync
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    _info "已尝试释放内存缓存（drop_caches=3）"
  else
    _warn "/proc/sys/vm/drop_caches 无写权限或不可用"
  fi

  # 清空 /tmp 和 /var/tmp（保守：仅删除可写项）
  _info "清理 /tmp 和 /var/tmp（仅删除普通文件/目录）"
  find /tmp -mindepth 1 -maxdepth 3 -xdev -exec rm -rf -- {} + 2>/dev/null || true
  find /var/tmp -mindepth 1 -maxdepth 3 -xdev -exec rm -rf -- {} + 2>/dev/null || true

  # 清理包管理缓存（安全调用，不卸载任何包）
  _info "清理包管理缓存（apt/dnf/pacman/apk）"
  command -v apt-get >/dev/null 2>&1 && apt-get clean 2>/dev/null || true
  command -v dnf >/dev/null 2>&1 && dnf clean all -y >/dev/null 2>&1 || true
  command -v pacman >/dev/null 2>&1 && pacman -Scc --noconfirm >/dev/null 2>&1 || true
  command -v apk >/dev/null 2>&1 && apk cache clean >/dev/null 2>&1 || true

  # journal 日志压缩/清理（保留7天）
  if command -v journalctl >/dev/null 2>&1; then
    _info "journalctl: 删除 7 天前的日志以节省空间"
    journalctl --vacuum-time=7d >/dev/null 2>&1 || true
  fi

  _info "Level 1 完成"
fi

# ---------- Level 2: 进阶清理 ----------
if [[ $LEVEL -ge 2 ]]; then
  _info "【Level 2】进阶清理：结束非关键用户进程、释放端口、清理孤立包（不卸载核心包）"

  # 列出监听端口及对应 PID
  _info "列出当前监听的 TCP/UDP 端口（简要）"
  if command -v ss >/dev/null 2>&1; then
    ss -tulnp | sed -n '1,200p' | tee -a "$LOG_FILE"
  else
    netstat -tulnp 2>/dev/null | sed -n '1,200p' | tee -a "$LOG_FILE" || true
  fi

  _info "将尝试终止 *非 root* 且不在白名单的监听进程，以释放端口。"
  if _confirm "继续尝试终止这些进程？（会保留 root 所有的进程与常见系统守护进程）"; then
    # 获取监听进程 PID 列表（非 root）
    mapfile -t PIDS < <(
      if command -v ss >/dev/null 2>&1; then
        ss -tulnp 2>/dev/null | awk 'NR>1 {print $6}' | grep -Eo '[0-9]+' | sort -u
      else
        netstat -tulnp 2>/dev/null | awk 'NR>2{print $7}' | grep -Eo '[0-9]+' | sort -u
      fi
    )

    for pid in "${PIDS[@]:-}"; do
      [[ -z "$pid" ]] && continue
      # get UID and cmdline
      if [[ -r "/proc/$pid/status" ]]; then
        uid=$(awk '/^Uid:/{print $2}' /proc/"$pid"/status || echo "")
      else
        uid=""
      fi
      cmd=$(tr -d '\0' < /proc/"$pid"/cmdline 2>/dev/null || ps -p "$pid" -o comm= 2>/dev/null || echo "")
      # skip root-owned
      if [[ "$uid" == "0" ]]; then
        continue
      fi
      # skip safe procs by name
      if [[ "$cmd" =~ $SAFE_PROCS_REGEX ]]; then
        _info "跳过安全进程 PID:$pid CMD:$cmd"
        continue
      fi
      _warn "终止 PID:$pid CMD:$cmd (非 root、非白名单)"
      kill -9 "$pid" 2>/dev/null || _warn "无法终止 PID:$pid"
    done
    _info "监听端口相关的非 root 进程已尝试终止"
  else
    _info "已跳过终止监听进程"
  fi

  # 清理孤立包 / 自动移除无用包（安全模式：仅 autoremove / orphan 清理，不卸载手动安装的包）
  if command -v apt-get >/dev/null 2>&1; then
    _info "apt: 执行 apt autoremove -y"
    apt-get autoremove -y >/dev/null 2>&1 || true
  fi
  if command -v dnf >/dev/null 2>&1; then
    _info "dnf: 尝试 dnf autoremove -y"
    dnf autoremove -y >/dev/null 2>&1 || true
  fi
  if command -v pacman >/dev/null 2>&1; then
    orphans=$(pacman -Qtdq 2>/dev/null || true)
    if [[ -n "$orphans" ]]; then
      _info "pacman: 将移除 orphan 包（列出并移除）"
      printf '%s\n' "$orphans" | tee -a "$LOG_FILE"
      pacman -Rns --noconfirm $orphans >/dev/null 2>&1 || true
    else
      _info "pacman: 无 orphan 包"
    fi
  fi

  _info "Level 2 完成"
fi

# ---------- Level 3: 深度清理 ----------
if [[ $LEVEL -ge 3 ]]; then
  _info "【Level 3】深度清理：清理用户缓存、家目录临时文件以及旧系统日志"
  # 清理每个用户的 cache / trash（但不删除家目录中的 dotfiles）
  for home in /home/*; do
    [[ -d "$home" ]] || continue
    user=$(basename "$home")
    _info "处理用户: $user"
    # 删除常见缓存目录（仅这些目录）
    rm -rf "$home"/.cache/* 2>/dev/null || true
    rm -rf "$home"/.local/share/Trash/* 2>/dev/null || true
    # 可选：删除浏览器缓存目录（匹配常见路径）
    rm -rf "$home"/.mozilla/firefox/*/cache2/* 2>/dev/null || true
    rm -rf "$home"/.cache/google-chrome/* 2>/dev/null || true
  done

  # 删除 /var/log 下超过 30 天的日志文件（保守）
  _info "删除 /var/log 中超过 30 天的日志文件（仅文件，不删除目录）"
  find /var/log -type f -mtime +30 -exec rm -f {} + 2>/dev/null || true

  # 清理 apt / dnf / pacman 缓存（已在 Level1 做过，但再次确保）
  command -v apt-get >/dev/null 2>&1 && apt-get clean >/dev/null 2>&1 || true
  command -v dnf >/dev/null 2>&1 && dnf clean all -y >/dev/null 2>&1 || true
  command -v pacman >/dev/null 2>&1 && pacman -Scc --noconfirm >/dev/null 2>&1 || true

  _info "Level 3 完成"
fi

# ---------- final ----------
_info "清理完成。请检查日志： $LOG_FILE"
_warn "建议：在关键生产环境上先在测试机验证脚本后再运行。"
_warn "若你在远程 SSH 上执行 Level>=2，建议保留一个备用会话或控制台以防误杀 sshd。"

exit 0
