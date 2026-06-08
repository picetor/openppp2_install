#!/bin/bash
# =============================================================================
# openppp2 一键安装脚本（v4.5 服务端/客户端双模式 + tmux 管理）
# - liulilittle: 全兼容，按特性自动选择最佳版本
# - Miaocchi: 低 glibc 系统自动选 debian10 包，高版本按特性选择
# - 纯 bash glibc 检测（无 bc 依赖）
# - 自动安装 libunwind + tmux
# - 状态查看改用 tmux attach，完美显示 TUI
# =============================================================================

set -o pipefail

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; RESET='\033[0m'
print() { echo -e "${2:-$GREEN}$1${RESET}" >&2; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ==================== 快捷命令 ====================
create_ppp_shortcut() {
    if [ ! -f "/usr/local/bin/ppp" ]; then
        cat > /usr/local/bin/ppp << 'EOF'
#!/bin/bash
if [ -f "/root/ppp_install.sh" ]; then
    bash /root/ppp_install.sh
else
    echo "❌ 脚本文件不存在，请重新下载"
    echo "wget -4 -O /root/ppp_install.sh https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    echo "chmod +x /root/ppp_install.sh"
fi
EOF
        chmod +x /usr/local/bin/ppp
        print "✅ 已创建 ppp 快捷命令！" "$GREEN"
    else
        print "✅ ppp 快捷命令已存在" "$GREEN"
    fi
}

# ==================== 系统检测 ====================
has_aesni() { grep -qi 'aes' /proc/cpuinfo 2>/dev/null; }
kernel_supports_io_uring() {
    local major minor
    local raw
    raw=$(uname -r)
    major="${raw%%.*}"
    minor="${raw#*.}"
    minor="${minor%%.*}"
    [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 10 ]; }
}
has_tc() { command_exists tc; }

# ==================== glibc 检测（纯 bash，无 bc 依赖） ====================
glibc_lt_238() {
    local ver major minor
    ver=$(ldd --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1)
    [ -z "$ver" ] && return 1
    major="${ver%%.*}"
    minor="${ver#*.}"
    [ "$major" -lt 2 ] && return 0
    [ "$major" -eq 2 ] && [ "$minor" -lt 38 ] && return 0
    return 1
}

# ==================== libunwind 安装 ====================
install_libunwind() {
    if ldconfig -p 2>/dev/null | grep -q 'libunwind\.so\.8'; then
        print "✅ libunwind.so.8 已存在" "$GREEN"
        return 0
    fi
    print "🔧 检测到缺少 libunwind.so.8，正在安装..." "$YELLOW"
    if command_exists apt-get; then
        apt-get update -qq && apt-get install -y -qq libunwind8
    elif command_exists dnf; then
        dnf install -y -q libunwind
    elif command_exists yum; then
        yum install -y -q libunwind
    else
        print "❌ 无法识别包管理器，请手动安装 libunwind" "$RED"
        return 1
    fi
    ldconfig -p 2>/dev/null | grep -q 'libunwind\.so\.8' && { print "✅ libunwind 安装成功" "$GREEN"; return 0; }
    print "❌ libunwind 安装失败" "$RED"
    return 1
}

# ==================== 代理选择 ====================
select_proxy() {
    print "🌍 是否使用国内加速代理？" "$BLUE"
    read -p "输入 y 使用加速，直接回车直连: " USE_PROXY
    if [[ "$USE_PROXY" =~ ^[Yy]$ ]]; then
        GITHUB_PROXY="https://git.apad.pro/"
        print "✅ 启用加速" "$GREEN"
    else
        GITHUB_PROXY=""
        print "✅ 直连 GitHub" "$YELLOW"
    fi
}

# ==================== 仓库选择 ====================
select_repo() {
    print "📦 请选择 openppp2 仓库" "$BLUE"
    echo "1) liulilittle/openppp2 (原版，全兼容，按特性优化)"
    echo "2) Miaocchi/openppp2   (扩展版，低版本系统自动兼容)"
    read -p "请输入 [1-2]（默认 1）: " REPO_CHOICE
    if [ "$REPO_CHOICE" = "2" ]; then
        REPO_OWNER="Miaocchi"
        print "✅ 已选择 Miaocchi/openppp2" "$GREEN"
    else
        REPO_OWNER="liulilittle"
        print "✅ 已选择 liulilittle/openppp2（全兼容）" "$GREEN"
    fi
}

