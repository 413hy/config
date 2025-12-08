#!/usr/bin/env bash
# ==========================================
# 通用 Linux 静态网卡配置脚本（永久配置版）
# 支持: Debian/Ubuntu/Arch/Manjaro/CentOS/RHEL/Rocky/Fedora/openSUSE
# ==========================================

set -euo pipefail

echo "=========================================="
echo "🌐 通用 Linux 网卡配置工具 (永久配置版)"
echo "=========================================="
echo

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
   echo "❌ 此脚本需要 root 权限运行"
   echo "请使用: sudo $0"
   exit 1
fi

# 验证 IP 地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if ((octet > 255)); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 掩码转前缀函数
mask2cidr() {
    local mask=$1
    local nbits=0
    IFS='.' read -r -a octets <<< "$mask"
    
    for octet in "${octets[@]}"; do
        case $octet in
            255) ((nbits+=8));;
            254) ((nbits+=7));;
            252) ((nbits+=6));;
            248) ((nbits+=5));;
            240) ((nbits+=4));;
            224) ((nbits+=3));;
            192) ((nbits+=2));;
            128) ((nbits+=1));;
            0);;
            *) echo "❌ 无效的子网掩码"; exit 1;;
        esac
    done
    echo $nbits
}

# 检测 Linux 发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "unknown"
    fi
}

DISTRO=$(detect_distro)
echo "🖥️  检测到的系统: $DISTRO"
echo

# 检测网卡
echo "检测到以下网卡："
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo")
echo "$interfaces"
echo

# 输入网卡名称
while true; do
    read -p "请输入要配置的网卡名称: " IFACE
    if ip link show "$IFACE" >/dev/null 2>&1; then
        break
    else
        echo "❌ 网卡 $IFACE 不存在，请重新输入"
    fi
done

# 输入并验证 IP 地址
while true; do
    read -p "请输入静态IP地址（例如 192.168.1.100）: " IPADDR
    if validate_ip "$IPADDR"; then
        break
    else
        echo "❌ IP 地址格式无效，请重新输入"
    fi
done

# 输入并验证子网掩码
while true; do
    read -p "请输入子网掩码（例如 255.255.255.0）: " NETMASK
    if validate_ip "$NETMASK"; then
        break
    else
        echo "❌ 子网掩码格式无效，请重新输入"
    fi
done

# 输入并验证网关
while true; do
    read -p "请输入网关地址（例如 192.168.1.1）: " GATEWAY
    if validate_ip "$GATEWAY"; then
        break
    else
        echo "❌ 网关地址格式无效，请重新输入"
    fi
done

# 输入并验证 DNS
while true; do
    read -p "请输入DNS服务器（例如 8.8.8.8，多个用空格分隔）: " DNS
    IFS=' ' read -r -a dns_array <<< "$DNS"
    valid=true
    for dns in "${dns_array[@]}"; do
        if ! validate_ip "$dns"; then
            echo "❌ DNS 地址 $dns 格式无效"
            valid=false
            break
        fi
    done
    if $valid; then
        break
    fi
done

PREFIX=$(mask2cidr "$NETMASK")

echo
echo "=========================================="
echo "即将配置以下信息："
echo "网卡：$IFACE"
echo "模式：静态IP"
echo "IP地址：$IPADDR/$PREFIX"
echo "掩码：$NETMASK"
echo "网关：$GATEWAY"
echo "DNS：${dns_array[*]}"
echo "系统：$DISTRO"
echo "=========================================="
echo

# 配置类型选择
echo "请选择配置方式："
echo "1) 仅临时配置（重启后失效）"
echo "2) 永久配置（写入配置文件）"
echo "3) 临时+永久配置（推荐）"
read -p "请选择 [1-3]: " CONFIG_TYPE

case $CONFIG_TYPE in
    1|2|3) ;;
    *) echo "❌ 无效选择，默认使用选项 3"; CONFIG_TYPE=3;;
