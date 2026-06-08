#!/bin/bash
# openppp2 启动脚本（tmux 伪终端 + systemd 托管，不写日志）

cd /opt/ppp

# 结束已有的同名会话
tmux kill-session -t ppp 2>/dev/null

# 创建新的后台 tmux 会话（提供伪终端，ppp 可显示 TUI）
tmux new-session -d -s ppp './ppp --mode=server'

# 等待 tmux 会话完全创建
sleep 1

echo "ppp 已在 tmux 会话中启动"
echo "查看界面: tmux attach -t ppp"
echo "退出界面: Ctrl+B 然后按 D"

# 保持脚本不退出，直到 tmux 会话结束
while tmux has-session -t ppp 2>/dev/null; do
    sleep 5
done

echo "ppp 会话已结束，脚本退出"
