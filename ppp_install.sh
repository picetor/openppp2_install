#!/bin/bash
# =============================================================================
# openppp2 一键安装脚本（v4.3.1 修复版）
# 特性：
#   - 修复 zip_name 变量被 print 输出污染的问题
#   - 纯 bash glibc 版本检测（无需 bc）
#   - 自动安装 libunwind 依赖
#   - 双仓库支持（liulilittle / Miaocchi）
#   - 二进制兼容性验证及自动回退机制
# =============================================================================

set -o pipefail

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; RESET='\033[0m'
print() { echo -e "${2:-$GREEN}$1${RESET}" >&2; }  # 输出到 stderr，避免污染变量

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
    major=$(uname -r | cut -d. -f1)
    minor=$(uname -r | cut -d. -f2)
    [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 10 ]; }
}
has_tc() { command_exists tc; }

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
    if ldconfig -p 2>/dev/null | grep -q 'libunwind\.so\.8'; then
        print "✅ libunwind 安装成功" "$GREEN"
        return 0
    else
        print "❌ libunwind 安装失败" "$RED"
        return 1
    fi
}

# ==================== 代理 ====================
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
    echo "1) liulilittle/openppp2 (原版)"
    echo "2) Miaocchi/openppp2   (扩展版，推荐 Debian 12 用户)"
    read -p "请输入 [1-2]（默认 1）: " REPO_CHOICE
    if [ "$REPO_CHOICE" = "2" ]; then
        REPO_OWNER="Miaocchi"
        print "✅ 已选择 Miaocchi/openppp2" "$GREEN"
    else
        REPO_OWNER="liulilittle"
        print "✅ 已选择 liulilittle/openppp2" "$GREEN"
    fi
}

# ==================== 纯 bash 版本比较 ====================
glibc_lt_238() {
    local ver major minor
    ver=$(ldd --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+' | head -1)
    if [ -z "$ver" ]; then return 1; fi
    major="${ver%%.*}"
    minor="${ver#*.}"
    # 小于 2.38：major < 2，或者 major == 2 且 minor < 38
    [ "$major" -lt 2 ] && return 0
    [ "$major" -eq 2 ] && [ "$minor" -lt 38 ] && return 0
    return 1
}

# ==================== 智能选择版本（仅输出文件名到 stdout） ====================
choose_best_zip() {
    local arch
    arch=$(uname -m)

    # x86_64 且 glibc < 2.38 → debian10 包
    if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
        if glibc_lt_238; then
            print "💡 检测到 glibc 版本较低，自动选用 Debian 10 兼容包" "$YELLOW"
            echo "openppp2-linux-amd64-debian10.zip"
            return
        fi
    fi

    # 常规匹配
    case "$arch" in
        x86_64|amd64)
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
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-mipsel-cross.zip"
            else
                echo "openppp2-linux-mipsel.zip"
            fi
            ;;
        ppc64le|ppc64el)
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-ppc64el-cross.zip"
            else
                echo "openppp2-linux-ppc64el.zip"
            fi
            ;;
        riscv64)
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-riscv64-cross.zip"
            else
                echo "openppp2-linux-riscv64.zip"
            fi
            ;;
        s390x)
            if [ "$REPO_OWNER" = "Miaocchi" ]; then
                echo "openppp2-linux-s390x-cross.zip"
            else
                echo "openppp2-linux-s390x.zip"
            fi
            ;;
        *) 
            print "❌ 不支持的架构: $arch" "$RED"
            exit 1 
            ;;
    esac
}

# ==================== 下载 ====================
prompt_replace_file() {
    local target_path="$1" url="$2" desc="$3"
    mkdir -p "$(dirname "$target_path")"
    if [ -f "$target_path" ]; then
        print "⚠️  $desc 已存在" "$YELLOW"
        read -p "是否替换？(y/n): " REPLACE
        [[ ! "$REPLACE" =~ ^[Yy]$ ]] && return 0
    fi
    print "📥 正在下载 $desc ..." "$BLUE"
    if wget -4 --no-check-certificate -q --show-progress -O "$target_path" "$url"; then
        print "✅ $desc 下载完成" "$GREEN"
        return 0
    else
        print "❌ $desc 下载失败！" "$RED"
        return 1
    fi
}

# ==================== 依赖安装 ====================
install_deps() {
    print "🔧 安装基础依赖 (jq, uuid, unzip)..." "$BLUE"
    if command_exists apt-get; then
        apt-get update -qq && apt-get install -y -qq jq uuid-runtime unzip
    elif command_exists dnf; then
        dnf install -y -q jq util-linux unzip
    elif command_exists yum; then
        yum install -y -q jq util-linux unzip
    else
        print "❌ 无法识别包管理器" "$RED"
        return 1
    fi
    command_exists jq && command_exists unzip || { print "❌ 依赖安装失败" "$RED"; return 1; }
    install_libunwind || return 1
    print "✅ 所有依赖就绪" "$GREEN"
    return 0
}

