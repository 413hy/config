#!/usr/bin/env bash
# =============================================
# 🧹 Linux 通用系统清理脚本（多发行版通用）
# 作者: yuuhe
# 版本: 1.0
# =============================================

set -e
LOG_FILE="/tmp/system_clean_$(date +%F_%H-%M-%S).log"

info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; echo "[INFO] $*" >>"$LOG_FILE"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; echo "[WARN] $*" >>"$LOG_FILE"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; echo "[ERROR] $*" >>"$LOG_FILE"; }

# 检测 root 权限
[[ $EUID -ne 0 ]] && { error "请使用 root 权限运行"; exit 1; }

# 检测系统类型
OS="$(. /etc/os-release 2>/dev/null; echo "$ID")"
info "检测到系统: $OS"

# ------------------------------
# 选择清理等级
# ------------------------------
cat <<EOF

请选择清理等级：

  1️⃣  基础清理    - 清理缓存、日志、临时文件
  2️⃣  进阶清理    - 清理无用包、关闭所有进程端口
  3️⃣  深度清理    - 清理用户数据、软件配置
  4️⃣  系统重置    - 恢复为刚安装系统的状态（危险）

EOF

read -rp "请输入数字选择清理等级 (1-4): " LEVEL
[[ ! $LEVEL =~ ^[1-4]$ ]] && { error "输入无效"; exit 1; }

read -rp "是否确认执行该清理操作？(y/N): " CONFIRM
[[ $CONFIRM =~ ^[Yy]$ ]] || { warn "操作已取消"; exit 0; }

info "开始执行清理等级 $LEVEL ..."
sleep 1

# ------------------------------
# 基础清理
# ------------------------------
if [[ $LEVEL -ge 1 ]]; then
  info "🧹 清理缓存与临时文件中..."
  sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
  journalctl --vacuum-time=1d >/dev/null 2>&1 || true
  rm -rf /var/log/*.gz /var/log/*-????????
  apt-get clean >/dev/null 2>&1 || true
  dnf clean all >/dev/null 2>&1 || true
  pacman -Scc --noconfirm >/dev/null 2>&1 || true
  apk cache clean >/dev/null 2>&1 || true
  info "✅ 基础清理完成"
fi

# ------------------------------
# 进阶清理
# ------------------------------
if [[ $LEVEL -ge 2 ]]; then
  info "🚫 关闭所有非系统关键进程与端口..."
  ss -tulnp | awk 'NR>1{print $6}' | grep -Eo '[0-9]+$' | xargs -r kill -9 2>/dev/null || true
  pkill -9 -f python 2>/dev/null || true
  pkill -9 -f node 2>/dev/null || true
  pkill -9 -f java 2>/dev/null || true
  info "✅ 非系统进程已清理"

  info "🧩 清理系统残留包..."
  apt-get autoremove -y >/dev/null 2>&1 || true
  dnf autoremove -y >/dev/null 2>&1 || true
  pacman -Rns $(pacman -Qtdq 2>/dev/null) --noconfirm >/dev/null 2>&1 || true
  info "✅ 残留包清理完成"
fi

# ------------------------------
# 深度清理
# ------------------------------
if [[ $LEVEL -ge 3 ]]; then
  info "🗑 清理用户缓存与配置文件..."
  find /home -type f -name '*.log' -delete 2>/dev/null || true
  rm -rf /home/*/.cache /home/*/.config /home/*/.local/share/Trash/* 2>/dev/null || true
  info "✅ 用户数据清理完成"na
fi

# ------------------------------
# 系统重置（危险）
# ------------------------------
if [[ $LEVEL -ge 4 ]]; then
  warn "⚠️ 即将执行系统重置，将清除用户数据、包管理配置、主目录内容。"
  read -rp "确认继续？(y/N): " FINAL
  [[ $FINAL =~ ^[Yy]$ ]] || { warn "操作已取消"; exit 0; }

  info "🔥 执行系统重置..."
  rm -rf /home/* /root/* /etc/ssh/ssh_host_* 2>/dev/null || true
  apt-get purge -y $(dpkg --get-selections | grep -v deinstall | awk '{print $1}') >/dev/null 2>&1 || true
  rm -rf /etc/network/interfaces.d/* /etc/netplan/* 2>/dev/null || true
  info "⚠️ 重置完成（部分更改需重启生效）"
fi

info "🧾 日志文件保存至: $LOG_FILE"
info "✅ 所有清理操作完成！"
