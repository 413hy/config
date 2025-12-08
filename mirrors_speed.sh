#!/bin/bash
echo "========================================"
echo "  Linux 最快镜像源自动选择脚本"
echo "  作者: yhe"
echo "  支持国内外VPS自动选择最优镜像"
echo "========================================"
echo ""

# 判断是否为root用户
if [ $(id -u) != "0" ]; then
    echo "请使用 root 权限运行此脚本: sudo $0"
    exit 1
fi

# 询问用户是否继续
read -p "是否继续执行脚本？(y/n): " answer
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
if [[ "$answer" != "y" ]]; then
    echo "操作已取消"
    exit 0
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

echo ""
echo "检测到系统: $OS_ID ${VERSION_CODENAME:-$VERSION_ID}"

# 检测服务器地理位置
echo "正在检测服务器位置..."
IP_INFO=$(curl -s --connect-timeout 5 --max-time 10 "http://ip-api.com/json/?lang=zh-CN" 2>/dev/null)

if [ -n "$IP_INFO" ]; then
    COUNTRY=$(echo "$IP_INFO" | grep -oP '"country":"\K[^"]+' 2>/dev/null)
    COUNTRY_CODE=$(echo "$IP_INFO" | grep -oP '"countryCode":"\K[^"]+' 2>/dev/null)
    CITY=$(echo "$IP_INFO" | grep -oP '"city":"\K[^"]+' 2>/dev/null)
    
    if [ -n "$COUNTRY" ]; then
        echo "检测到位置: $COUNTRY $CITY"
    fi
else
    echo "无法检测位置，将测试所有镜像源"
    COUNTRY_CODE="UNKNOWN"
fi

echo ""

# 定义镜像源列表
declare -A MIRROR_LIST

