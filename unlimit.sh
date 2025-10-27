#!/usr/bin/env bash
# unlock-all-interactive.sh
# 各发行版通用解除系统限制脚本（交互式）
# ⚠️ 高风险，仅在可恢复环境或测试环境使用
set -euo pipefail

# -----------------------
color() { printf "\e[%sm%s\e[0m\n" "$1" "$2"; }
info()  { color "36" "[INFO] $1"; }
warn()  { color "33" "[WARN] $1"; }
err()   { color "31" "[ERROR] $1"; }

# -----------------------
# 检查 root
if [ "$EUID" -ne 0 ]; then
  err "请以 root/使用 sudo 运行此脚本。"
  exit 1
fi

# -----------------------
# 用户交互
echo "=========================="
echo "通用系统解除限制脚本"
echo "=========================="

# 选择环境
echo "请选择运行环境："
echo "1) 测试环境（建议）"
echo "2) 生产环境（风险自负）"
read -p "输入选项 (1/2，默认1): " ENV
ENV=${ENV:-1}
if [[ "$ENV" == "1" ]]; then
  info "已选择测试环境"
else
  warn "已选择生产环境，请确保已备份系统"
fi

# 是否永久生效
read -p "是否希望修改配置文件以永久生效？(y/N): " PERM
PERM=${PERM:-N}

# 确认
read -p "继续执行脚本？ (y/N): " CONF
if [[ ! "$CONF" =~ ^[Yy]$ ]]; then
  info "已取消"
  exit 0
fi

timestamp() { date +%Y%m%d-%H%M%S; }
backup_file() {
  local f="$1"
  if [ -e "$f" ]; then
    local bak="${f}.bak.$(timestamp)"
    cp -a "$f" "$bak"
    info "备份 $f -> $bak"
  fi
}

# -----------------------
# 发行版检测
. /etc/os-release 2>/dev/null || true
DISTRO="${ID:-unknown}"
info "检测到发行版: ${PRETTY_NAME:-$DISTRO}"

# -----------------------
# 1) 根分区只读解除
info "1) 根分区只读解除"
if mount | grep ' on / ' | grep -q 'ro,'; then
  warn "根分区为只读，尝试 remount rw"
  mount -o remount,rw / || warn "无法 remount /"
else
  info "根分区不是只读"
fi
if [[ "$PERM" =~ ^[Yy]$ ]]; then
  FSTAB="/etc/fstab"
  backup_file "$FSTAB"
  sed -E -i.bak."$(timestamp)" 's/(\s\/\s[^\n]*\s)ro(\s|$)/\1rw\2/g' "$FSTAB" || true
  info "已修改 fstab，使根分区永久 rw"
else
  info "未修改 fstab，重启后可能恢复默认"
fi

# -----------------------
# 2) SELinux
if command -v getenforce >/dev/null 2>&1; then
  info "2) SELinux 临时关闭"
  setenforce 0 || true
  info "已临时 Permissive"
  if [[ "$PERM" =~ ^[Yy]$ ]]; then
    SELINUX_CONF="/etc/selinux/config"
    backup_file "$SELINUX_CONF"
    sed -i.bak."$(timestamp)" -E 's/^[[:space:]]*SELINUX=.*/SELINUX=disabled/' "$SELINUX_CONF" || true
    info "已修改 SELinux 配置，重启后永久禁用"
  fi
fi

# -----------------------
# 3) AppArmor
if command -v aa-status >/dev/null 2>&1 || systemctl list-units --type=service | grep -q apparmor; then
  info "3) AppArmor 停止"
  systemctl stop apparmor.service 2>/dev/null || true
  if [[ "$PERM" =~ ^[Yy]$ ]]; then
    systemctl disable apparmor.service 2>/dev/null || true
    systemctl mask apparmor.service 2>/dev/null || true
    info "已永久禁用 AppArmor"
  fi
fi

# -----------------------
# 4) 防火墙
info "4) 停止防火墙服务"
for FW in firewalld ufw nftables; do
  if systemctl list-units --type=service | grep -q "$FW"; then
    systemctl stop "$FW" 2>/dev/null || true
    if [[ "$PERM" =~ ^[Yy]$ ]]; then
      systemctl disable "$FW" 2>/dev/null || true
      systemctl mask "$FW" 2>/dev/null || true
      info "已永久禁用 $FW"
    fi
  fi