esac

echo
read -p "确认继续？(y/n): " CONFIRM
[[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && echo "操作已取消。" && exit 0

# 备份当前配置
BACKUP_DIR="/root/network_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
ip addr show "$IFACE" > "$BACKUP_DIR/ip_addr.txt" 2>/dev/null || true
ip route show > "$BACKUP_DIR/routes.txt" 2>/dev/null || true
cp /etc/resolv.conf "$BACKUP_DIR/resolv.conf" 2>/dev/null || true
echo "📁 已备份当前配置到: $BACKUP_DIR"
echo

# ==================== 临时配置 ====================
if [[ $CONFIG_TYPE == "1" || $CONFIG_TYPE == "3" ]]; then
    echo "⏳ 正在应用临时配置..."
    
    # 停止可能的服务
    systemctl stop NetworkManager >/dev/null 2>&1 || true
    dhclient -r "$IFACE" >/dev/null 2>&1 || true
    
    # 清除旧配置
    ip addr flush dev "$IFACE" 2>/dev/null || true
    
    # 配置新 IP
    if ip addr add "$IPADDR/$PREFIX" dev "$IFACE"; then
        echo "✅ IP 地址配置成功"
    else
        echo "❌ IP 地址配置失败"
        exit 1
    fi
    
    # 启用网卡
    ip link set "$IFACE" up
    
    # 配置网关
    ip route del default >/dev/null 2>&1 || true
    if ip route add default via "$GATEWAY" dev "$IFACE"; then
        echo "✅ 网关配置成功"
    fi
    
    # 配置 DNS
    {
        echo "# Generated by network config script at $(date)"
        for dns in "${dns_array[@]}"; do
            echo "nameserver $dns"
        done
    } > /etc/resolv.conf
    echo "✅ DNS 配置成功"
    echo
fi

# ==================== 永久配置 ====================
if [[ $CONFIG_TYPE == "2" || $CONFIG_TYPE == "3" ]]; then
    echo "💾 正在写入永久配置..."
    
    case $DISTRO in
        ubuntu|debian)
            # 检查使用 netplan 还是 interfaces
            if [ -d /etc/netplan ]; then
                echo "使用 Netplan 配置..."
                # 备份现有配置
                [ -f /etc/netplan/01-netcfg.yaml ] && cp /etc/netplan/01-netcfg.yaml "$BACKUP_DIR/"
                
                # 创建新配置
                cat > /etc/netplan/01-netcfg.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses:
        - $IPADDR/$PREFIX
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$(IFS=','; echo "${dns_array[*]}")]
EOF
                chmod 600 /etc/netplan/01-netcfg.yaml
                echo "✅ Netplan 配置已写入"
                
                if [[ $CONFIG_TYPE == "2" ]]; then
                    echo "⏳ 应用 Netplan 配置..."
                    netplan apply
                fi
            else
                echo "使用 interfaces 配置..."
                [ -f /etc/network/interfaces ] && cp /etc/network/interfaces "$BACKUP_DIR/"
                
                # 移除旧配置
                sed -i "/iface $IFACE/,/^$/d" /etc/network/interfaces
                
                # 添加新配置
                cat >> /etc/network/interfaces <<EOF

auto $IFACE
iface $IFACE inet static
    address $IPADDR
    netmask $NETMASK
    gateway $GATEWAY
    dns-nameservers ${dns_array[*]}
