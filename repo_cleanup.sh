#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "🧹 软件源配置清理脚本（高风险）"
echo "=========================================="
echo

if [[ $EUID -ne 0 ]]; then
  echo "❌ 此脚本需要 root 权限运行"
  echo "请使用: sudo $0"
  exit 1
fi

read -rp "确认要清理所有软件源配置与相关密钥？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "已取消"
  exit 0
fi

BACKUP_DIR="/root/yhe_repo_cleanup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_and_remove() {
  local path=$1
  if [[ -e "$path" ]]; then
    mkdir -p "$BACKUP_DIR$(dirname "$path")"
    mv "$path" "$BACKUP_DIR$path"
    echo "已移除: $path"
  fi
}

backup_and_remove_glob() {
  local glob=$1
  shopt -s nullglob
  local files=($glob)
  shopt -u nullglob
  if [[ ${#files[@]} -gt 0 ]]; then
    for f in "${files[@]}"; do
      backup_and_remove "$f"
    done
  fi
}

# Debian/Ubuntu (APT)
backup_and_remove "/etc/apt/sources.list"
backup_and_remove_glob "/etc/apt/sources.list.d/*"
backup_and_remove "/etc/apt/trusted.gpg"
backup_and_remove_glob "/etc/apt/trusted.gpg.d/*"
backup_and_remove_glob "/etc/apt/keyrings/*"
backup_and_remove_glob "/usr/share/keyrings/*"

# RHEL/CentOS/Fedora (YUM/DNF)
backup_and_remove_glob "/etc/yum.repos.d/*.repo"
backup_and_remove_glob "/etc/pki/rpm-gpg/*"

# SUSE (zypper)
backup_and_remove_glob "/etc/zypp/repos.d/*"
backup_and_remove_glob "/etc/zypp/keys/*"

# Arch (pacman)
backup_and_remove "/etc/pacman.d/mirrorlist"
backup_and_remove "/etc/pacman.d/gnupg"

# Alpine (apk)
backup_and_remove "/etc/apk/repositories"

# NixOS (nix)
backup_and_remove "/etc/nixos/configuration.nix"

echo
echo "✅ 清理完成，备份目录: $BACKUP_DIR"
echo "请根据需要手动重新配置软件源与密钥。"
