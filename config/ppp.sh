#!/bin/bash
# openppp2 客户端启动脚本（tmux 伪终端 + systemd 托管）

cd /opt/ppp

# 结束已有的同名会话
tmux kill-session -t ppp 2>/dev/null

# 创建新的后台 tmux 会话（提供伪终端，ppp 可显示 TUI）
tmux new-session -d -s ppp \
    './ppp ./ppp --mode=server > ./ppp.log'

# 等待 tmux 会话完全创建
sleep 1

# 开启日志管道：将 TUI 输出同时写入 ppp.log
tmux pipe-pane -t ppp 'cat >> ppp.log'

echo "ppp 客户端已在 tmux 会话中启动"

# 关键：保持脚本不退出，直到 tmux 会话结束
# 使用无限循环 + 睡眠检查，降低 CPU 占用
while tmux has-session -t ppp 2>/dev/null; do
    sleep 5
done

echo "ppp 会话已结束，脚本退出"
