#!/usr/bin/env bash
set -euo pipefail

echo "正在调用 LinuxMirrors 换源脚本..."
exec bash <(curl -sSL https://linuxmirrors.cn/main.sh)
