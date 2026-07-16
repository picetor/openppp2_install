@echo off
fltmc >nul 2>&1
if errorlevel 1 (
	powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
	exit /b
)

cd /d "%~dp0"
start "openppp2" ppp.exe --mode=client --config=./config/zgo.json --tun-mux=0 --tun-host=yes --tun-vnet=yes --tun-gw=192.168.12.0 --tun-ip=192.168.12.68 --tun-flash=yes --tun-mask=24 --link-restart=3 --tun-static=no --tun-mux-acceleration=3 --bypass-mode=geo --block-quic=yes --log-file ./ppp1.log --lwip=yes 