# ==================== 解压并校验二进制 ====================
extract_and_verify() {
    local zip_name="$1"
    print "📦 解压并检查 $zip_name ..." "$BLUE"
    if ! unzip -o "$zip_name" ppp -d . ; then
        print "❌ 解压失败" "$RED"
        return 1
    fi
    chmod +x ppp

    print "🔎 检查二进制依赖是否满足..." "$BLUE"
    local miss
    miss=$(ldd ppp 2>&1 | grep "not found")
    if [ -z "$miss" ]; then
        print "✅ 二进制依赖完整，兼容当前系统" "$GREEN"
        return 0
    else
        print "❌ 二进制存在未满足的依赖:" "$RED"
        echo "$miss"
        return 1
    fi
}

# ==================== 下载主程序（含回退） ====================
download_main_binary() {
    local zip_name url fallback_name="openppp2-linux-amd64-debian10.zip"
    
    # 捕获 choose_best_zip 的 stdout（文件名）
    zip_name=$(choose_best_zip)
    print "🔍 最优版本：$zip_name (仓库: $REPO_OWNER)" "$BLUE"

    mkdir -p /opt/ppp || return 1
    cd /opt/ppp || return 1

    # 构造下载链接
    url="${GITHUB_PROXY}https://github.com/${REPO_OWNER}/openppp2/releases/latest/download/${zip_name}"
    
    # 下载首选版本
    if prompt_replace_file "/opt/ppp/${zip_name}" "$url" "$zip_name"; then
        if extract_and_verify "$zip_name"; then
            rm -f "$zip_name" 2>/dev/null
            return 0
        fi
    fi

    # 回退机制：仅在 x86_64 且首选不是 debian10 时触发
    if { [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "amd64" ]; } && [ "$zip_name" != "$fallback_name" ]; then
        print "⚠️ 当前版本不兼容，尝试回退到 Debian 10 兼容包 ..." "$YELLOW"
        rm -f "$zip_name" ppp 2>/dev/null

        url="${GITHUB_PROXY}https://github.com/${REPO_OWNER}/openppp2/releases/latest/download/${fallback_name}"
        if prompt_replace_file "/opt/ppp/${fallback_name}" "$url" "$fallback_name"; then
            if extract_and_verify "$fallback_name"; then
                rm -f "$fallback_name" 2>/dev/null
                print "✅ 回退成功，使用 Debian 10 兼容二进制" "$GREEN"
                return 0
            else
                rm -f "$fallback_name" ppp 2>/dev/null
            fi
        fi
        print "❌ 回退方案也失败了，请检查网络或手动下载" "$RED"
        return 1
    fi

    print "❌ 安装失败" "$RED"
    return 1
}

# ==================== systemd 服务 ====================
setup_systemd_service() {
    local service_url="${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/ppp.service"
    prompt_replace_file "/etc/systemd/system/ppp.service" "$service_url" "ppp.service" || return 1
    chmod 644 /etc/systemd/system/ppp.service
    systemctl daemon-reload
    systemctl enable --now ppp.service
}

# ==================== 1) 完整自动安装 ====================
auto_install() {
    select_proxy
    select_repo
    install_deps || return 1
    download_main_binary || return 1

    prompt_replace_file "/opt/ppp/ppp.sh" \
        "${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/ppp.sh" \
        "ppp.sh" || return 1
    chmod +x /opt/ppp/ppp.sh

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
        .client.server = ("ppp://" + $ip + ":" + $port) |
        .client.guid = $guid |
        .key."protocol-key" = $pkey |
        .key."transport-key" = $tkey
    ' appsettings.json > temp.json && mv temp.json appsettings.json || {
        print "❌ 配置修改失败" "$RED"
        rm -f temp.json
        return 1
    }

    setup_systemd_service || return 1

    if systemctl is-active --quiet ppp.service; then
        print "🎉 安装成功！服务已启动" "$GREEN"
        create_ppp_shortcut
    else
        print "⚠️ 服务启动失败，请检查日志" "$YELLOW"
    fi
}

# ==================== 2) 仅配置服务 ====================
configure_service_only() {
    if [ ! -f "/opt/ppp/appsettings.json" ]; then
        print "❌ 未找到 appsettings.json，请先运行选项 1" "$RED"
        return 1
    fi
    cd /opt/ppp || { print "❌ /opt/ppp 目录不存在" "$RED"; return 1; }
    select_proxy
    setup_systemd_service || return 1
    print "✅ 系统服务配置完成并启动" "$GREEN"
}

# ==================== 3) 更新二进制 ====================
update_binary_only() {
    select_proxy
    select_repo
    install_libunwind
    download_main_binary || return 1
    print "✅ 二进制更新完毕，如需生效请重启服务 (选项 4)" "$GREEN"
}

# ==================== 4) 重启服务 ====================
restart_service() {
    systemctl restart ppp.service && print "✅ 服务已重启" "$GREEN"
}

