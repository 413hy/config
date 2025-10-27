#!/usr/bin/env bash
# 通用 Linux 网卡配置脚本
# 作者: ChatGPT (GPT-5)
# 支持系统: Debian/Ubuntu/CentOS/Fedora/Arch/openSUSE/Alpine/NixOS 等

set -e

echo "=== 通用Linux网卡配置脚本 ==="
echo "此脚本将帮助你交互式配置静态IP网络。"
echo

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

# 检测系统信息
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  DISTRO=$(uname -s)
fi

echo "检测到系统发行版: $DISTRO"
echo

# 显示网卡
echo "可用网卡如下："
ip -br link | awk '{print $1}'
echo

read -p "请输入要配置的网卡名称（如 eth0 或 ens33）: " IFACE
read -p "请输入静态IP地址（例如 192.168.1.100）: " IPADDR
read -p "请输入子网掩码（例如 255.255.255.0）: " NETMASK
read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
read -p "请输入DNS服务器（例如 8.8.8.8）: " DNS

echo
echo "即将配置以下信息："
echo "网卡：$IFACE"
echo "IP地址：$IPADDR"
echo "掩码：$NETMASK"
echo "网关：$GATEWAY"
echo "DNS：$DNS"
echo

read -p "确认继续？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "已取消。" && exit 0

backup_and_write() {
  local file="$1"
  [[ -f "$file" ]] && cp "$file" "$file.bak_$(date +%s)"
  echo -e "$2" > "$file"
}

case "$DISTRO" in
  debian|ubuntu|linuxmint)
    if command -v netplan >/dev/null 2>&1; then
      CONF_FILE="/etc/netplan/01-netcfg.yaml"
      backup_and_write "$CONF_FILE" "
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses: [$IPADDR/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS]
"
      netplan apply
    else
      CONF_FILE="/etc/network/interfaces"
      backup_and_write "$CONF_FILE" "
auto $IFACE
iface $IFACE inet static
  address $IPADDR
  netmask $NETMASK
  gateway $GATEWAY
  dns-nameservers $DNS
"
      systemctl restart networking || service networking restart
    fi
    ;;
  centos|rocky|almalinux|fedora|rhel)
    CONF_FILE="/etc/sysconfig/network-scripts/ifcfg-$IFACE"
    backup_and_write "$CONF_FILE" "
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DNS1=$DNS
"
    systemctl restart network || nmcli connection reload
    ;;
  arch|manjaro)
    mkdir -p /etc/systemd/network
    CONF_FILE="/etc/systemd/network/$IFACE.network"
    backup_and_write "$CONF_FILE" "
[Match]
Name=$IFACE

[Network]
Address=$IPADDR/24
Gateway=$GATEWAY
DNS=$DNS
"
    systemctl enable --now systemd-networkd
    systemctl restart systemd-networkd
    ;;
  opensuse*)
    CONF_FILE="/etc/sysconfig/network/ifcfg-$IFACE"
    backup_and_write "$CONF_FILE" "
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$IPADDR'
NETMASK='$NETMASK'
GATEWAY='$GATEWAY'
DNS1='$DNS'
"
    systemctl restart wicked
    ;;
  alpine)
    CONF_FILE="/etc/network/interfaces"
    backup_and_write "$CONF_FILE" "
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
  address $IPADDR
  netmask $NETMASK
  gateway $GATEWAY
  dns-nameservers $DNS
"
    /etc/init.d/networking restart
    ;;
  nixos)
    echo "NixOS 的网络配置需在 /etc/nixos/configuration.nix 中定义，例如："
    echo "
networking.interfaces.$IFACE = {
  ipv4.addresses = [{
    address = \"$IPADDR\";
    prefixLength = 24;
  }];
  ipv4.gateway = \"$GATEWAY\";
  nameservers = [ \"$DNS\" ];
};"
    echo "修改后执行：sudo nixos-rebuild switch"
    ;;
  *)
    echo "暂不支持自动识别该发行版，请手动配置。"
    ;;
esac

echo
echo "✅ 配置完成！如未生效，请尝试重启网络或系统。"
