#!/bin/bash
# =============================================================================
# openppp2 一键安装脚本（v4.0 仓库迁移至 picetor/openppp2_install）
# 自动检测架构 + tc + io-uring + simd，选择最佳版本
# 修复：
# 1. io_uring 内核版本判断错误（应为 5.10+）
# 2. amd64 分支错误返回带 tc 的压缩包
# 3. 补全部分架构/能力组合判断
# 新增：客户端模式 - 扫描 /opt/ppp 下 JSON 并写入 ppp.sh，自动重启服务
# 变更：默认下载源改为直连 GitHub（国际），可选用国内加速
# 变更：仓库由 zouazhi/zouazhi 迁移至 picetor/openppp2_install，去除 ppp 子目录
# =============================================================================

set -o pipefail

# ==================== 颜色定义 ====================
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

print() { echo -e "${2:-$GREEN}$1${RESET}"; }

# ==================== 基础工具函数 ====================
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ==================== 创建 ppp 快捷命令 ====================
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
        print "✅ 已创建 ppp 快捷命令！以后直接输入 ppp 即可运行" "$GREEN"
    else
        print "✅ ppp 快捷命令已存在" "$GREEN"
    fi
}

# ==================== 系统能力检测 ====================
has_aesni() {
    grep -qi 'aes' /proc/cpuinfo 2>/dev/null
}

kernel_supports_io_uring() {
    local major minor
    major=$(uname -r | cut -d. -f1)
    minor=$(uname -r | cut -d. -f2)

    # openppp2 提示要求 5.10.0 或更高
    [ "$major" -gt 5 ] || { [ "$major" -eq 5 ] && [ "$minor" -ge 10 ]; }
}

has_tc() {
    command_exists tc
}

# ==================== 代理选择（默认直连） ====================
select_proxy() {
    print "🌍 是否使用国内加速代理 (git.apad.pro)？" "$BLUE"
    read -p "输入 y 使用加速，直接回车或 n 直连国际源 (默认直连): " USE_PROXY
    if [[ "$USE_PROXY" =~ ^[Yy]$ ]]; then
        GITHUB_PROXY="https://git.apad.pro/"
        print "✅ 已启用国内加速代理" "$GREEN"
    else
        GITHUB_PROXY=""
        print "✅ 使用直连 GitHub (国际)" "$YELLOW"
    fi
}

# ==================== 自动选择最优版本 ====================
choose_best_zip() {
    local arch
    arch=$(uname -m)

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
            if kernel_supports_io_uring && has_tc; then
                echo "openppp2-linux-aarch64-tc-io-uring.zip"
            elif kernel_supports_io_uring; then
                echo "openppp2-linux-aarch64-io-uring.zip"
            elif has_tc; then
                echo "openppp2-linux-aarch64-tc.zip"
            else
                echo "openppp2-linux-aarch64.zip"
            fi
            ;;
        armv7l|armv7)
            if kernel_supports_io_uring; then
                echo "openppp2-linux-armv7l-io-uring.zip"
            else
                echo "openppp2-linux-armv7l.zip"
            fi
            ;;
        mips|mipsel)
            echo "openppp2-linux-mipsel.zip"
            ;;
        ppc64le|ppc64el)
            echo "openppp2-linux-ppc64el.zip"
            ;;
        riscv64)
            echo "openppp2-linux-riscv64.zip"
            ;;
        s390x)
            echo "openppp2-linux-s390x.zip"
            ;;
        *)
            print "❌ 不支持的架构: $arch" "$RED"
            exit 1
            ;;
    esac
}

# ==================== 下载函数 ====================
prompt_replace_file() {
    local target_path="$1"
    local url="$2"
    local desc="$3"

    mkdir -p "$(dirname "$target_path")"

    if [ -f "$target_path" ]; then
        print "⚠️  $desc 已存在" "$YELLOW"
        read -p "是否替换？(y/n，默认 n): " REPLACE
        if [[ ! "$REPLACE" =~ ^[Yy]$ ]]; then
            return 0
        fi
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
    print "🔧 正在安装依赖..." "$BLUE"

    if command_exists apt-get; then
        apt-get update && apt-get install -y jq uuid-runtime unzip
    elif command_exists dnf; then
        dnf install -y jq util-linux unzip
    elif command_exists yum; then
        yum install -y jq util-linux unzip
    else
        print "❌ 无法识别包管理器，请手动安装 jq uuid-runtime unzip" "$RED"
        return 1
    fi

    if ! command_exists jq || ! command_exists unzip; then
        print "❌ 依赖安装失败，请手动检查 jq / unzip" "$RED"
        return 1
    fi

    print "✅ 依赖安装完成" "$GREEN"
    return 0
}

