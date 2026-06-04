# openppp2 一键安装脚本
> 双仓库智能适配 + tmux 管理 | 支持多架构、低 glibc 兼容
本脚本用于**一键安装、配置、管理** [openppp2](https://github.com/liulilittle/openppp2) 高性能隧道程序。  
支持服务端/客户端模式，自动选择最优二进制版本，并提供 systemd + tmux 进程管理。
## 📦 项目作用
openppp2 是一个**高性能点对点 PPP 隧道实现**，支持 TCP/UDP 多路复用、加密传输、流量整形等特性。  
本脚本封装了完整的部署流程，使普通用户也能轻松搭建：
- **服务端**：监听公网端口，接收客户端连接
- **客户端**：连接服务端，建立安全隧道
典型场景：内网穿透、异地组网、网络加速。
## 🖥️ 适用范围
- **操作系统**：Linux (Debian/Ubuntu/CentOS/RHEL/Fedora 等)
- **CPU 架构**：`x86_64`、`aarch64`、`armv7l`、`mipsel`、`ppc64le`、`riscv64`、`s390x`
- **环境要求**：glibc ≥ 2.17（低版本自动选用 debian10 兼容包）
- **网络**：IPv4 公网/内网均可（建议开放监听端口）
## 📥 安装的软件
通过本脚本会自动安装以下组件：
| 软件 | 用途 |
|------|------|
| openppp2 | 主程序（从 GitHub Release 下载） |
| libunwind8 | 运行时库（必须） |
| tmux | 终端复用器，用于查看运行状态 |
| jq | JSON 配置文件修改 |
| uuid-runtime | 生成 GUID |
| unzip | 解压二进制包 |
| wget | 下载文件 |
同时会创建 systemd 服务 `/etc/systemd/system/ppp.service` 和快捷命令 `/usr/local/bin/ppp`。
## 📚 来源仓库
本脚本支持两个 openppp2 仓库，安装时可手动选择：
- **[liulilittle/openppp2](https://github.com/liulilittle/openppp2)**（原版，全兼容，按特性自动选择最佳二进制）
- **[Miaocchi/openppp2](https://github.com/Miaocchi/openppp2)**（扩展版，低 glibc 系统自动选用 debian10 包）
脚本自身维护仓库：[picetor/openppp2_install](https://github.com/picetor/openppp2_install)
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

## 🧰 脚本功能详解

脚本启动后显示主菜单，支持以下操作：

|选项|功能|
|---|---|
|**1) 服务端 - 完整自动安装**|选择代理/仓库 → 安装依赖 → 下载最优二进制 → 配置 appsettings.json → 创建 systemd 服务并启动|
|**2) 服务端 - 配置系统服务**|仅将现有的 `/opt/ppp` 注册为 systemd 服务（适用于手动配置后补注册）|
|**3) 通用 - 更新二进制文件**|重新下载最新版 openppp2 并替换，保留配置文件|
|**4) 通用 - 重启服务**|重启 systemd 服务|
|**5) 通用 - 停止服务**|停止 systemd 服务|
|**6) 通用 - 查看运行状态**|进入 tmux 会话（`ppp`）实时查看日志输出（`Ctrl+B D` 退出）|
|**7) 通用 - 完全卸载**|停止服务、删除 systemd 单元、可选删除所有配置和数据|
|**8) 更新本脚本**|从 GitHub 拉取最新版 `ppp_install.sh`|
|**9) 客户端 - 更换配置文件**|扫描 `/opt/ppp/*.json`，选择后修改 `ppp.sh` 中的 `--config=` 参数并重启服务|
|**10) 退出**|退出脚本|

### 智能版本选择

脚本会根据 CPU 特性、内核版本、glibc 版本自动选择最合适的二进制文件：

- 检测 `io_uring` 支持（内核 ≥ 5.10）
    
- 检测 AES-NI 指令集
    
- 检测 是否`tc`加成 
    
- 低 glibc 系统自动选用 `debian10` 兼容包（仅 Miaocchi 仓库）
    

### 进程管理方式

- **systemd**：后台守护，开机自启，常用命令 `systemctl {start\|stop\|restart} ppp`
    
- **tmux**：运行时输出绑定到 tmux 会话 `ppp`，通过选项 6 可实时查看彩色日志
    

## ⚙️ 服务端配置示例（自动生成）

自动安装会交互式询问以下参数，并写入 `/opt/ppp/appsettings.json`：

- 监听 IP（默认 `0.0.0.0`）
    
- 监听端口（默认 `20000`）
    
- GUID（随机生成）
    
- protocol-key / transport-key（随机生成 16 位字符串）
    

若需高级配置（如多用户、限速），请手动编辑 `appsettings.json` 后重启服务。

## 🧩 客户端模式使用

1. 在服务端安装完成后，将 `/opt/ppp/ppp` 二进制和对应 `client.json` 拷贝到客户端机器。
    
2. 在客户端运行本脚本，选择 `9) 客户端 - 更换配置文件`，选择你的 `client.json`。
    
3. 脚本会自动生成 `/opt/ppp/ppp.sh` 并启动服务。
    

> 客户端需自行准备 JSON 配置文件，格式参考 [openppp2 文档](https://github.com/liulilittle/openppp2#client)。

## ❓ 常见问题

### Q: 如何查看详细日志？

A: 主菜单选 `6)` 进入 tmux 界面，或执行 `journalctl -u ppp -f`。

### Q: 安装后无法启动？

A: 执行 `systemctl status ppp` 查看错误，常见原因：端口被占用、libunwind 缺失、配置文件 JSON 语法错误。

### Q: 如何更换仓库？

A: 重新运行脚本，选 `3) 更新二进制`，在提示时选择另一个仓库即可。

### Q: armv7 设备是否支持？

A: 支持，脚本会自动下载对应架构的二进制（Miaocchi 仓库提供 cross 版本）。

## 📄 许可证

本脚本采用 MIT 协议，openppp2 项目请参考各自仓库的许可证。

## 🙏 致谢

- [liulilittle](https://github.com/liulilittle) 开源的高性能隧道实现
    
- [Miaocchi](https://github.com/Miaocchi) 提供的兼容性增强版本
    
- 国内加速服务由 [git.apad.pro](https://git.apad.pro/) 提供
