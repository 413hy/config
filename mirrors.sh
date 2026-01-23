#!/bin/bash
set -euo pipefail
echo "欢迎使用Linux镜像源切换脚本，作者 yhe"
echo "该脚本正在测试中，如若继续使用后出现的任何问题均与本作者无关（如系统损坏，数据丢失等）"

# 判断是否为root用户
if [ $(id -u) != "0" ]; then
    echo "请使用 root 权限运行此脚本: sudo $0"
    exit 1
fi

# 询问用户是否继续使用本脚本
read -p "是否继续执行脚本？(y/n): " answer
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
if [[ "$answer" == "y" ]]; then
    echo "继续执行..."
elif [[ "$answer" == "n" ]]; then
    echo "操作已取消"
    exit 0
else
    echo "输入无效，请输入 y 或 n"
    exit 1
fi

# 检测系统发行版
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
    VERSION_CODENAME="${VERSION_CODENAME:-}"
    VERSION_ID="${VERSION_ID:-}"
else
    echo "无法检测系统发行版"
    exit 1
fi

echo "检测到系统: $OS_ID ${VERSION_CODENAME:-$VERSION_ID}"

# 镜像源地址（可根据需要修改）
MIRROR_BASE="https://mirrors.ustc.edu.cn"

# 下载工具检测
fetch_url() {
    local url=$1
    local dest=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        echo "缺少 curl 或 wget，请先安装其中之一"
        exit 1
    fi
}

resolve_codename() {
    local codename="${VERSION_CODENAME:-}"
    if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
        codename=$(lsb_release -sc 2>/dev/null || true)
    fi
    if [ -z "$codename" ] && [ -f /etc/os-release ]; then
        . /etc/os-release
        codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
    fi
    echo "$codename"
}