# 根据发行版定义镜像源
case $OS_ID in
    debian|ubuntu|kali)
        if [ "$COUNTRY_CODE" = "CN" ]; then
            # 国内镜像源
            MIRROR_LIST=(
                ["中国科学技术大学"]="https://mirrors.ustc.edu.cn"
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn"
                ["阿里云"]="https://mirrors.aliyun.com"
                ["腾讯云"]="https://mirrors.cloud.tencent.com"
                ["华为云"]="https://mirrors.huaweicloud.com"
                ["网易"]="https://mirrors.163.com"
                ["上海交通大学"]="https://mirror.sjtu.edu.cn"
                ["浙江大学"]="https://mirrors.zju.edu.cn"
                ["南京大学"]="https://mirrors.nju.edu.cn"
                ["北京外国语大学"]="https://mirrors.bfsu.edu.cn"
            )
        else
            # 国外镜像源
            MIRROR_LIST=(
                ["官方源(全球CDN)"]="http://deb.debian.org"
                ["Ubuntu官方源"]="http://archive.ubuntu.com"
                ["Cloudflare"]="https://cloudflaremirrors.com"
                ["MIT(美国)"]="https://mirrors.mit.edu"
                ["KAIST(韩国)"]="https://mirror.kakao.com"
                ["日本理化学研究所"]="https://ftp.riken.jp"
                ["新加坡国立大学"]="https://download.nus.edu.sg"
                ["澳大利亚Aarnet"]="https://mirror.aarnet.edu.au"
                ["英国剑桥大学"]="https://www.mirrorservice.org"
                ["德国FAU"]="https://ftp.fau.de"
            )
        fi
        ;;
    arch|manjaro|endeavouros)
        if [ "$COUNTRY_CODE" = "CN" ]; then
            MIRROR_LIST=(
                ["中国科学技术大学"]="https://mirrors.ustc.edu.cn/archlinux"
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn/archlinux"
                ["阿里云"]="https://mirrors.aliyun.com/archlinux"
                ["腾讯云"]="https://mirrors.cloud.tencent.com/archlinux"
                ["华为云"]="https://mirrors.huaweicloud.com/archlinux"
                ["上海交通大学"]="https://mirror.sjtu.edu.cn/archlinux"
            )
        else
            MIRROR_LIST=(
                ["Cloudflare"]="https://cloudflaremirrors.com/archlinux"
                ["MIT(美国)"]="https://mirrors.mit.edu/archlinux"
                ["KAIST(韩国)"]="https://mirror.kakao.com/archlinux"
                ["日本理化学研究所"]="https://ftp.riken.jp/Linux/archlinux"
                ["新加坡国立大学"]="https://download.nus.edu.sg/mirror/archlinux"
                ["澳大利亚Aarnet"]="https://mirror.aarnet.edu.au/pub/archlinux"
            )
        fi
        ;;
    fedora|centos|rocky|almalinux)
        if [ "$COUNTRY_CODE" = "CN" ]; then
            MIRROR_LIST=(
                ["中国科学技术大学"]="https://mirrors.ustc.edu.cn"
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn"
                ["阿里云"]="https://mirrors.aliyun.com"
                ["腾讯云"]="https://mirrors.cloud.tencent.com"
                ["华为云"]="https://mirrors.huaweicloud.com"
                ["上海交通大学"]="https://mirror.sjtu.edu.cn"
            )
        else
            MIRROR_LIST=(
                ["Cloudflare"]="https://cloudflaremirrors.com"
                ["MIT(美国)"]="https://mirrors.mit.edu"
                ["KAIST(韩国)"]="https://mirror.kakao.com"
                ["日本理化学研究所"]="https://ftp.riken.jp/Linux"
            )
        fi
        ;;
    alpine)
        if [ "$COUNTRY_CODE" = "CN" ]; then
            MIRROR_LIST=(
                ["中国科学技术大学"]="https://mirrors.ustc.edu.cn/alpine"
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn/alpine"
                ["阿里云"]="https://mirrors.aliyun.com/alpine"
                ["腾讯云"]="https://mirrors.cloud.tencent.com/alpine"
            )
        else
            MIRROR_LIST=(
                ["Cloudflare"]="https://cloudflaremirrors.com/alpine"
                ["官方源"]="https://dl-cdn.alpinelinux.org/alpine"
            )
        fi
        ;;
    opensuse*)
        if [ "$COUNTRY_CODE" = "CN" ]; then
            MIRROR_LIST=(
                ["中国科学技术大学"]="https://mirrors.ustc.edu.cn/opensuse"
                ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn/opensuse"
                ["阿里云"]="https://mirrors.aliyun.com/opensuse"
                ["北京外国语大学"]="https://mirrors.bfsu.edu.cn/opensuse"
            )
        else
            MIRROR_LIST=(
                ["官方源"]="https://download.opensuse.org"
                ["Cloudflare"]="https://cloudflaremirrors.com/opensuse"
            )
        fi
        ;;
    *)
        echo "暂不支持的发行版: $OS_ID"
        exit 1
        ;;
esac

# 测试镜像源速度函数
test_mirror_speed() {
    local url=$1
    local name=$2
    
    # 根据发行版选择测试文件
    local test_file=""
    case $OS_ID in
        debian)
            if [[ "$url" == *"deb.debian.org"* ]]; then
                test_file="$url/debian/dists/$VERSION_CODENAME/Release"
            else
                test_file="$url/debian/dists/$VERSION_CODENAME/Release"
            fi
            ;;
        ubuntu)
            if [[ "$url" == *"archive.ubuntu.com"* ]]; then
                test_file="$url/ubuntu/dists/$VERSION_CODENAME/Release"
            else
                test_file="$url/ubuntu/dists/$VERSION_CODENAME/Release"
            fi
            ;;
        kali)
            test_file="$url/kali/dists/kali-rolling/Release"
            ;;
        arch|manjaro|endeavouros)
            test_file="$url/core/os/x86_64/core.db"
            ;;
        fedora)
            test_file="$url/fedora/releases/$VERSION_ID/Everything/x86_64/os/repodata/repomd.xml"
            ;;
        centos)
            if [ "${VERSION_ID%%.*}" -ge 8 ]; then
                test_file="$url/centos/$VERSION_ID/BaseOS/x86_64/os/repodata/repomd.xml"
            else
                test_file="$url/centos/$VERSION_ID/os/x86_64/repodata/repomd.xml"
            fi
            ;;
        rocky)
            test_file="$url/rocky/$VERSION_ID/BaseOS/x86_64/os/repodata/repomd.xml"
            ;;
        almalinux)
            test_file="$url/almalinux/$VERSION_ID/BaseOS/x86_64/os/repodata/repomd.xml"
            ;;
        alpine)
            test_file="$url/v${VERSION_ID}/main/x86_64/APKINDEX.tar.gz"
            ;;
        opensuse*)
            test_file="$url/distribution/leap/$VERSION_ID/repo/oss/repodata/repomd.xml"
            ;;
    esac
    
    # 测试延迟和下载速度
    local ping_time=$(curl -o /dev/null -s -w '%{time_total}' --connect-timeout 3 --max-time 5 "$test_file" 2>/dev/null)
    
    if [ -n "$ping_time" ] && [ "$ping_time" != "0.000" ]; then
        # 再测试实际下载速度
        local speed=$(curl -o /dev/null -s -w '%{speed_download}' --connect-timeout 3 --max-time 8 "$test_file" 2>/dev/null)
        
        if [ -n "$speed" ] && [ "$speed" != "0.000" ]; then
            local speed_kb=$(echo "scale=2; $speed / 1024" | bc 2>/dev/null)
            local ping_ms=$(echo "scale=0; $ping_time * 1000" | bc 2>/dev/null)
            echo "$speed_kb|$ping_ms"
        else
            echo "0|999999"
        fi
    else
        echo "0|999999"
    fi
}

