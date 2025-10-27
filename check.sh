#!/usr/bin/env bash
# ==========================================
# 通用 Linux 发行版一键网卡信息检测脚本
# 适配: Debian/Ubuntu/CentOS/RHEL/Fedora/Arch/Manjaro/openSUSE/Alpine/Rocky/NixOS 等
# 作者: ChatGPT（GPT-5）
# ==========================================

echo "=========================================="
echo "🔍 通用 Linux 网卡信息检测脚本"
echo "=========================================="
echo

# 检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$NAME
else
    DISTRO=$(uname -s)
fi
echo "🖥️ 系统发行版: $DISTRO"
echo

# 检查命令可用性
cmd_exist() {
    command -v "$1" >/dev/null 2>&1
}

# 获取所有网卡
if cmd_exist ip; then
    interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
elif cmd_exist ifconfig; then
    interfaces=$(ifconfig -a | grep -o '^[^ ]*' | grep -v "lo")
else
    echo "❌ 未找到 ip 或 ifconfig 命令，请安装 net-tools 或 iproute2"
    exit 1
fi

# 输出网卡信息
for iface in $interfaces; do
    echo "------------------------------------------"
    echo "🕹️ 网卡名称: $iface"

    # 状态
    if ip link show "$iface" | grep -q "state UP"; then
        echo "✅ 状态: UP"
    else
        echo "⚠️ 状态: DOWN"
    fi

    # MAC 地址
    mac=$(cat /sys/class/net/$iface/address 2>/dev/null)
    echo "🔸 MAC 地址: ${mac:-未知}"

    # IP 地址
    ipv4=$(ip -4 addr show $iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d/ -f1)
    ipv6=$(ip -6 addr show $iface | grep -oP '(?<=inet6\s)[\da-f:]+')
    echo "🌐 IPv4 地址: ${ipv4:-无}"
    echo "🌐 IPv6 地址: ${ipv6:-无}"

    # 网关
    gateway=$(ip route show default 2>/dev/null | grep "dev $iface" | awk '{print $3}')
    echo "🚪 网关: ${gateway:-无}"

    # DNS 检测
    dns_list=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
    if [ -n "$dns_list" ]; then
        echo "🧭 DNS: $dns_list"
    else
        echo "🧭 DNS: 未配置"
    fi
done

echo "------------------------------------------"
echo "✅ 检测完成！"
echo

# 若系统支持 nmcli，也输出 NetworkManager 状态
if cmd_exist nmcli; then
    echo "📡 NetworkManager 概况："
    nmcli device status 2>/dev/null || echo "（NetworkManager 未管理此设备）"
fi