update_deb822_sources() {
    local file=$1
    local base_url=$2
    local security_url=$3
    local tmp
    tmp=$(mktemp)
    awk -v base="$base_url" -v sec="$security_url" '
        BEGIN { mode="base" }
        /^Suites:/ {
            mode="base"
            if ($0 ~ /security/) mode="security"
        }
        /^URIs:/ {
            if (mode == "security") {
                print "URIs: " sec
            } else {
                print "URIs: " base
            }
            next
        }
        { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

# 备份和替换函数
backup_file() {
    local file=$1
    local backup="${file}.bak"
    
    if [ -f "$backup" ]; then
        echo "备份文件 $backup 已存在，跳过备份"
    else
        cp "$file" "$backup"
        echo "已创建备份文件 $backup"
    fi
}

# Debian/Ubuntu 系列
configure_debian_ubuntu() {
    local distro=$1
    local codename
    codename=$(resolve_codename)
    if [ -z "$codename" ]; then
        echo "无法检测系统代号（codename），请安装 lsb-release 或手动填写 VERSION_CODENAME"
        exit 1
    fi
    
    # 处理 DEB822 格式 (Debian 12+, Ubuntu 24.04+)
    if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
        echo "检测到 DEB822 格式配置文件"
        backup_file "/etc/apt/sources.list.d/debian.sources"
        update_deb822_sources "/etc/apt/sources.list.d/debian.sources" "$MIRROR_BASE/debian/" "$MIRROR_BASE/debian-security/"
        
    elif [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
        echo "检测到 Ubuntu DEB822 格式配置文件"
        backup_file "/etc/apt/sources.list.d/ubuntu.sources"
        update_deb822_sources "/etc/apt/sources.list.d/ubuntu.sources" "$MIRROR_BASE/ubuntu/" "$MIRROR_BASE/ubuntu/"
        
    # 处理传统格式
    else
        echo "使用传统格式配置"
        backup_file "/etc/apt/sources.list"
        
        if [ "$distro" = "debian" ]; then
            if [ -n "$codename" ]; then
                fetch_url "$MIRROR_BASE/repogen/conf/debian-https-4-$codename" /etc/apt/sources.list 2>/dev/null || {
                    echo "自动下载失败，手动生成配置"
                    cat > /etc/apt/sources.list <<EOF
deb $MIRROR_BASE/debian/ $codename main contrib non-free non-free-firmware
deb $MIRROR_BASE/debian/ $codename-updates main contrib non-free non-free-firmware
deb $MIRROR_BASE/debian/ $codename-backports main contrib non-free non-free-firmware
deb $MIRROR_BASE/debian-security/ $codename-security main contrib non-free non-free-firmware
EOF
                }
            fi
        elif [ "$distro" = "ubuntu" ]; then
            if [ -n "$codename" ]; then
                cat > /etc/apt/sources.list <<EOF
deb $MIRROR_BASE/ubuntu/ $codename main restricted universe multiverse
deb $MIRROR_BASE/ubuntu/ $codename-updates main restricted universe multiverse
deb $MIRROR_BASE/ubuntu/ $codename-backports main restricted universe multiverse
deb $MIRROR_BASE/ubuntu/ $codename-security main restricted universe multiverse
EOF
            fi
        fi
    fi
    
    echo "配置完成！请运行: sudo apt update"
}

# Kali Linux
configure_kali() {
    backup_file "/etc/apt/sources.list"
    
    cat > /etc/apt/sources.list <<EOF
deb $MIRROR_BASE/kali kali-rolling main non-free non-free-firmware contrib
deb-src $MIRROR_BASE/kali kali-rolling main non-free non-free-firmware contrib
EOF
    
    echo "配置完成！请运行: sudo apt update"
}

# Arch Linux
configure_arch() {
    backup_file "/etc/pacman.d/mirrorlist"
    
    cat > /etc/pacman.d/mirrorlist <<EOF
Server = $MIRROR_BASE/archlinux/\$repo/os/\$arch
EOF
    
    echo "配置完成！请运行: sudo pacman -Syy"
}

# Fedora
configure_fedora() {
    if [ ! -d /etc/yum.repos.d ]; then
        mkdir -p /etc/yum.repos.d
    fi
    
    # 备份原有配置
    for file in /etc/yum.repos.d/fedora*.repo; do
        [ -f "$file" ] && backup_file "$file"
    done
    
    cat > /etc/yum.repos.d/fedora.repo <<EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=$MIRROR_BASE/fedora/releases/\$releasever/Everything/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch

[updates]
name=Fedora \$releasever - \$basearch - Updates
baseurl=$MIRROR_BASE/fedora/updates/\$releasever/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF
    
    echo "配置完成！请运行: sudo dnf makecache"
}

# CentOS / Rocky Linux / AlmaLinux
configure_rhel_based() {
    local distro=$1
    local base_url="$MIRROR_BASE"
    local centos_release=""

    if [ "$distro" = "centos" ] && [ -f /etc/centos-release ]; then
        centos_release=$(cat /etc/centos-release)
        if [[ "$centos_release" == *"CentOS Linux"* ]] && [[ "${VERSION_ID%%.*}" -ge 8 ]]; then
            base_url="https://vault.centos.org"
        fi
    fi
    
    if [ ! -d /etc/yum.repos.d ]; then
        mkdir -p /etc/yum.repos.d
    fi
    
    case $distro in
        centos)
            for file in /etc/yum.repos.d/CentOS-*.repo; do
                [ -f "$file" ] && backup_file "$file"
            done
            
            sed -E -e "s|^mirrorlist=|#mirrorlist=|g" \
                -e "s|^#baseurl=|baseurl=|g" \
                -e "s|^baseurl=.*://[^/]+|baseurl=${base_url}|g" \
                -i.bak /etc/yum.repos.d/CentOS-*.repo
            ;;
        rocky)
            sed -E -e "s|^mirrorlist=|#mirrorlist=|g" \
                -e "s|^#baseurl=|baseurl=|g" \
                -e "s|^baseurl=.*://[^/]+|baseurl=${base_url}|g" \
                -i.bak /etc/yum.repos.d/rocky*.repo
            ;;
        almalinux)
            sed -E -e "s|^mirrorlist=|#mirrorlist=|g" \
                -e "s|^#baseurl=|baseurl=|g" \
                -e "s|^baseurl=.*://[^/]+|baseurl=${base_url}|g" \
                -i.bak /etc/yum.repos.d/almalinux*.repo
            ;;
    esac
    
    if [ "${SKIP_REFRESH:-0}" != "1" ]; then
        if command -v dnf >/dev/null 2>&1; then
            dnf makecache -y || true
        else
            yum makecache -y || true
        fi
    else
        echo "已跳过缓存更新（可手动运行: sudo yum makecache 或 sudo dnf makecache）"
    fi
}

