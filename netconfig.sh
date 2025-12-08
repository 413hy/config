
你说：
#!/usr/bin/env bash
# ==========================================
# 通用 Linux 静态网卡配置脚本（适配主流发行版）
# 支持: Debian/Ubuntu/Arch/Manjaro/CentOS/RHEL/Rocky/Fedora/openSUSE/Alpine/NixOS
# 作者: ChatGPT（GPT-5）
# ==========================================

echo "=========================================="
echo "🌐 通用 Linux 网卡配置工具"
echo "=========================================="
echo

# 检测网卡
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
echo "检测到以下网卡："
echo "$interfaces"
echo
read -p "请输入要配置的网卡名称: " IFACE

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "❌ 网卡 $IFACE 不存在！"
    exit 1
fi

read -p "请输入静态IP地址（例如 192.168.1.100）: " IPADDR
read -p "请输入子网掩码（例如 255.255.255.0）: " NETMASK
read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
read -p "请输入DNS服务器（例如 8.8.8.8）: " DNS

# 掩码转前缀函数（不用 ipcalc）
mask2cidr() {
    local x=${1##*255.}
    local b=0
    IFS=. read -r i1 i2 i3 i4 <<< "$1"
    for n in $i1 $i2 $i3 $i4; do
        while [ $n -gt 0 ]; do
            ((b+=n%2))
            n=$((n/2))
        done
    done
    echo $b
}

PREFIX=$(mask2cidr "$NETMASK")

echo
echo "即将配置以下信息："
echo "网卡：$IFACE"
echo "模式：静态"
echo "IP地址：$IPADDR"
echo "掩码：$NETMASK (/ $PREFIX)"
echo "网关：$GATEWAY"
echo "DNS：$DNS"
echo
read -p "确认继续？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "操作已取消。" && exit 0

# 停止 DHCP
dhclient -r "$IFACE" >/dev/null 2>&1

# 清除旧 IP
ip addr flush dev "$IFACE"

# 添加新 IP
ip addr add "$IPADDR/$PREFIX" dev "$IFACE"
ip link set "$IFACE" up

# 添加网关
ip route add default via "$GATEWAY" dev "$IFACE" 2>/dev/null || {
    ip route replace default via "$GATEWAY" dev "$IFACE"
}

# 更新 DNS
echo -e "nameserver $DNS" | tee /etc/resolv.conf >/dev/null

echo
echo "✅ 配置完成！当前网络状态："
ip addr show dev "$IFACE" | grep -E "inet |link/"
echo
echo "🌍 当前路由表："
ip route show
echo
echo "🧭 当前 DNS："
grep nameserver /etc/resolv.conf
echo
echo "✅ 静态 IP 配置成功！"
