#!/usr/bin/env bash
# 通用系统状态检测脚本 by ChatGPT (GPT-5)
# 支持系统：Debian / Ubuntu / CentOS / Fedora / Arch / openSUSE / Alpine / NixOS 等

set -e

# 彩色输出函数
color() { echo -e "\033[$1m$2\033[0m"; }

# 分割线
line() { echo "------------------------------------------------------------"; }

clear
color 36 "=== 🧭 系统状态检测脚本 ==="
echo

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  color 33 "⚠️ 建议使用 root 权限运行，以获取完整信息。"
fi

# 1️⃣ 系统信息
line
color 34 "[系统信息]"
[ -f /etc/os-release ] && . /etc/os-release
echo "主机名:       $(hostname)"
echo "系统发行版:   ${PRETTY_NAME:-$(uname -s)}"
echo "内核版本:     $(uname -r)"
echo "架构:         $(uname -m)"
echo "运行时间:     $(uptime -p)"
echo "当前时间:     $(date '+%Y-%m-%d %H:%M:%S')"

# 2️⃣ CPU信息
line
color 34 "[CPU 信息]"
CPU_MODEL=$(awk -F: '/model name/ {print $2; exit}' /proc/cpuinfo | sed 's/^ *//')
CPU_CORES=$(nproc)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
echo "CPU型号:      $CPU_MODEL"
echo "核心数:       $CPU_CORES"
echo "负载平均:     $LOAD_AVG"

# 3️⃣ 内存信息
line
color 34 "[内存信息]"
free -h | awk 'NR==1 || NR==2 {print}'
MEM_USED=$(free | awk '/Mem/ {printf("%.2f"), $3/$2*100}')
echo "内存使用率:   $MEM_USED%"

# 4️⃣ 磁盘信息
line
color 34 "[磁盘信息]"
df -h --output=source,fstype,size,used,avail,pcent,target | grep -v tmpfs

# 5️⃣ 网络信息
line
color 34 "[网络信息]"
echo "接口状态:"
ip -br addr | awk '{print "  " $0}'
echo
GATEWAY=$(ip route | awk '/default/ {print $3}' | head -n1)
DNS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | paste -sd ",")
PING_TEST=$(ping -c1 -W1 8.8.8.8 >/dev/null 2>&1 && echo "✅ 可访问互联网" || echo "❌ 无法访问外网")
echo "默认网关:     ${GATEWAY:-未检测到}"
echo "DNS服务器:    ${DNS:-未检测到}"
echo "联网状态:     $PING_TEST"

# 6️⃣ 登录信息
line
color 34 "[用户与会话]"
who
echo
color 32 "当前登录用户: $(whoami)"
color 32 "登录终端: $(tty)"

# 7️⃣ 进程与服务状态
line
color 34 "[进程与服务]"
echo "活跃进程数: $(ps -e --no-headers | wc -l)"
if command -v systemctl >/dev/null 2>&1; then
  echo "Systemd 状态: $(systemctl is-system-running 2>/dev/null || echo unknown)"
else
  echo "Systemd 不可用（可能是 Alpine 或容器环境）"
fi

# 8️⃣ 网络监听端口
line
color 34 "[网络端口监听]"
if command -v ss >/dev/null 2>&1; then
  ss -tuln | awk 'NR==1 || /LISTEN/'
else
  netstat -tuln | awk 'NR==1 || /LISTEN/'
fi

# 9️⃣ 高负载检测
line
color 34 "[系统负载检测]"
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}')
DISK_ALERT=$(df --output=pcent,target | awk 'NR>1 {gsub("%","",$1); if($1>90) print $2}')
echo "CPU使用率:    $CPU_USAGE"
if [ -n "$DISK_ALERT" ]; then
  color 31 "磁盘警告：以下分区使用率超过90%："
  echo "$DISK_ALERT"
else
  color 32 "磁盘空间正常。"
fi

line
color 36 "✅ 检测完成。建议每次维护前运行该脚本查看状态。"