run_rhel_self_check() {
    local repo_dir="/etc/yum.repos.d"
    local repo_files=("$repo_dir"/*.repo)
    if [ "${#repo_files[@]}" -eq 0 ]; then
        echo "未找到 repo 配置文件，跳过自检"
        return
    fi
    echo "开始自检（仅检查启用的 baseurl 是否可访问）..."
    for file in "${repo_files[@]}"; do
        [ -f "$file" ] || continue
        if [ "${DEBUG:-0}" = "1" ]; then
            echo "[DEBUG] 检查文件: $file"
        fi
        awk -F= '
            /^\[.*\]/ {section=$0}
            /^enabled=/ {enabled=$2}
            /^baseurl=/ {baseurl=$2}
            /^#?mirrorlist=/ {mirrorlist=$2}
            /^$/ {
                if (enabled == "1" && baseurl != "") {
                    print section "|" baseurl
                }
                enabled=""; baseurl=""; mirrorlist=""
            }
            END {
                if (enabled == "1" && baseurl != "") {
                    print section "|" baseurl
                }
            }
        ' "$file" | while IFS='|' read -r section baseurl; do
            baseurl=$(echo "$baseurl" | xargs)
            if [ -z "$baseurl" ]; then
                continue
            fi
            test_url="${baseurl%/}/repodata/repomd.xml"
            if command -v curl >/dev/null 2>&1; then
                if curl -fsI --connect-timeout 5 "$test_url" >/dev/null 2>&1; then
                    echo "✅ $section -> $test_url"
                else
                    echo "❌ $section -> $test_url (无法访问)"
                fi
            else
                echo "⚠️ 未找到 curl，跳过 $section 的可用性检测"
            fi
        done
    done
    echo "自检完成。若存在失败项，请将 DEBUG=1 的执行日志发给我。"
}

run_rhel_self_check() {
    local repo_dir="/etc/yum.repos.d"
    local repo_files=("$repo_dir"/*.repo)
    if [ "${#repo_files[@]}" -eq 0 ]; then
        echo "未找到 repo 配置文件，跳过自检"
        return
    fi
    echo "开始自检（仅检查启用的 baseurl 是否可访问）..."
    for file in "${repo_files[@]}"; do
        [ -f "$file" ] || continue
        debug "检查文件: $file"
        awk -F= '
            /^\[.*\]/ {section=$0}
            /^enabled=/ {enabled=$2}
            /^baseurl=/ {baseurl=$2}
            /^#?mirrorlist=/ {mirrorlist=$2}
            /^$/ {
                if (enabled == "1" && baseurl != "") {
                    print section "|" baseurl
                }
                enabled=""; baseurl=""; mirrorlist=""
            }
            END {
                if (enabled == "1" && baseurl != "") {
                    print section "|" baseurl
                }
            }
        ' "$file" | while IFS='|' read -r section baseurl; do
            baseurl=$(echo "$baseurl" | xargs)
            if [ -z "$baseurl" ]; then
                continue
            fi
            test_url="${baseurl%/}/repodata/repomd.xml"
            if command -v curl >/dev/null 2>&1; then
                if curl -fsI --connect-timeout 5 "$test_url" >/dev/null 2>&1; then
                    echo "✅ $section -> $test_url"
                else
                    echo "❌ $section -> $test_url (无法访问)"
                fi
            else
                echo "⚠️ 未找到 curl，跳过 $section 的可用性检测"
            fi
        done
    done
    echo "自检完成。若存在失败项，请将 DEBUG=1 的执行日志发给我。"
}

# Alpine Linux
configure_alpine() {
    backup_file "/etc/apk/repositories"
    
    local version="${VERSION_ID:-latest-stable}"
    cat > /etc/apk/repositories <<EOF
$MIRROR_BASE/alpine/v${version}/main
$MIRROR_BASE/alpine/v${version}/community
EOF
    
    echo "配置完成！请运行: sudo apk update"
}

# openSUSE
configure_opensuse() {
    if command -v zypper &> /dev/null; then
        zypper mr -da
        zypper ar -fcg $MIRROR_BASE/opensuse/distribution/leap/\$releasever/repo/oss/ oss
        zypper ar -fcg $MIRROR_BASE/opensuse/distribution/leap/\$releasever/repo/non-oss/ non-oss
        zypper ar -fcg $MIRROR_BASE/opensuse/update/leap/\$releasever/oss/ update-oss
        zypper ar -fcg $MIRROR_BASE/opensuse/update/leap/\$releasever/non-oss/ update-non-oss
        
        echo "配置完成！请运行: sudo zypper ref"
    else
        echo "未找到 zypper 命令"
        exit 1
    fi
}

# NixOS
configure_nixos() {
    echo "NixOS 需要修改配置文件 /etc/nixos/configuration.nix"
    echo "请添加以下内容到配置文件中："
    echo ""
    echo "  nix.settings.substituters = ["
    echo "    \"$MIRROR_BASE/nix-channels/store\""
    echo "  ];"
    echo ""
    echo "然后运行: sudo nixos-rebuild switch"
}

# 根据发行版执行对应配置
case $OS_ID in
    debian)
        configure_debian_ubuntu "debian"
        ;;
    ubuntu)
        configure_debian_ubuntu "ubuntu"
        ;;
    kali)
        configure_kali
        ;;
    arch|manjaro|endeavouros)
        configure_arch
        ;;
    fedora)
        configure_fedora
        ;;
    centos)
        configure_rhel_based "centos"
        run_rhel_self_check
        ;;
    rocky)
        configure_rhel_based "rocky"
        run_rhel_self_check
        ;;
    almalinux)
        configure_rhel_based "almalinux"
        run_rhel_self_check
        ;;
    alpine)
        configure_alpine
        ;;
    opensuse*|sles)
        configure_opensuse
        ;;
    nixos)
        configure_nixos
        ;;
    *)
        echo "不支持的发行版: $OS_ID"
        echo "支持的发行版: Debian, Ubuntu, Kali, Arch, Fedora, CentOS, Rocky, AlmaLinux, Alpine, openSUSE, NixOS"
        exit 1
        ;;
esac

echo ""
echo "感谢您的使用！"
