# openppp2 一键安装脚本（v4.4）

## 项目介绍

**openppp2** 是一款高性能、轻量级的虚拟以太网隧道工具（Virtual Ethernet Tunnel），类似于 WireGuard + TUN/TAP 的增强版实现。

### 项目作用

- 实现点对点或多点安全虚拟网络隧道
- 支持 TCP + UDP 双协议传输
- 提供高性能数据转发（支持 io_uring、SIMD 加速）
- 适用于内网穿透、远程办公、服务器组网、游戏加速等场景
- 具备较强的抗干扰能力和传输效率，适合弱网环境
- 支持客户端/服务端模式，可实现多设备组网

---

## 适用范围

### 支持系统
- Debian 10 / 11 / 12（重点优化）
- Ubuntu 20.04 及以上
- 其他 glibc ≥ 2.28 的 Linux 发行版（低版本 glibc 可自动切换兼容包）

### 支持架构
- **x86_64 / amd64**（功能最完整，推荐）
- **aarch64 / arm64**（树莓派、ARM 服务器等）
- **armv7l**
- **mips / mipsel**
- **ppc64le**
- **riscv64**
- **s390x**

### 适用场景
- 个人/企业内网穿透
- 远程安全访问
- 多地区服务器组网
- 需要低延迟、高吞吐的隧道需求
- VPS / 云服务器组网

---

## 安装的软件

### 1. 核心程序
- **openppp2**（主二进制文件 `ppp`）
- 智能选择最优特性版本（含 io_uring、SIMD、TC 加速等）

### 2. 系统依赖（自动安装）
| 软件包              | 作用                          | 是否必须 |
|---------------------|-------------------------------|----------|
| `tmux`              | 管理 TUI 状态界面             | 是      |
| `jq`                | 配置 JSON 文件修改            | 是      |
| `unzip`             | 解压下载的程序包              | 是      |
| `uuid-runtime`      | 生成随机 GUID                 | 是      |
| `libunwind8`        | 程序运行时栈展开支持          | 是      |
| `systemd`           | 服务管理（开机自启）          | 是      |

### 3. 安装路径
- 主程序目录：`/opt/ppp/`
- 二进制文件：`/opt/ppp/ppp`
- 配置文件：`/opt/ppp/appsettings.json`
- systemd 服务：`/etc/systemd/system/ppp.service`
- 快捷命令：`/usr/local/bin/ppp`

---

## 默认配置

- **监听端口**：`20000`（TCP + UDP）
- **监听地址**：`0.0.0.0`
- **工作模式**：服务端（可切换客户端）

---

## 快速安装

```bash
# 国内加速（推荐）
wget -4 -O ppp_install.sh https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh

# 直连 GitHub
wget -4 -O ppp_install.sh https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh
