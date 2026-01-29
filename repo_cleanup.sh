#!/usr/bin/env bash
set -e

# 1) 备份 /etc/apt（防止删错还能恢复）
ts="$(date +%F_%H%M%S)"
mkdir -p "/root/apt-backup-$ts"
cp -a /etc/apt "/root/apt-backup-$ts/"
echo "✅ 已备份到 /root/apt-backup-$ts"

# 2) 删除所有软件源配置（list / sources）
rm -f /etc/apt/sources.list
find /etc/apt/sources.list.d -maxdepth 1 -type f -print -delete 2>/dev/null || true

# 3) 删除 APT 信任密钥（仅 /etc/apt 里的，不动系统包自带的 /usr/share/keyrings）
rm -f /etc/apt/trusted.gpg
find /etc/apt/trusted.gpg.d -maxdepth 1 -type f -print -delete 2>/dev/null || true
find /etc/apt/keyrings -maxdepth 1 -type f -print -delete 2>/dev/null || true

# 4) 删除 pin / preferences（有些人加过会导致版本/源混乱）
rm -f /etc/apt/preferences
rm -rf /etc/apt/preferences.d/* 2>/dev/null || true

# 5) 清空 apt 缓存索引
apt-get clean
rm -rf /var/lib/apt/lists/*

# 6) 写入“干净的 Debian 官方源”（自动识别系统代号）
CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-bookworm}")"
cat > /etc/apt/sources.list <<EOF
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://mirrors.huaweicloud.com/debian ${CODENAME} main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://mirrors.huaweicloud.com/debian ${CODENAME}-updates main contrib non-free non-free-firmware
deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] http://mirrors.huaweicloud.com/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
EOF

# 7) 更新
apt-get update
echo "✅ 清理完成 + 已恢复为纯 Debian 官方源（${CODENAME}）"