# 备份函数
backup_file() {
    local file=$1
    local backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
    
    if [ -f "$file" ]; then
        cp "$file" "$backup"
        echo "已备份到: $backup"
    fi
}

# 测试所有镜像源
echo "开始测试镜像源速度（延迟和下载速度），请稍候..."
echo ""
printf "%-30s %-15s %-15s\n" "镜像源" "速度(KB/s)" "延迟(ms)"
echo "================================================================"

declare -A SPEED_RESULTS
declare -A PING_RESULTS
fastest_mirror=""
fastest_speed=0
fastest_name=""
lowest_ping=999999

for name in "${!MIRROR_LIST[@]}"; do
    url="${MIRROR_LIST[$name]}"
    printf "%-30s " "$name"
    
    result=$(test_mirror_speed "$url" "$name")
    speed=$(echo "$result" | cut -d'|' -f1)
    ping=$(echo "$result" | cut -d'|' -f2)
    
    SPEED_RESULTS[$name]=$speed
    PING_RESULTS[$name]=$ping
    
    if [ "$speed" != "0" ]; then
        printf "%-15.2f %-15s\n" "$speed" "${ping}ms"
        
        # 综合评分：速度权重70%，延迟权重30%
        # 分数 = 速度 - (延迟/10)
        score=$(echo "scale=2; $speed - ($ping / 10)" | bc -l 2>/dev/null)
        best_score=$(echo "scale=2; $fastest_speed - ($lowest_ping / 10)" | bc -l 2>/dev/null)
        
        is_better=$(echo "$score > $best_score" | bc -l 2>/dev/null)
        if [ "$is_better" -eq 1 ] || [ "$fastest_speed" = "0" ]; then
            fastest_speed=$speed
            fastest_mirror=$url
            fastest_name=$name
            lowest_ping=$ping
        fi
    else
        printf "%-15s %-15s\n" "超时" "失败"
    fi
done

echo ""
echo "========================================"

if [ -z "$fastest_mirror" ]; then
    echo "错误: 所有镜像源测试失败，请检查网络连接"
    exit 1
fi

echo "推荐的镜像源: $fastest_name"
echo "下载速度: $(printf '%.2f' $fastest_speed) KB/s"
echo "延迟: ${lowest_ping}ms"
echo "地址: $fastest_mirror"
echo "========================================"
echo ""

# 显示速度排行榜（前5名）
echo "速度排行榜（前5名）："
echo "----------------------------------------"
for name in "${!SPEED_RESULTS[@]}"; do
    speed="${SPEED_RESULTS[$name]}"
    ping="${PING_RESULTS[$name]}"
    if [ "$speed" != "0" ]; then
        score=$(echo "scale=2; $speed - ($ping / 10)" | bc -l 2>/dev/null)
        echo "$score|$name|$speed|$ping"
    fi
