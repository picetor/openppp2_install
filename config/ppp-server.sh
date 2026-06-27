#!/bin/bash
# openppp2 服务端启动脚本 - 双模式版（tmux 会话: ppp-server）
# 配合 ppp-client.sh 在同一机器同时运行服务端和客户端

cd /opt/ppp/server
chmod +x ../ppp ppp-server.sh
# 结束已有的同名会话
tmux kill-session -t ppp-server 2>/dev/null

# 创建新的后台 tmux 会话（提供伪终端，ppp 可显示 TUI）
tmux new-session -d -s ppp-server '../ppp --mode=server'

# 等待 tmux 会话完全创建
sleep 1

echo "ppp-server 已在 tmux 会话中启动"
echo "查看界面: tmux attach -t ppp-server"
echo "退出界面: Ctrl+B 然后按 D"

# 保持脚本不退出，直到 tmux 会话结束
while tmux has-session -t ppp-server 2>/dev/null; do
    sleep 5
done

echo "ppp-server 会话已结束，脚本退出"