# ==================== 5) 停止服务 ====================
stop_service() {
    systemctl stop ppp.service && print "✅ 服务已停止" "$GREEN"
}

# ==================== 6) 查看状态 ====================
show_status() {
    print "=== ppp.log（前 50 行）===" "$BLUE"
    if [ -f "/opt/ppp/ppp.log" ]; then
        watch -n 1 'head -n 50 /opt/ppp/ppp.log'
    else
        print "日志文件不存在" "$YELLOW"
    fi
    echo
    print "=== ppp.service 状态 ===" "$BLUE"
    systemctl status ppp.service --no-pager -l
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
        rm -rf /opt/ppp
        print "✅ 已删除所有文件" "$GREEN"
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
    local update_mode update_url
    print "🌍 更新本脚本 - 请选择方式" "$BLUE"
    echo "1) 使用国内加速"
    echo "2) 直连 GitHub"
    read -p "请输入 [1-2]（默认 2）: " update_mode
    if [ "$update_mode" = "1" ]; then
        update_url="https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    else
        update_url="https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    fi
    print "📥 正在下载最新脚本..." "$BLUE"
    wget -4 -O /root/ppp_install.sh "$update_url" && chmod +x /root/ppp_install.sh
    if [ $? -eq 0 ]; then
        print "✅ 脚本更新成功，重新启动..." "$GREEN"
        exec /root/ppp_install.sh
    else
        print "❌ 更新失败" "$RED"
    fi
}

# ==================== 9) 客户端配置切换 ====================
configure_client_json() {
    print "🔧 客户端模式 - 更换配置文件并自动重启服务" "$BLUE"
    if [ ! -d "/opt/ppp" ]; then mkdir -p /opt/ppp; fi
    if [ ! -f "/opt/ppp/ppp" ]; then
        print "❌ 未找到 /opt/ppp/ppp，请先安装二进制（选项 1 或 3）" "$RED"
        return 1
    fi
    mapfile -t json_files < <(find /opt/ppp -maxdepth 1 -name "*.json" -type f -printf "%f\n" 2>/dev/null)
    if [ ${#json_files[@]} -eq 0 ]; then
        print "❌ 未找到任何 JSON 配置文件" "$RED"
        return 1
    fi
    print "📄 可用的 JSON 配置文件：" "$BLUE"
    for i in "${!json_files[@]}"; do echo "$((i+1))) ${json_files[$i]}"; done
    local choice
    read -p "请选择配置文件 (1-${#json_files[@]}): " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#json_files[@]}" ]; then
        print "❌ 无效选择" "$RED"; return 1
    fi
    local selected="${json_files[$((choice-1))]}"
    print "✅ 已选择: $selected" "$GREEN"
    local ppp_sh="/opt/ppp/ppp.sh"
    if [ ! -f "$ppp_sh" ]; then
        cat > "$ppp_sh" << EOF
#!/bin/bash
cd /opt/ppp
./ppp --mode=client --config=./${selected}
EOF
        chmod +x "$ppp_sh"
        print "✅ 已创建 ppp.sh 并设置配置为 ${selected}" "$GREEN"
    else
        if grep -q -- '--config=' "$ppp_sh"; then
            sed -i "s|--config=[^ ]*|--config=./${selected}|" "$ppp_sh"
        elif grep -q './ppp' "$ppp_sh"; then
            sed -i "s|./ppp |&--config=./${selected} |" "$ppp_sh"
        else
            print "❌ 无法在 ppp.sh 中找到 ./ppp 命令" "$RED"; return 1
        fi
        print "✅ 已更新 ppp.sh 的 --config 参数" "$GREEN"
    fi
    print "🔄 正在重启 ppp 服务..." "$BLUE"
    if systemctl restart ppp.service; then
        print "✅ 配置文件已更换，服务重启成功！" "$GREEN"
    else
        print "⚠️ 服务重启失败，请检查 systemctl 状态" "$YELLOW"
        return 1
    fi
}

# ==================== 主菜单 ====================
create_ppp_shortcut
while true; do
    clear
    print "=============== openppp2 一键脚本（v4.3.1 修复版）===============" "$BLUE"
    echo "1) 服务端 - 完整自动安装（自动选最优版本）"
    echo "2) 服务端 - 配置系统服务（已有配置时使用）"
    echo "3) 通用 - 更新二进制文件（自动适配）"
    echo "4) 通用 - 重启服务"
    echo "5) 通用 - 停止服务"
    echo "6) 通用 - 查看运行状态（日志前50行）"
    echo "7) 通用 - 完全卸载"
    echo "8) 更新本脚本"
    echo "9) 客户端 - 更换配置文件（自动重启）"
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
        10) print "👋 退出脚本" "$GREEN"; exit 0 ;;
        *) print "❌ 无效选项" "$RED" ;;
    esac
    echo; read -p "按 Enter 键返回主菜单..."
done
