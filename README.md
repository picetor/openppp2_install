Optimized tool selection这是一个 **`openppp2` 的一键安装与管理脚本**（版本 v4.7），支持**服务端**和**客户端**两种模式，内置智能版本选择、系统服务管理和 TUI 状态查看。以下是详细的功能分析：

---
## 🚀 一键安装命令
### 直连 GitHub（海外服务器或网络良好）
```bash
wget -4 -O ppp_install.sh https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh
```
### 使用国内加速（大陆服务器）

```bash
wget -4 -O ppp_install.sh https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh
```

运行后进入图形菜单，选择 `1) 服务端 - 完整自动安装` 即可完成服务端部署。

## 一、脚本概述

- **用途**：自动化部署、配置、管理 `openppp2`（一个隧道VPN工具）
- **运行环境**：Linux（支持多种架构）
- **管理方式**：`systemd` 系统服务 + `tmux` 会话管理
- **双仓库支持**：可在 `liulilittle/openppp2`（原版，静态编译）和 `Miaocchi/openppp2`（扩展版）之间选择

---

## 二、核心功能模块

### 1. 快捷命令创建 (`create_ppp_shortcut`)
在 `/usr/local/bin/ppp` 创建一个快捷命令，以后只需输入 `ppp` 即可重新运行此安装脚本。

### 2. 系统检测
脚本会自动检测系统硬件/软件特性，以选择最佳的二进制版本：
- **`has_aesni()`**：CPU 是否支持 AES-NI 指令集
- **`kernel_supports_io_uring()`**：内核是否 ≥ 5.10（支持 io_uring 异步 I/O）
- **`has_tc()`**：系统是否安装了 `tc`（Traffic Control，流量控制工具）
- **`glibc_lt_238()`**：检测 glibc 版本是否低于 2.38（用于 Miaocchi 版选择兼容包）

### 3. 智能版本选择 (`choose_best_zip`)
根据 CPU 架构和系统特性，从 GitHub Releases 下载最优版本：
- **x86_64**：按特性组合选择（`tc`、`io-uring`、`simd` 等后缀）
- **aarch64 / armv7l / mips / ppc64le / riscv64 / s390x**：均有对应架构包
- **Miaocchi 仓库**：在低 glibc 系统上自动选择 `debian10` 兼容包

### 4. 依赖安装 (`install_deps`)
自动安装：
- `jq`（JSON 处理）
- `uuid-runtime` 或 `util-linux`（UUID 生成）
- `unzip`（解压）
- `tmux`（终端复用，用于状态查看）

### 5. 代理选择 (`select_proxy`)
支持国内用户通过 `https://git.apad.pro/` 代理加速下载 GitHub 资源。

---

## 三、主菜单选项详解

### 服务端功能
| 选项 | 功能 |
|------|------|
| **1.1 完整自动安装** | 从 0 开始：选代理 → 选仓库 → 装依赖 → 下载二进制 → 下载启动脚本 → 配置 `appsettings.json`（IP/端口/GUID/密钥）→ 可选 BDP 优化 → 创建 systemd 服务并启动 |
| **1.2 仅配置系统服务** | 在已有 `appsettings.json` 和 `ppp` 二进制的情况下，只下载启动脚本并配置 systemd 服务 |

### 客户端功能
| 选项 | 功能 |
|------|------|
| **2.1 完整自动安装** | 安装二进制和客户端启动脚本 (`client.sh`)，提示用户放入 JSON 配置文件后配置服务 |
| **2.2 仅配置系统服务** | 在已有二进制的情况下，只配置客户端服务和启动脚本 |
| **2.3 切换配置文件** | 在 `/opt/ppp/` 目录下扫描所有 `.json` 文件，通过 `sed` 修改 `ppp.sh` 中的 `--config=./xxx.json` 参数，实现配置文件切换 |
| **2.4 BDP 窗口计算器** | 根据带宽和延迟计算最优 TCP/UDP 窗口大小（CWND/RWND），支持保守/均衡/激进三档，并自动写入当前配置文件 |
| **2.5 修改 GUID** | 读取当前配置文件，修改 `.client.guid` 字段，支持手动输入或自动生成 UUID |

### 通用功能
| 选项 | 功能 |
|------|------|
| **3 更新二进制文件** | 重新下载并替换 `ppp` 二进制（会检测是否需要 `libunwind`） |
| **4 重启服务** | `systemctl restart ppp.service` |
| **5 停止服务** | `systemctl stop ppp.service` |
| **6 查看运行状态** | `tmux attach -t ppp` 连接到 ppp 的 tmux 会话查看 TUI 界面（按 `Ctrl+B` 再按 `D` 退出） |
| **7 完全卸载** | 停止并禁用服务，删除 systemd 单元，可选保留/删除配置文件，删除快捷命令 |
| **8 更新本脚本** | 从 GitHub 拉取最新版 ppp_install.sh 并自动重新执行 |
| **9 退出** | 退出脚本 |

---

## 四、配置文件处理逻辑

脚本使用 `jq` 操作 JSON 配置：
- **服务端**：自动生成/修改 `appsettings.json`，配置监听 IP、端口、GUID、协议密钥 (`protocol-key`)、传输密钥 (`transport-key`)
- **客户端**：支持多配置文件，通过 `ppp.sh` 中的 `--config=./xxx.json` 指定当前使用的配置
- **智能回退**：`get_current_config()` 会按以下顺序查找当前配置：
  1. `ppp.sh` 中的 `--config` 参数
  2. `/opt/ppp/appsettings.json`
  3. `/opt/ppp/` 下任意 `.json` 文件

---

## 五、BDP（带宽延迟积）计算器 (`bdp_calculator`)

用于优化网络传输窗口大小：
- **公式**：窗口 = 带宽(bps) / 8 × RTT(ms) / 1000
- **自动测延迟**：Ping `1.1.1.1` 获取 RTT，失败则手动输入
- **2 的幂次对齐**：计算结果向上取到最接近的 2 的幂次，以享受缓存行优化
- **三档策略**：
  - 保守：CWND = 计算值/2, RWND = 计算值
  - 均衡：CWND = 计算值, RWND = 计算值×2（默认）
  - 激进：CWND = 计算值×2, RWND = 计算值×4

---

## 六、启动脚本处理

脚本会根据模式下载不同的启动脚本模板：
- **服务端模式**：下载 ppp.sh
- **客户端模式**：下载 client.sh

两者都会被保存为 `/opt/ppp/ppp.sh`，并被 systemd 服务调用。

---

## 七、systemd 服务 (`setup_systemd_service`)

从仓库下载 `ppp.service` 文件到 `/etc/systemd/system/`，然后：
- `daemon-reload`
- `enable --now`（立即启用并启动）

---

## 八、设计亮点

1. **零依赖检测**：`glibc_lt_238()` 使用纯 bash 字符串分割，不依赖 `bc`
2. **低版本兼容**：Miaocchi 版在低 glibc 系统自动选择 `debian10` 兼容包
3. **IPv4/IPv6 双栈下载**：`wget` 失败时自动回退 `-4`/`-6`
4. **非侵入式更新**：更新二进制时如果服务正在运行，会自动重启
5. **配置保护**：卸载时可选保留配置文件
6. **状态可视化**：用 `tmux attach` 替代 `systemctl status`，完美显示 TUI 界面

---

总结来说，这是一个**功能非常完善的自动化运维脚本**，涵盖了 openppp2 从安装、配置、优化到卸载的全生命周期管理，特别适合在 VPS 上快速部署和后续维护。