done | sort -rn | head -5 | awk -F'|' '{printf "%d. %-25s %8.2f KB/s  %5sms\n", NR, $2, $3, $4}'
echo ""

read -p "是否使用推荐的镜像源？(y/n): " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
if [[ "$confirm" != "y" ]]; then
    echo "操作已取消"
    exit 0
fi

# 配置函数
configure_debian_ubuntu() {
    local mirror=$1
    local distro=$2
    
    # DEB822 格式
    if [ -f "/etc/apt/sources.list.d/debian.sources" ]; then
        backup_file "/etc/apt/sources.list.d/debian.sources"
        
        if [[ "$mirror" == *"deb.debian.org"* ]]; then
            sed -i '/^URIs:/ { /security/! s#.*#URIs: http://deb.debian.org/debian/# }' /etc/apt/sources.list.d/debian.sources
            sed -i '/^URIs:/ { /security/ s#.*#URIs: http://deb.debian.org/debian-security/# }' /etc/apt/sources.list.d/debian.sources
        else
            sed -i '/^URIs:/ { /security/! s#.*#URIs: '"$mirror"'/debian/# }' /etc/apt/sources.list.d/debian.sources
            sed -i '/^URIs:/ { /security/ s#.*#URIs: '"$mirror"'/debian-security/# }' /etc/apt/sources.list.d/debian.sources
        fi
        
    elif [ -f "/etc/apt/sources.list.d/ubuntu.sources" ]; then
        backup_file "/etc/apt/sources.list.d/ubuntu.sources"
        
        if [[ "$mirror" == *"archive.ubuntu.com"* ]]; then
            sed -i '/^URIs:/ s#.*#URIs: http://archive.ubuntu.com/ubuntu/#' /etc/apt/sources.list.d/ubuntu.sources
        else
            sed -i '/^URIs:/ s#.*#URIs: '"$mirror"'/ubuntu/#' /etc/apt/sources.list.d/ubuntu.sources
        fi
        
    else
        backup_file "/etc/apt/sources.list"
        
        if [ "$distro" = "debian" ]; then
            if [[ "$mirror" == *"deb.debian.org"* ]]; then
                mirror="http://deb.debian.org"
            fi
            cat > /etc/apt/sources.list <<EOF
deb $mirror/debian/ $VERSION_CODENAME main contrib non-free non-free-firmware
deb $mirror/debian/ $VERSION_CODENAME-updates main contrib non-free non-free-firmware
deb $mirror/debian/ $VERSION_CODENAME-backports main contrib non-free non-free-firmware
deb $mirror/debian-security/ $VERSION_CODENAME-security main contrib non-free non-free-firmware
EOF
        elif [ "$distro" = "ubuntu" ]; then
            if [[ "$mirror" == *"archive.ubuntu.com"* ]]; then
                mirror="http://archive.ubuntu.com"
            fi
            cat > /etc/apt/sources.list <<EOF
deb $mirror/ubuntu/ $VERSION_CODENAME main restricted universe multiverse
deb $mirror/ubuntu/ $VERSION_CODENAME-updates main restricted universe multiverse
deb $mirror/ubuntu/ $VERSION_CODENAME-backports main restricted universe multiverse
deb $mirror/ubuntu/ $VERSION_CODENAME-security main restricted universe multiverse
EOF
        fi
    fi
    
    echo "配置完成！正在更新软件源..."
    apt update
}

configure_kali() {
    local mirror=$1
    backup_file "/etc/apt/sources.list"
    
    cat > /etc/apt/sources.list <<EOF
deb $mirror/kali kali-rolling main non-free non-free-firmware contrib
deb-src $mirror/kali kali-rolling main non-free non-free-firmware contrib
EOF
    
    echo "配置完成！正在更新软件源..."
    apt update
}

configure_arch() {
    local mirror=$1
    backup_file "/etc/pacman.d/mirrorlist"
    
    cat > /etc/pacman.d/mirrorlist <<EOF
Server = $mirror/\$repo/os/\$arch
EOF
    
    echo "配置完成！正在更新软件源..."
    pacman -Syy
}

configure_fedora() {
    local mirror=$1
    
    backup_file "/etc/yum.repos.d/fedora.repo"
    backup_file "/etc/yum.repos.d/fedora-updates.repo"
    
    cat > /etc/yum.repos.d/fedora.repo <<EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=$mirror/fedora/releases/\$releasever/Everything/\$basearch/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF

    cat > /etc/yum.repos.d/fedora-updates.repo <<EOF
[updates]
name=Fedora \$releasever - \$basearch - Updates
baseurl=$mirror/fedora/updates/\$releasever/Everything/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever-\$basearch
EOF
    
    echo "配置完成！正在更新软件源..."
    dnf makecache
}

configure_rhel_based() {
    local mirror=$1
    local distro=$2
    
    case $distro in
        centos)
            if [ -f "/etc/yum.repos.d/CentOS-Base.repo" ]; then
                backup_file "/etc/yum.repos.d/CentOS-Base.repo"
                sed -e "s|^mirrorlist=|#mirrorlist=|g" \
                    -e "s|^#baseurl=.*|baseurl=$mirror/centos/\$releasever/BaseOS/\$basearch/os/|g" \
                    -i /etc/yum.repos.d/CentOS-Base.repo
            fi
            ;;
        rocky)
            for file in /etc/yum.repos.d/rocky*.repo; do
                [ -f "$file" ] && backup_file "$file"
                sed -e "s|^mirrorlist=|#mirrorlist=|g" \
                    -e "s|^#baseurl=.*|baseurl=$mirror/rocky/\$releasever/BaseOS/\$basearch/os/|g" \
                    -i "$file"
            done
            ;;
        almalinux)
            for file in /etc/yum.repos.d/almalinux*.repo; do
                [ -f "$file" ] && backup_file "$file"
                sed -e "s|^mirrorlist=|#mirrorlist=|g" \
                    -e "s|^#baseurl=.*|baseurl=$mirror/almalinux/\$releasever/BaseOS/\$basearch/os/|g" \
                    -i "$file"
            done
            ;;
    esac
    
    echo "配置完成！正在更新软件源..."
    if command -v dnf &> /dev/null; then
        dnf makecache
    else
        yum makecache
    fi
}

configure_alpine() {
    local mirror=$1
    backup_file "/etc/apk/repositories"
    
    cat > /etc/apk/repositories <<EOF
$mirror/v${VERSION_ID}/main
$mirror/v${VERSION_ID}/community
EOF
    
    echo "配置完成！正在更新软件源..."
    apk update
}

configure_opensuse() {
    local mirror=$1
    
    zypper mr -da
    zypper ar -fcg $mirror/distribution/leap/\$releasever/repo/oss/ mirror-oss
    zypper ar -fcg $mirror/distribution/leap/\$releasever/repo/non-oss/ mirror-non-oss
    zypper ar -fcg $mirror/update/leap/\$releasever/oss/ mirror-update-oss
    zypper ar -fcg $mirror/update/leap/\$releasever/non-oss/ mirror-update-non-oss
    
    echo "配置完成！正在更新软件源..."
    zypper ref
}

# 应用配置
echo ""
echo "正在应用配置..."

case $OS_ID in
    debian)
        configure_debian_ubuntu "$fastest_mirror" "debian"
        ;;
    ubuntu)
        configure_debian_ubuntu "$fastest_mirror" "ubuntu"
        ;;
    kali)
        configure_kali "$fastest_mirror"
        ;;
    arch|manjaro|endeavouros)
        configure_arch "$fastest_mirror"
        ;;
    fedora)
        configure_fedora "$fastest_mirror"
        ;;
    centos)
        configure_rhel_based "$fastest_mirror" "centos"
        ;;
    rocky)
        configure_rhel_based "$fastest_mirror" "rocky"
        ;;
    almalinux)
        configure_rhel_based "$fastest_mirror" "almalinux"
        ;;
    alpine)
        configure_alpine "$fastest_mirror"
        ;;
    opensuse*)
        configure_opensuse "$fastest_mirror"
        ;;
esac

echo ""
echo "========================================"
echo "配置完成！已将镜像源设置为: $fastest_name"
echo "位置: ${COUNTRY:-未知} ${CITY:-}"
echo "感谢使用！"
echo "========================================"