# ==================== 智能版本选择 ====================
choose_best_zip() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64|amd64)
            if [ "$REPO_OWNER" = "liulilittle" ]; then
                if kernel_supports_io_uring && has_aesni && has_tc; then
                    echo "openppp2-linux-amd64-tc-io-uring-simd.zip"
                elif kernel_supports_io_uring && has_aesni; then
                    echo "openppp2-linux-amd64-io-uring-simd.zip"
                elif kernel_supports_io_uring && has_tc; then
                    echo "openppp2-linux-amd64-tc-io-uring.zip"
                elif kernel_supports_io_uring; then
                    echo "openppp2-linux-amd64-io-uring.zip"
                elif has_aesni && has_tc; then
                    echo "openppp2-linux-amd64-tc-simd.zip"
                elif has_aesni; then
                    echo "openppp2-linux-amd64-simd.zip"
                elif has_tc; then
                    echo "openppp2-linux-amd64-tc.zip"
                else
                    echo "openppp2-linux-amd64.zip"
                fi
                return
            fi

            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                if glibc_lt_238; then
                    print "💡 检测到 glibc 版本较低，自动选用 Debian 10 兼容包" "$YELLOW"
                    echo "openppp2-linux-amd64-debian10.zip"
                    return
                fi
                if kernel_supports_io_uring && has_aesni && has_tc; then
                    echo "openppp2-linux-amd64-tc-io-uring-simd.zip"
                elif kernel_supports_io_uring && has_aesni; then
                    echo "openppp2-linux-amd64-io-uring-simd.zip"
                elif kernel_supports_io_uring && has_tc; then
                    echo "openppp2-linux-amd64-tc-io-uring.zip"
                elif kernel_supports_io_uring; then
                    echo "openppp2-linux-amd64-io-uring.zip"
                elif has_aesni && has_tc; then
                    echo "openppp2-linux-amd64-tc-simd.zip"
                elif has_aesni; then
                    echo "openppp2-linux-amd64-simd.zip"
                elif has_tc; then
                    echo "openppp2-linux-amd64-tc.zip"
                else
                    echo "openppp2-linux-amd64.zip"
                fi
                return
            fi
            ;;
        aarch64|arm64)
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-aarch64-cross.zip"
            else
                if kernel_supports_io_uring && has_tc; then
                    echo "openppp2-linux-aarch64-tc-io-uring.zip"
                elif kernel_supports_io_uring; then
                    echo "openppp2-linux-aarch64-io-uring.zip"
                elif has_tc; then
                    echo "openppp2-linux-aarch64-tc.zip"
                else
                    echo "openppp2-linux-aarch64.zip"
                fi
            fi
            ;;
        armv7l|armv7)
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-armv7l-cross.zip"
            else
                if kernel_supports_io_uring; then
                    echo "openppp2-linux-armv7l-io-uring.zip"
                else
                    echo "openppp2-linux-armv7l.zip"
                fi
            fi
            ;;
        mips|mipsel)
            [ "$REPO_OWNER" = "Miaocchi" ] && echo "openppp2-linux-mipsel-cross.zip" || echo "openppp2-linux-mipsel.zip"
            ;;
        ppc64le|ppc64el)
            [ "$REPO_OWNER" = "Miaocchi" ] && echo "openppp2-linux-ppc64el-cross.zip" || echo "openppp2-linux-ppc64el.zip"
            ;;
        riscv64)
            [ "$REPO_OWNER" = "Miaocchi" ] && echo "openppp2-linux-riscv64-cross.zip" || echo "openppp2-linux-riscv64.zip"
            ;;
        s390x)
            [ "$REPO_OWNER" = "Miaocchi" ] && echo "openppp2-linux-s390x-cross.zip" || echo "openppp2-linux-s390x.zip"
            ;;
        *) print "❌ 不支持的架构: $arch" "$RED"; exit 1 ;;
    esac
}