# ==================== 下载并解压主程序 ====================
download_main_binary() {
    local zip_name url

    zip_name=$(choose_best_zip)
    print "🔍 自动选择最优版本：$zip_name" "$BLUE"

    mkdir -p /opt/ppp || return 1
    cd /opt/ppp || return 1

    url="${GITHUB_PROXY}https://github.com/liulilittle/openppp2/releases/latest/download/${zip_name}"
    prompt_replace_file "/opt/ppp/${zip_name}" "$url" "$zip_name" || return 1

    if ! command_exists unzip; then
        print "❌ 未安装 unzip，请先安装后重试" "$RED"
        return 1
    fi

    if unzip -o "$zip_name" ppp -d . && chmod +x ppp; then
        rm -f "$zip_name"
        print "✅ openppp2 最优版本处理完成" "$GREEN"
        return 0
    else
        print "❌ 解压或设置权限失败，请检查压缩包是否正确" "$RED"
        return 1
    fi
}

# ==================== 配置 systemd 服务 ====================
setup_systemd_service() {
    local service_url

    service_url="${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/ppp.service"

    prompt_replace_file "/etc/systemd/system/ppp.service" "$service_url" "ppp.service" || return 1

    chmod 644 /etc/systemd/system/ppp.service
    systemctl daemon-reload
    systemctl enable --now ppp.service
}

# ==================== 自动安装 ====================
auto_install() {
    select_proxy

    install_deps || return 1
    download_main_binary || return 1

    prompt_replace_file "/opt/ppp/ppp.sh" \
        "${GITHUB_PROXY}https://raw.githubusercontent.com/picetor/openppp2_install/main/config/ppp.sh" \
        "ppp.sh" || return 1
    chmod +x /opt/ppp/ppp.sh

    read -p "是否自行修改 appsettings.json？(y/n，默认 n): " SELF
    if [[ "$SELF" =~ ^[Yy]$ ]]; then
        print "请手动修改 /opt/ppp/appsettings.json 后，运行选项 2" "$YELLOW"
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

    if ! jq --indent 4 \
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
    ' appsettings.json > temp.json; then
        print "❌ appsettings.json 修改失败，请检查原始配置格式" "$RED"
        rm -f temp.json
        return 1
    fi

    mv temp.json appsettings.json

    setup_systemd_service || return 1

    if systemctl is-active --quiet ppp.service; then
        print "🎉 安装成功！服务已启动" "$GREEN"
        create_ppp_shortcut
    else
        print "⚠️ 服务启动失败，请检查日志" "$YELLOW"
    fi
}

# ==================== 仅更新二进制 ====================
update_binary_only() {
    select_proxy
    download_main_binary || return 1
}

# ==================== 手动配置系统服务 ====================
configure_service_only() {
    if [ ! -f "/opt/ppp/appsettings.json" ]; then
        print "❌ 未找到 appsettings.json，请先运行选项 1" "$RED"
        return 1
    fi

    cd /opt/ppp || {
        print "❌ /opt/ppp 目录不存在" "$RED"
        return 1
    }

    select_proxy
    setup_systemd_service || return 1
    print "✅ 系统服务配置完成并启动" "$GREEN"
}

