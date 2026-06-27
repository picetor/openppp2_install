# openppp2 一键安装与管理脚本

**版本 v4.7** — 提供两套脚本，覆盖单机和同机双模式部署场景，内置智能版本选择、systemd 服务管理、tmux TUI 状态查看。

---

## 🚀 一键安装命令

### ppp_install.sh (单模式 -- 一台机器只装服务端或只装客户端)
#### 直连 GitHub (海外服务器或网络良好)
```bash
wget -4 -O ppp_install.sh https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh
```
#### 使用国内加速 (大陆服务器)
```bash
wget -4 -O ppp_install.sh https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh
```

### ppp_dual.sh (双模式 -- 同机同时运行服务端+客户端)
#### 直连 GitHub
```bash
wget -4 -O ppp_dual.sh https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_dual.sh && chmod +x ppp_dual.sh && ./ppp_dual.sh
```
#### 使用国内加速
```bash
wget -4 -O ppp_dual.sh https://git.apad.pro/https://raw.githubusercontent.com/picetor/openppp2_install/main/ppp_dual.sh && chmod +x ppp_dual.sh && ./ppp_dual.sh
```

---

## 一、脚本选择指南

| 场景 | 推荐脚本 |
|------|----------|
| 只运行服务端 (VPS 提供 VPN 接入) | ppp_install.sh |
| 只运行客户端 (连接远程服务端) | ppp_install.sh |
| 同机同时运行服务端+客户端 | ppp_dual.sh |

---

## 二、脚本对比

| 特性 | ppp_install.sh (单模式) | ppp_dual.sh (双模式) |
|------|:---:|:---:|
| 安装目录 | /opt/ppp/ | /opt/ppp/server/ + /opt/ppp/client/ |
| systemd 服务 | ppp.service | ppp-server.service + ppp-client.service |
| tmux 会话 | ppp | ppp-server / ppp-client |
| 快捷命令 | ppp | ppp 或 ppp-dual |
| 二进制位置 | /opt/ppp/ppp | /opt/ppp/ppp (共享) |
| 服务端安装 | 1.1/1.2 | 1.1/1.2 |
| 客户端安装 | 2.1/2.2 | 2.1/2.2 |
| 同机双装 | 不支持 | 1.3 服务端+客户端同时安装 |
| 重启/停止 | 直接操作 ppp.service | 自动检测, 菜单选择 |

---

## 三、脚本概述

- 用途: 自动化部署、配置、管理 openppp2 (隧道 VPN 工具)
- 运行环境: Linux (支持多种架构)
- 管理方式: systemd 系统服务 + tmux 会话管理
- 多仓库支持: liulilittle/openppp2 (原版), Miaocchi/openppp2 (扩展版), picetor/openppp2 (WSS 修改版)

---

## 四、核心功能模块

### 1. 快捷命令创建
- ppp_install.sh: 创建 /usr/local/bin/ppp
- ppp_dual.sh: 额外创建 /usr/local/bin/ppp-dual

### 2. 系统检测
- has_aesni(): CPU 是否支持 AES-NI
- kernel_supports_io_uring(): 内核是否 >= 5.10
- has_tc(): 是否安装 tc
- glibc_lt_238(): glibc 是否低于 2.38 (纯 bash, 无 bc 依赖)

### 3. 智能版本选择 (choose_best_zip)
根据 CPU 架构和系统特性, 从 GitHub Releases 下载最优版本。

### 4. 依赖安装 (install_deps)
自动安装: jq, uuid-runtime, unzip, tmux

### 5. 代理选择 (select_proxy)
国内用户可选 https://git.apad.pro/ 代理加速。

---

## 五、主菜单选项详解

### 服务端功能
| 选项 | 功能 | 单脚本 | 双脚本 |
|------|------|:---:|:---:|
| 1.1 完整自动安装 | 选代理->选仓库->装依赖->下载二进制->启动脚本->配置 appsettings.json->BDP 优化->创建 systemd 服务 | 支持 | 支持 |
| 1.2 仅配置系统服务 | 已有配置文件时只配置服务和启动脚本 | 支持 | 支持 |
| 1.3 服务端+客户端同时安装双模式 | 同机部署, 双目录+双服务+双 tmux | 不支持 | 支持 |