# ==================== 下载函数 ====================
prompt_replace_file() {
    local target_path="$1" url="$2" desc="$3"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ]; then
        print "⚠️  $desc 已存在" "$YELLOW"
        read -p "是否替换？(y/n): " REPLACE
        [[ ! "$REPLACE" =~ ^[Yy]$ ]] && return 0
    fi
    print "📥 正在下载 $desc ..." "$BLUE"
    if wget -4 --no-check-certificate -q --show-progress -O "$target_path" "$url" 2>/dev/null; then
        print "✅ $desc 下载完成" "$GREEN"; return 0
    elif wget -6 --no-check-certificate -q --show-progress -O "$target_path" "$url" 2>/dev/null; then
        print "✅ $desc 下载完成 (IPv6)" "$GREEN"; return 0
    else
        print "❌ $desc 下载失败！" "$RED"; return 1
    fi
}

# ==================== 依赖安装（含 tmux） ====================
install_deps() {
    print "🔧 安装基础依赖 (jq, uuid, unzip, tmux)..." "$BLUE"
    if command_exists apt-get; then
        apt-get update -qq && apt-get install -y -qq jq uuid-runtime unzip tmux
    elif command_exists dnf; then
        dnf install -y -q jq util-linux unzip tmux
    elif command_exists yum; then
        yum install -y -q jq util-linux unzip tmux
    else
        print "❌ 无法识别包管理器" "$RED"; return 1
    fi
    command_exists jq && command_exists unzip && command_exists tmux || { print "❌ 依赖安装失败" "$RED"; return 1; }
    # 原版 liulilittle 为静态编译，无需 libunwind；仅 Miaocchi 扩展版需要
    if [ "$REPO_OWNER" = "Miaocchi" ]; then
        install_libunwind || return 1
    else
        print "🔍 原版仓库为静态编译，跳过 libunwind 安装" "$YELLOW"
    fi
    print "✅ 所有依赖就绪" "$GREEN"
    return 0
}

# ==================== 下载解压主程序 ====================
download_main_binary() {
    local zip_name url
    zip_name=$(choose_best_zip)
    print "🔍 最优版本：$zip_name (仓库: $REPO_OWNER)" "$BLUE"

    mkdir -p /opt/ppp || return 1
    cd /opt/ppp || return 1

    url="${GITHUB_PROXY}https://github.com/${REPO_OWNER}/openppp2/releases/latest/download/${zip_name}"
    prompt_replace_file "/opt/ppp/${zip_name}" "$url" "$zip_name" || return 1

    command_exists unzip || { print "❌ 未安装 unzip" "$RED"; return 1; }
    if unzip -o "$zip_name" ppp -d . && chmod +x ppp; then
        rm -f "$zip_name"
        print "✅ openppp2 二进制准备完成" "$GREEN"
        # 替换赋权后自动重启服务
        if systemctl is-active --quiet ppp.service 2>/dev/null; then
            print "🔄 正在重启服务..." "$BLUE"
            systemctl restart ppp.service && print "✅ 服务已重启" "$GREEN" || print "⚠️ 重启失败" "$YELLOW"
        fi
        return 0
    else
        print "❌ 解压失败" "$RED"
        return 1
    fi
}

# ==================== systemd 服务 ====================
setup_systemd_service() {
    local service_url="${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/ppp.service"
    prompt_replace_file "/etc/systemd/system/ppp.service" "$service_url" "ppp.service" || return 1
    chmod 644 /etc/systemd/system/ppp.service
    systemctl daemon-reload
    systemctl enable --now ppp.service
}

# ==================== 下载启动脚本（统一命名为 ppp.sh） ====================
# 参数 $1: 模式名称，server 或 client
download_startup_script() {
    local mode="$1"
    local src_script
    if [ "$mode" = "client" ]; then
        src_script="client.sh"
        print "📋 客户端模式：使用 client.sh 模板" "$BLUE"
    else
        src_script="ppp.sh"
        print "📋 服务端模式：使用 ppp.sh 模板" "$BLUE"
    fi

    prompt_replace_file "/opt/ppp/ppp.sh" \
        "${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/${src_script}" \
        "ppp.sh (${mode} 模式)" || return 1
    chmod +x /opt/ppp/ppp.sh

    if [ "$mode" = "client" ]; then
        print "📄 请将您的客户端 JSON 配置文件放入 /opt/ppp/ 目录" "$YELLOW"
        print "📄 然后运行选项 2.3 选择配置文件" "$YELLOW"
    fi
    return 0
}