EOF
                echo "✅ interfaces 配置已写入"
                
                if [[ $CONFIG_TYPE == "2" ]]; then
                    ifdown "$IFACE" && ifup "$IFACE"
                fi
            fi
            ;;
            
        centos|rhel|rocky|fedora|almalinux)
            echo "使用 NetworkManager 配置..."
            CONFIG_FILE="/etc/sysconfig/network-scripts/ifcfg-$IFACE"
            [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_DIR/"
            
            cat > "$CONFIG_FILE" <<EOF
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE
DEVICE=$IFACE
ONBOOT=yes
IPADDR=$IPADDR
NETMASK=$NETMASK
GATEWAY=$GATEWAY
DNS1=${dns_array[0]}
$([ ${#dns_array[@]} -gt 1 ] && echo "DNS2=${dns_array[1]}")
$([ ${#dns_array[@]} -gt 2 ] && echo "DNS3=${dns_array[2]}")
EOF
            echo "✅ NetworkManager 配置已写入"
            
            if [[ $CONFIG_TYPE == "2" ]]; then
                systemctl restart NetworkManager
                nmcli connection reload
                nmcli connection up "$IFACE"
            fi
            ;;
            
        arch|manjaro)
            echo "使用 systemd-networkd 配置..."
            CONFIG_FILE="/etc/systemd/network/20-$IFACE.network"
            [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_DIR/"
            
            cat > "$CONFIG_FILE" <<EOF
[Match]
Name=$IFACE

[Network]
Address=$IPADDR/$PREFIX
Gateway=$GATEWAY
$(for dns in "${dns_array[@]}"; do echo "DNS=$dns"; done)
EOF
            echo "✅ systemd-networkd 配置已写入"
            
            systemctl enable systemd-networkd
            if [[ $CONFIG_TYPE == "2" ]]; then
                systemctl restart systemd-networkd
            fi
            ;;
            
        opensuse*)
            echo "使用 wicked 配置..."
            CONFIG_FILE="/etc/sysconfig/network/ifcfg-$IFACE"
            [ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BACKUP_DIR/"
            
            cat > "$CONFIG_FILE" <<EOF
BOOTPROTO='static'
IPADDR='$IPADDR/$PREFIX'
STARTMODE='auto'
EOF
            
            cat > /etc/sysconfig/network/routes <<EOF
default $GATEWAY - -
EOF
            
            for i in "${!dns_array[@]}"; do
                echo "NETCONFIG_DNS_STATIC_SERVERS=\"${dns_array[*]}\"" > /etc/sysconfig/network/config
            done
            
            echo "✅ wicked 配置已写入"
            
            if [[ $CONFIG_TYPE == "2" ]]; then
                wicked ifdown "$IFACE" && wicked ifup "$IFACE"
            fi
            ;;
            
        *)
            echo "⚠️  未识别的发行版 ($DISTRO)，仅应用临时配置"
            echo "请手动配置永久网络设置"
            ;;
    esac
    
    echo "✅ 永久配置已完成"
    echo
fi

# 测试连接
echo "🧪 测试网络连接..."
sleep 2

if ping -c 2 -W 3 "$GATEWAY" >/dev/null 2>&1; then
    echo "✅ 网关连接正常"
else
    echo "⚠️  无法 ping 通网关"
fi

if ping -c 2 -W 3 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ 外网连接正常"
else
    echo "⚠️  无法连接外网"
fi

echo
echo "=========================================="
echo "✅ 配置完成！当前网络状态："
echo "=========================================="
echo
echo "📌 网卡信息："
ip addr show dev "$IFACE" | grep -E "inet |link/"
echo
echo "🌍 路由表："
ip route show | grep -E "default|$IFACE"
echo
echo "🧭 DNS 配置："
cat /etc/resolv.conf | grep nameserver
echo
echo "=========================================="

if [[ $CONFIG_TYPE == "2" || $CONFIG_TYPE == "3" ]]; then
    echo "✅ 永久配置已生效，重启后依然有效"
else
    echo "⚠️  当前为临时配置，重启后会丢失"
fi

echo
echo "📁 配置备份位置: $BACKUP_DIR"
echo "=========================================="
echo
echo "💡 提示："
echo "  - 如需回滚，请查看备份目录"
echo "  - 如有问题，可以重启系统恢复原配置"
echo "=========================================="