### 客户端功能
| 选项 | 功能 | 单脚本 | 双脚本 |
|------|------|:---:|:---:|
| 2.1 完整自动安装 | 安装二进制+客户端启动脚本, 配置服务 | 支持 | 支持 |
| 2.2 仅配置系统服务 | 已有二进制时只配置服务 | 支持 | 支持 |
| 2.3 切换配置文件 | 扫描 JSON, sed 修改 --config | 支持 | 支持 |
| 2.4 BDP 窗口计算器 | 带宽x延迟计算 CWND/RWND, 三档可选 | 支持 | 支持 |
| 2.5 修改 GUID | 修改 client.guid | 支持 | 支持 |

### 通用功能
| 选项 | 功能 | 单脚本 | 双脚本 |
|------|------|:---:|:---:|
| 3 更新二进制 | 重新下载 ppp 二进制 | 支持 | 支持 |
| 4 重启服务 | 单: 重启 ppp.service; 双: 菜单选 1服务/2客户/3全部 | 支持 | 支持 |
| 5 停止服务 | 自动检测运行中的服务 | 支持 | 支持 |
| 6 查看运行状态 | tmux attach (Ctrl+B D 退出); 双脚本菜单选择 | 支持 | 支持 |
| 7 完全卸载 | 停止服务, 删除单元, 可选保留配置 | 支持 | 支持 (清理全部3个服务) |
| 8 更新本脚本 | 从 GitHub 拉取最新版 | 支持 | 支持 (各自拉取自身) |
| 9 退出 | 退出脚本 | 支持 | 支持 |

---

## 六、双模式架构详解 (ppp_dual.sh)

### 目录结构
```
/opt/ppp/
  ppp                     # 共享二进制
  server/
    ppp-server.sh         # 服务端启动脚本 (tmux: ppp-server)
    appsettings.json      # 服务端配置
  client/
    ppp-client.sh         # 客户端启动脚本 (tmux: ppp-client)
    *.json                # 客户端配置文件
```

### systemd 服务
- ppp-server.service -> ExecStart: /bin/bash /opt/ppp/server/ppp-server.sh
- ppp-client.service -> ExecStart: /bin/bash /opt/ppp/client/ppp-client.sh

### tmux 会话
- ppp-server: 显示服务端 TUI
- ppp-client: 显示客户端 TUI

---

## 七、配置文件处理逻辑

脚本使用 jq 操作 JSON:
- 服务端: 自动生成 appsettings.json, 配置 IP/端口/GUID/密钥
- 客户端: 多配置文件, 通过 --config=./xxx.json 指定
- 智能回退 get_current_config():
  1. 从启动脚本提取 --config 参数
  2. 回退到 appsettings.json
  3. 回退到目录下任意 .json

---

## 八、BDP (带宽延迟积) 计算器

- 公式: 窗口 = 带宽(bps) / 8 x RTT(ms) / 1000, 向上取 2 的幂次
- 自动测延迟: Ping 1.1.1.1, 失败则手动输入
- 三档策略: 保守 / 均衡(默认) / 激进

---

## 九、config 目录结构 (模板文件)

```
config/
  appsettings.json        # 服务端配置模板 (通用)
  ppp.service             # systemd 单元 (单模式)
  ppp.sh                  # 服务端启动脚本 (单模式)
  client.sh               # 客户端启动脚本 (单模式)
  ppp-server.service      # systemd 单元 - 服务端 (双模式)
  ppp-client.service      # systemd 单元 - 客户端 (双模式)
  ppp-server.sh           # 服务端启动脚本 (双模式)
  ppp-client.sh           # 客户端启动脚本 (双模式)
```

---

## 十、设计亮点

1. 零依赖检测: glibc_lt_238() 纯 bash, 无 bc 依赖
2. 低版本兼容: Miaocchi 版低 glibc 自动选 debian10 包
3. IPv4/IPv6 双栈: wget 自动回退
4. 非侵入式更新: 更新二进制时自动重启运行中的服务
5. 配置保护: 卸载时可选保留配置文件
6. 状态可视化: tmux attach 完美显示 TUI
7. 一单一双双脚本: 单模式简洁, 双模式灵活, 互不干扰

---

总结: 覆盖 openppp2 全生命周期管理的自动化工具集, 单机单用选 ppp_install.sh, 同机双开选 ppp_dual.sh.