# ==================== 1.1) 服务端 - 完整自动安装 ====================
server_install() {
    select_proxy
    select_repo
    install_deps || return 1
    download_main_binary || return 1
    download_startup_script server || return 1

    read -p "是否自行修改 appsettings.json？(y/n): " SELF
    if [[ "$SELF" =~ ^[Yy]$ ]]; then
        print "请手动修改 /opt/ppp/appsettings.json 后运行选项 1.2" "$YELLOW"
        create_ppp_shortcut
        return 0
    fi

    prompt_replace_file "/opt/ppp/appsettings.json" \
        "${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/appsettings.json" \
        "appsettings.json" || return 1

    read -p "服务器 IP（默认 0.0.0.0）: " NEW_IP
    read -p "端口（默认 20000）: " NEW_PORT
    read -p "GUID（留空自动生成）: " NEW_GUID
    NEW_IP=${NEW_IP:-0.0.0.0}
    NEW_PORT=${NEW_PORT:-20000}
    [[ -z "$NEW_GUID" ]] && NEW_GUID=$(uuidgen)

    PROTOCOL_KEY=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)
    TRANSPORT_KEY=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)

    cd /opt/ppp || return 1
    cp -f appsettings.json appsettings.json.bak 2>/dev/null

    jq --indent 4 \
        --arg ip "$NEW_IP" \
        --arg port "$NEW_PORT" \
        --arg guid "$NEW_GUID" \
        --arg pkey "$PROTOCOL_KEY" \
        --arg tkey "$TRANSPORT_KEY" '
        .tcp.listen.port = ($port|tonumber) |
        .udp.listen.port = ($port|tonumber) |
        .udp.static.servers[0] = ($ip + ":" + $port) |
        .client.server = ("ppp://" + $ip + ":" + $port + "/") |
        .client.guid = $guid |
        .key."protocol-key" = $pkey |
        .key."transport-key" = $tkey
    ' appsettings.json > temp.json && mv temp.json appsettings.json || {
        print "❌ 配置修改失败" "$RED"; rm -f temp.json; return 1
    }

    # BDP 窗口优化（自动 ping 检测延迟）
    read -p "是否根据带宽优化 RWND/CWND 窗口？(y/n): " OPT_BDP
    if [[ "$OPT_BDP" =~ ^[Yy]$ ]]; then
        local detected_ip rtt_ms bw window_pow
        detected_ip=$(extract_server_ip)
        if [ -n "$detected_ip" ]; then
            print "📡 检测到服务器 IP: $detected_ip，正在 Ping 测延迟..." "$BLUE"
            rtt_ms=$(ping_rtt "$detected_ip")
            if [ -n "$rtt_ms" ]; then
                rtt_ms=$(printf "%.0f" "$rtt_ms" 2>/dev/null || echo "$rtt_ms")
                print "✅ Ping $detected_ip 延迟: ${rtt_ms}ms" "$GREEN"
            else
                print "⚠️ Ping 超时，请手动输入延迟" "$YELLOW"
            fi
        fi
        read -p "带宽 (Mbps，如 100): " bw
        if [[ "$bw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            if [ -z "$rtt_ms" ]; then
                read -p "延迟 RTT (ms，如 63): " rtt_ms
            fi
            if [[ "$rtt_ms" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                window_pow=$(bdp_calculate_windows "$bw" "$rtt_ms")
                jq --indent 4 \
                    --arg cwnd "$window_pow" \
                    --arg rwnd "$((window_pow * 2))" '
                    .udp.cwnd = ($cwnd|tonumber) |
                    .udp.rwnd = ($rwnd|tonumber)
                ' appsettings.json > temp.json && mv temp.json appsettings.json
                print "✅ BDP 优化已应用: CWND=$window_pow, RWND=$((window_pow * 2))" "$GREEN"
            else
                print "⚠️ 延迟无效，跳过 BDP 优化" "$YELLOW"
            fi
        else
            print "⚠️ 带宽无效，跳过 BDP 优化" "$YELLOW"
        fi
    fi

    setup_systemd_service || return 1

    if systemctl is-active --quiet ppp.service; then
        print "🎉 服务端安装成功！服务已启动" "$GREEN"
        create_ppp_shortcut
    else
        print "⚠️ 服务启动失败，请检查日志" "$YELLOW"
    fi
}

# ==================== 2.1) 客户端 - 完整自动安装 ====================
client_install() {
    select_proxy
    select_repo
    install_deps || return 1
    download_main_binary || return 1
    download_startup_script client || return 1

    print "📄 请将您的客户端 JSON 配置文件放入 /opt/ppp/ 目录" "$YELLOW"
    print "📄 然后运行选项 2.3 选择要使用的配置文件" "$YELLOW"
    read -p "按 Enter 键继续安装系统服务..." 

    setup_systemd_service || return 1

    if systemctl is-active --quiet ppp.service; then
        print "🎉 客户端安装成功！服务已启动" "$GREEN"
        create_ppp_shortcut
    else
        print "⚠️ 服务启动失败，请检查日志" "$YELLOW"
    fi
}

# ==================== 1.2) 服务端 - 仅配置系统服务 ====================
server_configure_service() {
    if [ ! -f "/opt/ppp/appsettings.json" ]; then
        print "❌ 未找到 appsettings.json" "$RED"
        return 1
    fi
    if [ ! -f "/opt/ppp/ppp" ]; then
        print "❌ 未找到 ppp 二进制文件，请先运行选项 1.1 或 3 下载" "$RED"
        return 1
    fi
    cd /opt/ppp || { print "❌ /opt/ppp 目录不存在" "$RED"; return 1; }
    select_proxy
    download_startup_script server || return 1
    setup_systemd_service || return 1
    print "✅ 服务端系统服务配置完成并启动" "$GREEN"
}

# ==================== 2.2) 客户端 - 仅配置系统服务 ====================
client_configure_service() {
    if [ ! -f "/opt/ppp/ppp" ]; then
        print "❌ 未找到 ppp 二进制文件，请先运行选项 2.1 或 3 下载" "$RED"
        return 1
    fi
    cd /opt/ppp || { print "❌ /opt/ppp 目录不存在" "$RED"; return 1; }
    select_proxy
    download_startup_script client || return 1
    setup_systemd_service || return 1
    print "✅ 客户端系统服务配置完成并启动" "$GREEN"
}

# ==================== 3) 更新二进制 ====================
update_binary_only() {
    select_proxy
    select_repo
    # 原版 liulilittle 为静态编译，无需 libunwind；仅 Miaocchi 扩展版需要
    if [ "$REPO_OWNER" = "Miaocchi" ]; then
        install_libunwind || return 1
    else
        print "🔍 原版仓库为静态编译，跳过 libunwind 安装" "$YELLOW"
    fi
    download_main_binary || return 1
}

# ==================== 4) 重启服务 ====================
restart_service() { systemctl restart ppp.service && print "✅ 服务已重启" "$GREEN"; }

# ==================== 5) 停止服务 ====================
stop_service() { systemctl stop ppp.service && print "✅ 服务已停止" "$GREEN"; }

# ==================== 6) 查看运行状态（tmux attach） ====================
show_status() {
    if ! command_exists tmux; then
        print "❌ tmux 未安装，无法查看状态" "$RED"
        return 1
    fi
    if tmux has-session -t ppp 2>/dev/null; then
        print "📺 正在连接到 ppp 会话 (按 Ctrl+B 然后按 D 退出界面)" "$BLUE"
        sleep 1
        tmux attach -t ppp
    else
        print "⚠️ ppp tmux 会话不存在，服务可能未运行" "$YELLOW"
        echo
        print "=== ppp.service 状态 ===" "$BLUE"
        systemctl status ppp.service --no-pager -l
    fi
}

# ==================== 7) 卸载 ====================
uninstall_ppp() {
    print "🗑️ 开始卸载..." "$YELLOW"
    systemctl stop ppp.service 2>/dev/null
    systemctl disable ppp.service 2>/dev/null
    rm -f /etc/systemd/system/ppp.service
    systemctl daemon-reload
    print "是否保留配置文件？（默认保留）" "$BLUE"
    read -p "输入 y 保留，n 删除: " KEEP_CONFIG
    if [[ "$KEEP_CONFIG" =~ ^[Nn]$ ]]; then
        rm -rf /opt/ppp && print "✅ 已删除所有文件" "$GREEN"
    else
        rm -f /opt/ppp/ppp /opt/ppp/ppp.sh /opt/ppp/openppp2-linux-*.zip 2>/dev/null
        print "✅ 已保留配置文件" "$GREEN"
    fi
    rm -f /usr/local/bin/ppp
    print "✅ 卸载完成" "$GREEN"
    exit 0
}

# ==================== 8) 更新脚本 ====================
update_script() {
    local u url
    print "🌍 更新本脚本" "$BLUE"
    echo "1) 国内加速"; echo "2) 直连 GitHub"
    read -p "选择 [1-2]（默认 2）: " u
    [ "$u" = "1" ] && url="https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh" || url="https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    wget -4 -O /root/ppp_install.sh "$url" && chmod +x /root/ppp_install.sh && { print "✅ 更新成功" "$GREEN"; exec /root/ppp_install.sh; } || print "❌ 更新失败" "$RED"
}

# ==================== 10) BDP 窗口计算器 ====================
# BDP = 带宽(bps) / 8 * RTT(秒)
# 窗口 = BDP / (MSS) ，取 2 的幂次
# ==================== BDP 计算核心 ====================
# 参数: $1=带宽(Mbps) $2=RTT(ms)
# 输出: window_pow (CWND 推荐值，2 的幂次)
bdp_calculate_windows() {
    local bw="$1" rtt_ms="$2"
    local bw_bps rtt_sec flight_bytes window_raw window_pow

    bw_bps=$(echo "$bw * 1000000" | bc 2>/dev/null)
    [ $? -ne 0 ] && bw_bps=$((bw * 1000000))

    rtt_sec=$(echo "scale=3; $rtt_ms / 1000" | bc 2>/dev/null || echo "0.$rtt_ms")

    flight_bytes=$(echo "scale=0; $bw_bps / 8 * $rtt_sec" | bc 2>/dev/null || echo "$((bw_bps / 8 * rtt_ms / 1000))")

    window_raw=$(echo "scale=0; $flight_bytes * $rtt_ms / 1000" | bc 2>/dev/null || echo "$((flight_bytes * rtt_ms / 1000))")
    [ "$window_raw" -lt 1 ] && window_raw=65536

    window_pow=1
    while [ $window_pow -lt $window_raw ]; do
        window_pow=$((window_pow << 1))
    done

    echo "$window_pow"
}

# ==================== 获取当前使用的配置文件路径 ====================
# 从 ppp.sh 中解析 --config=./xxx.json，回退到 appsettings.json
get_current_config() {
    if [ -f "/opt/ppp/ppp.sh" ]; then
        local config_file
        config_file=$(grep -oP '--config=\./\K[^'\''"]+' /opt/ppp/ppp.sh 2>/dev/null | head -1)
        if [ -n "$config_file" ] && [ -f "/opt/ppp/$config_file" ]; then
            echo "/opt/ppp/$config_file"
            return 0
        fi
    fi
    [ -f "/opt/ppp/appsettings.json" ] && echo "/opt/ppp/appsettings.json" && return 0
    return 1
}

# ==================== 从当前运行的配置提取服务器 IP ====================
# 优先从 ppp.sh 中读取 --config=./xxx.json 确定当前使用的配置文件
# 回退到 appsettings.json
extract_server_ip() {
    local cfg server_url ip_only

    # 1) 从 ppp.sh 中提取 --config=./xxx.json 参数
    if [ -f "/opt/ppp/ppp.sh" ]; then
        local config_file
        config_file=$(grep -oP '--config=\./\K[^'\''"]+' /opt/ppp/ppp.sh 2>/dev/null | head -1)
        if [ -n "$config_file" ] && [ -f "/opt/ppp/$config_file" ]; then
            cfg="/opt/ppp/$config_file"
        fi
    fi

    # 2) 回退到默认 appsettings.json
    if [ -z "$cfg" ] || [ ! -f "$cfg" ]; then
        cfg="/opt/ppp/appsettings.json"
    fi

    [ ! -f "$cfg" ] && return 1

    # 提取 ppp://ip:port 中的 IP
    server_url=$(jq -r '.client.server // empty' "$cfg" 2>/dev/null)
    [ -z "$server_url" ] && return 1

    # 去掉 ppp:// 前缀，取 : 之前的部分
    ip_only="${server_url#ppp://}"
    ip_only="${ip_only%%:*}"

    # 排除 0.0.0.0 和 :: 等通配地址
    [ "$ip_only" = "0.0.0.0" ] && return 1
    [ "$ip_only" = "::" ] && return 1
    [ "$ip_only" = "*" ] && return 1

    echo "$ip_only"
    return 0
}

# ==================== Ping 测延迟 ====================
# 参数: $1=IP 地址
# 输出: 平均延迟(ms)，失败返回空
ping_rtt() {
    local ip="$1" avg
    # 发 3 个包，超时 2 秒，取平均
    avg=$(ping -c 3 -W 2 "$ip" 2>/dev/null | tail -1 | grep -oP '([0-9.]+)(?=/\d+\.\d+/\d+\.\d+)' | head -1)
    [ -z "$avg" ] && avg=$(ping -c 3 -W 2 "$ip" 2>/dev/null | grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9.]+')
    echo "$avg"
}

# ==================== 2.4) BDP 窗口计算器 ====================
bdp_calculator() {
    print "📐 BDP 窗口计算器" "$BLUE"
    echo "根据带宽和延迟计算最优 RWND/CWND 值"
    echo "公式: 窗口 ≈ 带宽(bps) / 8 * RTT² / 1000"
    echo

    # Ping 1.1.1.1 自动测延迟，失败则手动输入
    local rtt_ms
    print "📡 正在 Ping 1.1.1.1 测延迟..." "$BLUE"
    rtt_ms=$(ping_rtt "1.1.1.1")
    if [ -n "$rtt_ms" ]; then
        rtt_ms=$(printf "%.0f" "$rtt_ms" 2>/dev/null || echo "$rtt_ms")
        print "✅ 延迟: ${rtt_ms}ms" "$GREEN"
    else
        print "⚠️ Ping 超时，请手动输入延迟" "$YELLOW"
    fi

    read -p "带宽 (Mbps，如 100): " BW
    [[ ! "$BW" =~ ^[0-9]+(\.[0-9]+)?$ ]] && { print "❌ 带宽必须为数字" "$RED"; return 1; }

    if [ -z "$rtt_ms" ]; then
        read -p "延迟 RTT (ms，如 63): " RTT_MS
        [[ ! "$RTT_MS" =~ ^[0-9]+(\.[0-9]+)?$ ]] && { print "❌ 延迟必须为数字" "$RED"; return 1; }
    else
        RTT_MS=$rtt_ms
        echo "延迟 RTT: ${RTT_MS}ms (自动检测)"
    fi

    local window_pow window_kb window_mb
    window_pow=$(bdp_calculate_windows "$BW" "$RTT_MS")
    window_kb=$((window_pow / 1024))
    window_mb=$(echo "scale=2; $window_pow / 1048576" | bc 2>/dev/null || echo "$((window_pow / 1048576))")

    echo
    print "========== 计算结果 ==========" "$GREEN"
    echo "带宽:       ${BW} Mbps"
    echo "RTT:        ${RTT_MS} ms"
    echo "--------------------------------"
    echo "推荐 CWND:  $window_pow 字节 (${window_kb}K / ${window_mb}M)"
    echo "推荐 RWND:  $((window_pow * 2)) 字节 ($((window_kb * 2))K / $(echo "scale=2; $window_pow * 2 / 1048576" | bc 2>/dev/null)M)"
    echo "--------------------------------"
    echo "保守:       CWND=$((window_pow / 2))  RWND=$window_pow"
    echo "均衡:       CWND=$window_pow  RWND=$((window_pow * 2))"
    echo "激进:       CWND=$((window_pow * 2))  RWND=$((window_pow * 4))"
    echo
    print "💡 值取 2 的幂次可享受缓存行优化" "$YELLOW"

    # 写入当前使用的配置文件
    local target_cfg
    target_cfg=$(get_current_config)
    if [ -n "$target_cfg" ]; then
        local cfg_name
        cfg_name=$(basename "$target_cfg")
        read -p "是否将均衡配置写入 ${cfg_name}？(y/n): " WRITE
        if [[ "$WRITE" =~ ^[Yy]$ ]]; then
            local cfg_dir
            cfg_dir=$(dirname "$target_cfg")
            cd "$cfg_dir" || return 1
            cp -f "$cfg_name" "${cfg_name}.bak" 2>/dev/null
            jq --indent 4 \
                --arg cwnd "$window_pow" \
                --arg rwnd "$((window_pow * 2))" '
                .udp.cwnd = ($cwnd|tonumber) |
                .udp.rwnd = ($rwnd|tonumber)
            ' "$cfg_name" > temp.json && mv temp.json "$cfg_name" && {
                print "✅ 配置已写入 ${cfg_name}，请重启服务生效" "$GREEN"
            } || {
                print "❌ 写入失败" "$RED"; rm -f temp.json; return 1
            }
        fi
    else
        print "⚠️ 未找到配置文件，跳过写入" "$YELLOW"
    fi
}

# ==================== 2.3) 客户端 - 切换配置文件 ====================
client_switch_config() {
    print "🔧 客户端模式 - 切换配置文件" "$BLUE"
    [ ! -d "/opt/ppp" ] && mkdir -p /opt/ppp
    [ ! -f "/opt/ppp/ppp" ] && { print "❌ 未找到 ppp 二进制" "$RED"; return 1; }
    mapfile -t js < <(find /opt/ppp -maxdepth 1 -name "*.json" -type f -printf "%f\n" 2>/dev/null)
    [ ${#js[@]} -eq 0 ] && { print "❌ 无 JSON 配置文件" "$RED"; return 1; }
    print "📄 可选配置：" "$BLUE"
    for i in "${!js[@]}"; do echo "$((i+1))) ${js[$i]}"; done
    local c; read -p "选择: " c
    [[ ! "$c" =~ ^[0-9]+$ || "$c" -lt 1 || "$c" -gt ${#js[@]} ]] && { print "❌ 无效" "$RED"; return 1; }
    local s="${js[$((c-1))]}"

    # 直接重写 ppp.sh 为客户端模式，避免 sed 匹配问题
    cat > /opt/ppp/ppp.sh << EOF
#!/bin/bash
# openppp2 启动脚本（客户端模式）- 由选项 2.3 自动生成
cd /opt/ppp

tmux kill-session -t ppp 2>/dev/null

tmux new-session -d -s ppp './ppp --mode=client --config=./${s}'

sleep 1

echo "ppp 已在 tmux 会话中启动"
echo "查看界面: tmux attach -t ppp"
echo "退出界面: Ctrl+B 然后按 D"

while tmux has-session -t ppp 2>/dev/null; do
    sleep 5
done

echo "ppp 会话已结束，脚本退出"
EOF
    chmod +x /opt/ppp/ppp.sh
    print "✅ 已切换配置文件为: ${s}" "$GREEN"
    systemctl restart ppp.service && print "✅ 服务已重启" "$GREEN" || print "⚠️ 重启失败" "$YELLOW"
}

# ==================== 主菜单 ====================
create_ppp_shortcut
while true; do
    clear
    print "=============== openppp2 一键脚本（v4.5 服务端/客户端 + tmux 管理）===============" "$BLUE"
    echo "----- 服务端 -----"
    echo "1.1) 完整自动安装"
    echo "1.2) 仅配置系统服务"
    echo "----- 客户端 -----"
    echo "2.1) 完整自动安装"
    echo "2.2) 仅配置系统服务"
    echo "2.3) 切换配置文件"
    echo "2.4) BDP 窗口计算器"
    echo "----- 通用 -----"
    echo "3)  更新二进制文件"
    echo "4)  重启服务"
    echo "5)  停止服务"
    echo "6)  查看运行状态 (tmux 界面，Ctrl+B D 退出)"
    echo "7)  完全卸载"
    echo "8)  更新本脚本"
    echo "9)  退出"
    read -p "请输入选项: " OPERATION
    case "$OPERATION" in
        1.1|11) server_install ;;
        1.2|12) server_configure_service ;;
        2.1|21) client_install ;;
        2.2|22) client_configure_service ;;
        2.3|23) client_switch_config ;;
        2.4|24) bdp_calculator ;;
        3) update_binary_only ;;
        4) restart_service ;;
        5) stop_service ;;
        6) show_status ;;
        7) uninstall_ppp ;;
        8) update_script ;;
        9) print "👋 退出" "$GREEN"; exit 0 ;;
        *) print "❌ 无效选项" "$RED" ;;
    esac
    echo; read -p "按 Enter 键返回主菜单..."
done