done

# -----------------------
# 5) 磁盘配额
info "5) 关闭磁盘配额"
if command -v quotaoff >/dev/null 2>&1; then
  for m in $(mount | awk '/\s(ext4|xfs|btrfs)\s/ {print $3}'); do
    quotaoff -a 2>/dev/null || true
  done
fi
if [[ "$PERM" =~ ^[Yy]$ ]]; then
  FSTAB="/etc/fstab"
  backup_file "$FSTAB"
  sed -E -i.bak."$(timestamp)" 's/,?usrquota,?|,?grpquota,?//g' "$FSTAB" || true
fi
for qf in /aquota.* /quota.* /usrquota.*; do
  [ -e "$qf" ] || continue
  backup_file "$qf"
  rm -f "$qf" 2>/dev/null || true
  info "已删除配额文件 $qf"
done

# -----------------------
# 6) ulimit
info "6) 放宽 ulimit"
ulimit -n 65535 || true
ulimit -u 65535 || true
ulimit -c unlimited || true
if [[ "$PERM" =~ ^[Yy]$ ]]; then
  LIMITS_CONF="/etc/security/limits.d/99-unlimit.conf"
  backup_file "$LIMITS_CONF"
  cat > "$LIMITS_CONF" <<'EOF'
*               soft    nofile          65535
*               hard    nofile          65535
*               soft    nproc           65535
*               hard    nproc           65535
*               soft    core            unlimited
*               hard    core            unlimited
EOF
  for CONF in /etc/systemd/system.conf /etc/systemd/user.conf; do
    backup_file "$CONF"
    sed -i.bak."$(timestamp)" -E 's/^#?DefaultLimitNOFILE=.*$/DefaultLimitNOFILE=65535/' "$CONF" || echo "DefaultLimitNOFILE=65535" >> "$CONF"
    sed -i.bak."$(timestamp)" -E 's/^#?DefaultLimitNPROC=.*$/DefaultLimitNPROC=65535/' "$CONF" || echo "DefaultLimitNPROC=65535" >> "$CONF"
    sed -i.bak."$(timestamp)" -E 's/^#?DefaultLimitCORE=.*$/DefaultLimitCORE=infinity/' "$CONF" || echo "DefaultLimitCORE=infinity" >> "$CONF"
  done
fi

# -----------------------
# 7) 用户 sudo 提升
read -p "要提升哪个用户？(默认当前用户: ${SUDO_USER:-root}): " TARGET_USER
TARGET_USER="${TARGET_USER:-${SUDO_USER:-root}}"
if id "$TARGET_USER" >/dev/null 2>&1; then
  if getent group sudo >/dev/null 2>&1; then
    usermod -aG sudo "$TARGET_USER" || warn "usermod 失败"
  elif getent group wheel >/dev/null 2>&1; then
    usermod -aG wheel "$TARGET_USER" || warn "usermod 失败"
  fi
  if [[ "$PERM" =~ ^[Yy]$ ]]; then
    read -p "是否为 sudo 组启用 NOPASSWD？(y/N): " NOPW
    if [[ "$NOPW" =~ ^[Yy]$ ]]; then
      SUDOERS_D="/etc/sudoers.d"
      mkdir -p "$SUDOERS_D"
      backup_file "${SUDOERS_D}/99-${TARGET_USER}-nopasswd"
      echo "%sudo ALL=(ALL) NOPASSWD:ALL" > "${SUDOERS_D}/99-${TARGET_USER}-nopasswd"
      chmod 0440 "${SUDOERS_D}/99-${TARGET_USER}-nopasswd"
    fi
  fi
fi

# -----------------------
# 8) 文件不可变属性
info "8) 解除文件不可变属性"
if command -v chattr >/dev/null 2>&1; then
  for p in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config; do
    [ -e "$p" ] || continue
    chattr -i "$p" 2>/dev/null || true
    info "取消不可变属性: $p"
  done
fi

# -----------------------
info "✅ 脚本执行完成"
warn "部分永久生效设置需重启或重新登录 shell 才能完全生效"
exit 0
