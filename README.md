# 🧩 Linux Network & System Tools

这个仓库包含了一组方便在 **各类 Linux 发行版**（如 Debian / Ubuntu / Arch / Fedora / CentOS / Rocky / Alpine / openSUSE / NixOS 等）中快速使用的系统管理脚本。

---

## 🚀 一键使用命令

无需克隆仓库，直接复制以下命令即可运行：

### 🛠️ 配置网卡脚本
交互式配置网卡（支持自动识别系统类型、静态/DHCP 切换、自动重启网络）  
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/413hy/config/main/netconfig.sh)
```

### 🌐 检测网卡信息脚本
快速查看当前系统所有网卡的状态、IP 地址、网关、DNS 等信息
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/413hy/config/main/check.sh)
```

### 💻 检测系统信息脚本
一键显示系统版本、内核、CPU、内存、磁盘、负载、运行时间等状态信息
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/413hy/config/main/system.sh)
```

### ⚡ 解除系统限制（ulimit / 配额 / 防火墙 / SELinux 等）
交互式选择**永久生效或临时生效**解除限制脚本，并在执行前自动备份相关配置文件。
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/413hy/config/main/unlimit.sh)
```
