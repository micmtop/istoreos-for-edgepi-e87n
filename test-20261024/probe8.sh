echo "===== HTTP 服务"
ps | grep -E "[u]httpd|[n]ginx|[l]uci"
cat /etc/config/uhttpd
echo "===== 本机 wget /"
wget -qO- http://127.0.0.1/ 2>&1 | head -20
echo "===== 本机 wget /cgi-bin/luci/"
wget -S -O- http://127.0.0.1/cgi-bin/luci/ 2>&1 | head -25
echo "===== 403 日志"
logread | tail -15
echo "===== 证书/HTTPS"
netstat -lnt | grep -E ":443|:80"
echo "===== K9 内置主题 aurora"
uci set e87n-display.global.page=theme:aurora; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 5
screen-ctl snapshot /tmp/k9-theme.raw
ls -l /tmp/k9-theme.raw
ps | grep -E "e87n-display|/app" | grep -v grep
echo "--- 切回第 1 页"
/etc/init.d/e87n-display stop >/dev/null 2>&1
killall app 2>/dev/null
uci set e87n-display.global.page=1; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 2
ps | grep e87n-display | grep -v grep | wc -l
echo "===== K10 合法主题导入"
rm -rf /tmp/th /tmp/testtheme.tar.gz; mkdir -p /tmp/th
cp /tmp/k6.raw /tmp/th/frame.raw
printf '{"name":"AutoTest","desc":"e87n automated test"}\n' > /tmp/th/theme.json
tar -czf /tmp/testtheme.tar.gz -C /tmp/th theme.json frame.raw || echo tar-FAIL
e87n-theme install /tmp/testtheme.tar.gz testtheme
e87n-theme list
e87n-theme info testtheme
echo "--- 切换到导入主题"
uci set e87n-display.global.page=theme:testtheme; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 3
screen-ctl snapshot /tmp/k10.raw
md5sum /tmp/k10.raw /tmp/k6.raw
echo "--- 删除并回退"
/etc/init.d/e87n-display stop >/dev/null 2>&1
killall sleep 2>/dev/null
uci set e87n-display.global.page=1; uci commit e87n-display
e87n-theme remove testtheme
e87n-theme list
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 2
echo "===== K11 非法包"
rm -rf /tmp/bad; mkdir -p /tmp/bad/empty
tar -czf /tmp/bad-empty.tar.gz -C /tmp/bad/empty .
echo "-- 空包:"; e87n-theme install /tmp/bad-empty.tar.gz badempty
rm -rf /tmp/bad; mkdir -p /tmp/bad/notelf /tmp/bad/badframe
printf '{"name":"BadELF"}\n' > /tmp/bad/notelf/theme.json
printf 'NOTELF!!' > /tmp/bad/notelf/app
tar -czf /tmp/bad-elf.tar.gz -C /tmp/bad/notelf .
echo "-- 假 ELF:"; e87n-theme install /tmp/bad-elf.tar.gz badelf
printf '{"name":"BadFrame"}\n' > /tmp/bad/badframe/theme.json
dd if=/dev/zero of=/tmp/bad/badframe/frame.raw bs=1024 count=1 2>/dev/null
tar -czf /tmp/bad-frame.tar.gz -C /tmp/bad/badframe .
echo "-- 错误帧大小:"; e87n-theme install /tmp/bad-frame.tar.gz badframe
echo "-- 安装后列表:"; e87n-theme list
echo "-- 当前画面仍正常:"; screen-ctl snapshot /tmp/k11.raw; md5sum /tmp/k11.raw
