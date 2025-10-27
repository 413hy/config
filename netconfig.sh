#!/usr/bin/env bash
# 通用 Linux 网卡配置脚本 v2
# 支持系统: Debian/Ubuntu/CentOS/Fedora/Arch/openSUSE/Alpine/NixOS
# 作者: ChatGPT (GPT-5)

set -e

echo "=== 通用Linux网卡配置脚本 v2 ==="
echo "此脚本将帮助你交互式配置静态或DHCP网络。"
echo

# 必须用root
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本。"
  exit 1
fi

# 检测系统
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  DISTRO=$(uname -s)
fi

echo "检测到系统发行版: $DISTRO"
echo

# 列出网卡
echo "可用网卡如下："
ip -br link | awk '{print $1}'
echo
read -p "请输入要配置的网卡名称（如 eth0 或 ens33）: " IFACE

# 选择模式
echo
read -p "是否要使用 DHCP 自动获取IP？(y/n): " USE_DHCP

# 获取参数
if [[ "$USE_DHCP" != "y" ]]; then
  read -p "请输入静态IP地址（例如 192.168.1.100）: " IPADDR
  read -p "请输入子网掩码（例如 255.255.255.0）: " NETMASK
  read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
  read -p "请输入DNS服务器（例如 8.8.8.8）: " DNS
fi

echo
echo "即将配置以下信息："
echo "网卡：$IFACE"
if [[ "$USE_DHCP" == "y" ]]; then
  echo "模式：DHCP 自动获取"
else
  echo "模式：静态"
  echo "IP地址：$IPADDR"
  echo "掩码：$NETMASK"
  echo "网关：$GATEWAY"
  echo "DNS：$DNS"
fi
echo
read -p "确认继续？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" ]] && echo "已取消。" && exit 0

# 清除旧IP（防止双IP）
ip addr flush dev "$IFACE"

backup_and_write() {
  local file="$1"
  local content="$2"
  [[ -f "$file" ]] && cp "$file" "$file.bak_$(date +%s)"
  echo -e "$content" > "$file"
}

apply_static_now() {
  ip addr add "$IPADDR"/$(ipcalc -p "$IPADDR" "$NETMASK" | cut -d= -f2) dev "$IFACE"
  ip route add default via "$GATEWAY" || true
  echo "nameserver $DNS" > /etc/resolv.conf
}

apply_dhcp_now() {
  dhclient -r "$IFACE" 2>/dev/null || true
  dhclient "$IFACE"
}

case "$DISTRO" in
  debian|ubuntu|linuxmint)
    if command -v netplan >/dev/null 2>&1; then
      CONF_FILE="/etc/netplan/01-netcfg.yaml"
      if [[ "$USE_DHCP" == "y" ]]; then
        backup_and_write "$CONF_FILE" "
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: yes
"
      else
        backup_and_write "$CONF_FILE" "
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses: [$IPADDR/$(ipcalc -p "$IPADDR" "$NETMASK" | cut -d= -f2)]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$DNS]
"
      fi
      netplan apply
    else
      CONF_FILE="/etc/network/interfaces"
      if [[ "$USE_DHCP" == "y" ]]; then
        backup_and_write "$CONF_FILE" "
auto $IFACE
iface $IFACE inet dhcp
"
      else
        backup_and_write "$CONF_FILE" "
auto $IFACE
iface $IFACE inet static
  address $IPADDR
  netmask $NETMASK
  gateway $GATEWAY
  dns-nameservers $DNS
"
      fi
      systemctl restart networking || service networking restart
    fi
    ;;
  centos|rocky|almalinux|fedora|rhel)
    CONF_FILE="/etc/sysconfig/network-scripts/ifcfg-$IFACE"
    if [[ "$USE_DHCP" == "y" ]]; then
      backup_and_write "$CONF_FILE" "
DEVICE=$IFACE
BOOTPROTO=dhcp
ONBOOT=yes
"
    else
      backup_and_write "$CONF_FILE" "
DEVICE=$IFACE
BOOTPROTO=none
ONBOOT=yes
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DNS1=$DNS
"
    fi
    nmcli dev disconnect "$IFACE" 2>/dev/null || true
    nmcli con reload || true
    systemctl restart network || systemctl restart NetworkManager
    ;;
  arch|manjaro)
    mkdir -p /etc/systemd/network
    CONF_FILE="/etc/systemd/network/$IFACE.network"
    if [[ "$USE_DHCP" == "y" ]]; then
      backup_and_write "$CONF_FILE" "
[Match]
Name=$IFACE
[Network]
DHCP=yes
"
    else
      backup_and_write "$CONF_FILE" "
[Match]
Name=$IFACE
[Network]
Address=$IPADDR/$(ipcalc -p "$IPADDR" "$NETMASK" | cut -d= -f2)
Gateway=$GATEWAY
DNS=$DNS
"
    fi
    systemctl enable --now systemd-networkd
    systemctl restart systemd-networkd
    ;;
  opensuse*)
    CONF_FILE="/etc/sysconfig/network/ifcfg-$IFACE"
    if [[ "$USE_DHCP" == "y" ]]; then
      backup_and_write "$CONF_FILE" "
BOOTPROTO='dhcp'
STARTMODE='auto'
"
    else
      backup_and_write "$CONF_FILE" "
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$IPADDR'
NETMASK='$NETMASK'
GATEWAY='$GATEWAY'
DNS1='$DNS'
"
    fi
    systemctl restart wicked
    ;;
  alpine)
    CONF_FILE="/etc/network/interfaces"
    if [[ "$USE_DHCP" == "y" ]]; then
      backup_and_write "$CONF_FILE" "
auto lo
iface lo inet loopback
auto $IFACE
iface $IFACE inet dhcp
"
    else
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
    fi
    /etc/init.d/networking restart
    ;;
  nixos)
    echo "请在 /etc/nixos/configuration.nix 中配置 networking.interfaces.$IFACE"
    ;;
  *)
    echo "暂不支持该系统，请手动配置。"
    ;;
esac

# 立即应用IP
if [[ "$USE_DHCP" == "y" ]]; then
  apply_dhcp_now
else
  apply_static_now
fi

echo
echo "✅ 配置完成！当前网络已更新。"
ip addr show "$IFACE"