# ==================== 卸载 ====================
uninstall_ppp() {
    print "🗑️ 开始卸载..." "$YELLOW"
    systemctl stop ppp.service 2>/dev/null
    systemctl disable ppp.service 2>/dev/null
    rm -f /etc/systemd/system/ppp.service
    systemctl daemon-reload

    print "是否保留配置文件？（默认保留）" "$BLUE"
    read -p "输入 y 保留（默认），n 删除: " KEEP_CONFIG

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

# ==================== 查看状态 ====================
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

# ==================== 更新脚本 ====================
update_script() {
    local update_mode update_url

    print "🌍 更新本脚本 - 请选择方式" "$BLUE"
    echo "1) 使用国内加速 (推荐)"
    echo "2) 直连 GitHub (国际)"
    read -p "请输入 [1-2]（默认 2 直连）: " update_mode

    if [ "$update_mode" = "1" ]; then
        update_url="https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    else
        update_url="https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh"
    fi

    print "📥 正在下载最新脚本..." "$BLUE"
    wget -4 -O /root/ppp_install.sh "$update_url" && chmod +x /root/ppp_install.sh

    if [ $? -eq 0 ]; then
        print "✅ 脚本更新成功！正在重新启动..." "$GREEN"
        exec /root/ppp_install.sh
    else
        print "❌ 更新失败" "$RED"
    fi
}

# ==================== 客户端配置：选择 JSON 写入 ppp.sh 并自动重启 ====================
configure_client_json() {
    print "🔧 客户端模式 - 更换配置文件并自动重启服务" "$BLUE"

    if [ ! -d "/opt/ppp" ]; then
        mkdir -p /opt/ppp
    fi

    # 检查 ppp 二进制
    if [ ! -f "/opt/ppp/ppp" ]; then
        print "❌ 未找到 /opt/ppp/ppp，请先安装二进制（选项 1 或 3）" "$RED"
        return 1
    fi

    # 扫描 /opt/ppp 下的 json 文件（客户端不需要排除 appsettings.json）
    mapfile -t json_files < <(find /opt/ppp -maxdepth 1 -name "*.json" -type f -printf "%f\n" 2>/dev/null)
    if [ ${#json_files[@]} -eq 0 ]; then
        print "❌ 在 /opt/ppp/ 下未找到任何 JSON 文件。请先将客户端配置文件(.json)放入该目录。" "$RED"
        return 1
    fi

    print "📄 可用的 JSON 配置文件：" "$BLUE"
    for i in "${!json_files[@]}"; do
        echo "$((i+1))) ${json_files[$i]}"
    done

    local choice
    read -p "请选择配置文件 (1-${#json_files[@]}): " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#json_files[@]}" ]; then
        print "❌ 无效选择" "$RED"
        return 1
    fi

    local selected="${json_files[$((choice-1))]}"
    print "✅ 已选择配置文件: $selected" "$GREEN"

    local ppp_sh="/opt/ppp/ppp.sh"

    # 如果 ppp.sh 不存在则创建默认客户端启动脚本
    if [ ! -f "$ppp_sh" ]; then
        print "⚠️  ppp.sh 不存在，正在创建客户端启动脚本..." "$YELLOW"
        cat > "$ppp_sh" << EOF
#!/bin/bash
cd /opt/ppp
./ppp --mode=client --config=./${selected}
EOF
        chmod +x "$ppp_sh"
        print "✅ 已创建 ppp.sh 并设置配置文件为 ${selected}" "$GREEN"
    else
        # 修改现有脚本中的 --config= 参数
        if grep -q -- '--config=' "$ppp_sh"; then
            sed -i "s|--config=[^ ]*|--config=./${selected}|" "$ppp_sh"
            print "✅ 已更新 ppp.sh 中的 --config 参数为 ./${selected}" "$GREEN"
        elif grep -q './ppp' "$ppp_sh"; then
            # 如果没有 --config=，则插入到 ./ppp 命令后
            sed -i "s|./ppp |&--config=./${selected} |" "$ppp_sh"
            print "✅ 已在 ppp.sh 的 ./ppp 命令后添加 --config=./${selected}" "$GREEN"
        else
            print "❌ 无法在 ppp.sh 中找到 ./ppp 命令，未做修改。请手动编辑。" "$RED"
            return 1
        fi
    fi

    # 自动重启服务
    print "🔄 正在重启 ppp 服务..." "$BLUE"
    if systemctl restart ppp.service; then
        print "✅ 配置文件已更换，服务重启成功！" "$GREEN"
    else
        print "⚠️ 配置文件已更新，但服务重启失败，请检查 systemctl 状态。" "$YELLOW"
        return 1
    fi
}

# ==================== 主菜单 ====================
# 脚本启动时自动注册 ppp 快捷命令
create_ppp_shortcut

while true; do
    clear
    print "=============== openppp2 一键脚本（v3.9.2 picetor 仓库）===============" "$BLUE"
    echo "1) 服务端 - 完整自动安装（推荐，自动最优版本）"
    echo "2) 服务端 - 配置系统服务（自行修改配置后使用）"
    echo "3) 通用 - 更新二进制文件（自动最优版本）"
    echo "4) 通用 - 重启服务"
    echo "5) 通用 - 停止服务"
    echo "6) 通用 - 查看运行状态（日志前50行）"
    echo "7) 通用 - 完全卸载"
    echo "8) 更新本脚本"
    echo "9) 客户端 - 更换配置文件（自动重启）"
    echo "10) 退出"
    read -p "请输入选项 [1-10]: " OPERATION

    case "$OPERATION" in
        1)
            auto_install
            ;;
        2)
            configure_service_only
            ;;
        3)
            update_binary_only
            ;;
        4)
            systemctl restart ppp.service && print "✅ 服务已重启" "$GREEN"
            ;;
        5)
            systemctl stop ppp.service && print "✅ 服务已停止" "$GREEN"
            ;;
        6)
            show_status
            ;;
        7)
            uninstall_ppp
            ;;
        8)
            update_script
            ;;
        9)
            configure_client_json
            ;;
        10)
            print "👋 退出脚本" "$GREEN"
            exit 0
            ;;
        *)
            print "❌ 无效选项" "$RED"
            ;;
    esac

    echo
    read -p "按 Enter 键返回主菜单..."
done
