#!/usr/bin/env bash
# ==========================================
# 通用 Linux 静态网卡配置 + 桥接配置脚本
# 支持：
# Debian/Ubuntu、Arch/Manjaro、CentOS/RHEL/Rocky、Fedora、openSUSE、Alpine
# 作者: ChatGPT（GPT-5）
# ==========================================

echo "=========================================="
echo "🌐 通用 Linux 网卡配置工具（增强版）"
echo "=========================================="
echo

# 检测系统类型
detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif grep -qi "arch" /etc/os-release; then
        echo "arch"
    elif grep -qi "alpine" /etc/os-release; then
        echo "alpine"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo "📌 检测到系统类型：$OS"
echo

# 网卡列表
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
echo "检测到以下网卡："
echo "$interfaces"
echo

echo "请选择配置类型："
echo "1) 普通静态网卡"
echo "2) 桥接网卡（br0）"
read -p "请输入选项 (1/2): " MODE

if [[ "$MODE" == "1" ]]; then
    read -p "请输入要配置的网卡名称: " IFACE
elif [[ "$MODE" == "2" ]]; then
    read -p "请输入桥接名称（默认 br0）: " BR
    BR=${BR:-br0}
    read -p "请输入需要桥接的网卡（例如 eth0）: " IFACE
else
    echo "❌ 无效选项"
    exit 1
fi

# 判断网卡是否存在
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "❌ 网卡 $IFACE 不存在！"
    exit 1
fi

read -p "请输入静态IP地址（例如 192.168.1.100）: " IPADDR
read -p "请输入子网掩码（例如 255.255.255.0）: " NETMASK
read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
read -p "请输入DNS服务器（例如 8.8.8.8）: " DNS

# 掩码 → 前缀
mask2cidr() {
    IFS=. read -r o1 o2 o3 o4 <<< "$1"
    echo $(( (o1 * 16777216 + o2 * 65536 + o3 * 256 + o4)
        ^ 4294967295 | tr -dc 1 | wc -c ))
}

PREFIX=$(mask2cidr "$NETMASK")

echo
echo "即将配置以下信息："
if [[ "$MODE" == "1" ]]; then
    echo "网卡：$IFACE"
else
    echo "桥接：$BR"
    echo "桥接端口：$IFACE"
fi
echo "IP地址：$IPADDR/$PREFIX"
echo "网关：$GATEWAY"
echo "DNS：$DNS"
echo
read -p "确认继续？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "操作已取消。" && exit 0

# 🔧 写入系统配置文件
write_config() {
    if [[ "$OS" == "debian" ]]; then
        echo "🔧 正在写入 /etc/network/interfaces"

        if [[ "$MODE" == "1" ]]; then
            cat >/etc/network/interfaces <<EOF
auto $IFACE
iface $IFACE inet static
    address $IPADDR
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers $DNS
EOF

        else
            cat >/etc/network/interfaces <<EOF
auto $BR
iface $BR inet static
    bridge_ports $IFACE
    address $IPADDR
    gateway $GATEWAY
    netmask $NETMASK
    dns-nameservers $DNS
    bridge_stp off
    bridge_waitport 0
    bridge_fd 0
EOF

        fi
        systemctl restart networking

    elif [[ "$OS" == "rhel" ]]; then
        echo "🔧 正在写入 /etc/sysconfig/network-scripts"

        if [[ "$MODE" == "1" ]]; then
            cat >/etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOF
TYPE=Ethernet
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IPADDR
PREFIX=$PREFIX
GATEWAY=$GATEWAY
DNS1=$DNS
EOF

        else
            cat >/etc/sysconfig/network-scripts/ifcfg-$BR <<EOF
DEVICE=$BR
TYPE=Bridge
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IPADDR
PREFIX=$PREFIX
GATEWAY=$GATEWAY
DNS1=$DNS
EOF

            cat >/etc/sysconfig/network-scripts/ifcfg-$IFACE <<EOF
TYPE=Ethernet
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
BRIDGE=$BR
EOF
        fi

        systemctl restart network

    elif [[ "$OS" == "arch" ]]; then
        echo "🔧 正在使用 systemd-networkd 生成配置"
        mkdir -p /etc/systemd/network/

        if [[ "$MODE" == "1" ]]; then
            cat >/etc/systemd/network/$IFACE.network <<EOF
[Match]
Name=$IFACE

[Network]
Address=$IPADDR/$PREFIX
Gateway=$GATEWAY
DNS=$DNS
EOF
        else
            cat >/etc/systemd/network/$BR.netdev <<EOF
[NetDev]
Name=$BR
Kind=bridge
EOF

            cat >/etc/systemd/network/$BR.network <<EOF
[Match]
Name=$BR

[Network]
Address=$IPADDR/$PREFIX
Gateway=$GATEWAY
DNS=$DNS
EOF

            cat >/etc/systemd/network/$IFACE.network <<EOF
[Match]
Name=$IFACE

[Network]
Bridge=$BR
EOF
        fi

        systemctl restart systemd-networkd

    else
        echo "⚠ 你的系统暂不支持自动写配置文件，仅执行临时设置"
    fi
}

write_config

# 临时立即生效
ip addr flush dev "$IFACE"
if [[ "$MODE" == "2" ]]; then
    ip link add name "$BR" type bridge 2>/dev/null
    ip link set "$IFACE" master "$BR"
    ip link set "$BR" up
    ip addr add "$IPADDR/$PREFIX" dev "$BR"
else
    ip addr add "$IPADDR/$PREFIX" dev "$IFACE"
    ip link set "$IFACE" up
fi

ip route replace default via "$GATEWAY"

echo
echo "🎉 配置完成！当前网络状态："
ip addr show | grep -E "inet |link/"

echo
echo "🌍 路由表："
ip route

echo
echo "🧭 DNS："
cat /etc/resolv.conf
echo
echo "✅ 静态 IP 配置成功！"
