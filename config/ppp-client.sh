#!/bin/bash
# openppp2 客户端启动脚本 - 双模式版（tmux 会话: ppp-client）
# 配合 ppp-server.sh 在同一机器同时运行服务端和客户端

cd /opt/ppp/client
chmod +x ../ppp ppp-client.sh
# 结束已有的同名会话
tmux kill-session -t ppp-client 2>/dev/null

# 创建新的后台 tmux 会话（提供伪终端，ppp 可显示 TUI）
tmux new-session -d -s ppp-client '
ulimit -SHn 1000000
ulimit -c unlimited

iptables -t nat -F
iptables -t nat -A POSTROUTING -j MASQUERADE
../ppp --mode=client --config=./client.json --tun-mux=0 --tun-host=yes --tun-vnet=yes --tun-gw=192.168.12.0 --tun-ip=192.168.12.10 --tun-flash=yes --tun-mask=24 --link-restart=3 --tun-static=no --block-quic=yes --tun-mux-acceleration=3 --tun-ssmt=4/mq'

# 等待 tmux 会话完全创建
sleep 1

echo "ppp-client 已在 tmux 会话中启动"
echo "查看界面: tmux attach -t ppp-client"
echo "退出界面: Ctrl+B 然后按 D"

# 保持脚本不退出，直到 tmux 会话结束
while tmux has-session -t ppp-client 2>/dev/null; do
    sleep 5
done

echo "ppp-client 会话已结束，脚本退出"
