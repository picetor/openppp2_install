# 服务端自动(半自动)安装:一键脚本，仅支持 x86
<pre class="language-markup">wget -4 -O ppp_install.sh https://raw.githubusercontent.com/zouazhi/zouazhi/main/ppp/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh <code></code></pre>

https://git.apad.pro/ 加速
<pre class="language-markup">wget -4 -O ppp_install.sh https://git.apad.pro/https://raw.githubusercontent.com/zouazhi/zouazhi/main/ppp/ppp_install.sh && chmod +x ppp_install.sh && ./ppp_install.sh <code></code></pre>


# 手动
拉取二进制文件
<pre class="language-markup">mkdir /opt/ppp && cd /opt/ppp && wget https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-amd64.zip && unzip -o $(ls | grep -m1 'openppp2.*\.zip') ppp -d . && chmod +x ppp && echo "✅ ppp 安装/更新完成" && rm -f $(ls | grep -m1 'openppp2.*\.zip') <code></code></pre>

更新
<pre class="language-markup">cd /opt/ppp && wget -O openppp2.zip https://git.apad.pro/https://github.com/liulilittle/openppp2/releases/latest/download/openppp2-linux-amd64.zip && unzip -o openppp2.zip ppp && chmod +x ppp && rm -f openppp2.zip && systemctl restart ppp.service && echo "✅ 更新完成并重启" <code></code></pre>
拉取启动脚本
 
<pre class="language-markup">wget https://raw.githubusercontent.com/zouazhi/zouazhi/main/ppp/config/ppp.sh && chmod +x ppp.sh <code></code></pre>

拉取配置文件
<pre class="language-markup"> wget -O appsettings.json https://raw.githubusercontent.com/zouazhi/zouazhi/main/ppp/config/appsettings.json <code></code></pre>
自行修改配置文件

拉取系统服务
<pre class="language-markup">wget -P /etc/systemd/system https://raw.githubusercontent.com/zouazhi/zouazhi/main/ppp/config/ppp.service && chmod +x /opt/ppp/ && chmod +x /opt/ppp/ppp && systemctl daemon-reload && systemctl enable ppp.service  && systemctl start ppp.service && systemctl status ppp.service<code></code></pre>
