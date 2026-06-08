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

# ==================== 运行模式选择 ====================
select_mode() {
    print "📋 请选择运行模式" "$BLUE"
    echo "1) 服务端 - 部署为 VPN 服务器"
    echo "2) 客户端 - 部署为 VPN 客户端"
    read -p "请输入 [1-2]（默认 1）: " MODE_CHOICE
    if [ "$MODE_CHOICE" = "2" ]; then
        RUN_MODE="client"
        print "✅ 已选择客户端模式" "$GREEN"
    else
        RUN_MODE="server"
        print "✅ 已选择服务端模式" "$GREEN"
    fi
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
download_startup_script() {
    local src_script
    if [ "$RUN_MODE" = "client" ]; then
        src_script="client.sh"
        print "📋 客户端模式：使用 client.sh 模板" "$BLUE"
    else
        src_script="ppp.sh"
        print "📋 服务端模式：使用 ppp.sh 模板" "$BLUE"
    fi

    prompt_replace_file "/opt/ppp/ppp.sh" \
        "${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/${src_script}" \
        "ppp.sh (${RUN_MODE} 模式)" || return 1
    chmod +x /opt/ppp/ppp.sh

    # 客户端模式：提示用户选择配置文件
    if [ "$RUN_MODE" = "client" ]; then
        print "📄 请将您的客户端 JSON 配置文件放入 /opt/ppp/ 目录" "$YELLOW"
        print "📄 然后运行选项 9 选择配置文件" "$YELLOW"
    fi
    return 0
}

# ==================== 1) 服务端 - 完整安装 ====================
auto_install() {
    select_mode
    select_proxy
    select_repo
    install_deps || return 1
    download_main_binary || return 1
    download_startup_script || return 1

    if [ "$RUN_MODE" = "server" ]; then
        # 服务端：自动配置 appsettings.json
        read -p "是否自行修改 appsettings.json？(y/n): " SELF
        if [[ "$SELF" =~ ^[Yy]$ ]]; then
            print "请手动修改 /opt/ppp/appsettings.json 后运行选项 2" "$YELLOW"
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
    else
        # 客户端：提示用户自行放入配置文件
        print "📄 请将您的客户端 JSON 配置文件放入 /opt/ppp/ 目录" "$YELLOW"
        print "📄 然后运行选项 9 选择要使用的配置文件" "$YELLOW"
        read -p "按 Enter 键继续安装系统服务..." 
    fi

    setup_systemd_service || return 1

    if systemctl is-active --quiet ppp.service; then
        print "🎉 安装成功！服务已启动" "$GREEN"
        create_ppp_shortcut
    else
        print "⚠️ 服务启动失败，请检查日志" "$YELLOW"
    fi
}

# ==================== 2) 服务端 - 仅配置系统服务 ====================
configure_service_only() {
    if [ ! -f "/opt/ppp/appsettings.json" ]; then
        print "❌ 未找到 appsettings.json" "$RED"
        return 1
    fi
    if [ ! -f "/opt/ppp/ppp" ]; then
        print "❌ 未找到 ppp 二进制文件，请先运行选项 3 下载" "$RED"
        return 1
    fi
    cd /opt/ppp || { print "❌ /opt/ppp 目录不存在" "$RED"; return 1; }
    select_mode
    select_proxy
    download_startup_script || return 1
    setup_systemd_service || return 1
    print "✅ 系统服务配置完成并启动" "$GREEN"
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
    print "✅ 二进制更新完毕，如需生效请重启服务 (选项 4)" "$GREEN"
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

# ==================== 9) 客户端配置切换 ====================
configure_client_json() {
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
# openppp2 启动脚本（客户端模式）- 由选项 9 自动生成
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
    echo "1) 安装 - 完整安装（可选服务端/客户端）"
    echo "2) 服务端 - 仅配置系统服务（不更新二进制）"
    echo "3) 通用 - 更新二进制文件"
    echo "4) 通用 - 重启服务"
    echo "5) 通用 - 停止服务"
    echo "6) 通用 - 查看运行状态 (tmux 界面，Ctrl+B D 退出)"
    echo "7) 通用 - 完全卸载"
    echo "8) 更新本脚本"
    echo "9) 客户端 - 切换配置文件"
    echo "10) 退出"
    read -p "请输入选项 [1-10]: " OPERATION
    case "$OPERATION" in
        1) auto_install ;;
        2) configure_service_only ;;
        3) update_binary_only ;;
        4) restart_service ;;
        5) stop_service ;;
        6) show_status ;;
        7) uninstall_ppp ;;
        8) update_script ;;
        9) configure_client_json ;;
        10) print "👋 退出" "$GREEN"; exit 0 ;;
        *) print "❌ 无效选项" "$RED" ;;
    esac
    echo; read -p "按 Enter 键返回主菜单..."
done
