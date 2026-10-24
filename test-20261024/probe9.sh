echo "===== LuCI 首页 body"
wget -qO- http://127.0.0.1/cgi-bin/luci/ 2>&1 | head -30
echo "===== LuCI POST 登录"
wget -qO- --post-data='username=root&password=' http://127.0.0.1/cgi-bin/luci/ 2>&1 | head -20
echo "===== 登录字段名"
grep -rn "luci_username\|luci_password" /usr/lib/lua/luci/controller/ /usr/lib/lua/luci/view/ 2>/dev/null | head -10
echo "===== uhttpd lua 入口 403 逻辑"
grep -n "403\|forbidden\|Forbidden" /usr/lib/lua/luci/sgi/uhttpd.lua /usr/lib/lua/luci/dispatcher.lua 2>/dev/null | head -20
echo "===== HTTPS 访问"
wget --no-check-certificate -qO- https://127.0.0.1/cgi-bin/luci/ 2>&1 | head -10
echo "===== K10 重新导入合法主题"
screen-ctl snapshot /tmp/frame.raw
rm -rf /tmp/th /tmp/testtheme.tar.gz; mkdir -p /tmp/th
cp /tmp/frame.raw /tmp/th/frame.raw
printf '{"name":"AutoTest","desc":"e87n automated test"}\n' > /tmp/th/theme.json
tar -czf /tmp/testtheme.tar.gz -C /tmp/th theme.json frame.raw
echo "-- install:"; e87n-theme install /tmp/testtheme.tar.gz testtheme
echo "-- list:"; e87n-theme list
echo "-- info:"; e87n-theme info testtheme
uci set e87n-display.global.page=theme:testtheme; uci commit e87n-display
/etc/init.d/e87n-display restart >/dev/null 2>&1
sleep 3
screen-ctl snapshot /tmp/k10.raw
echo "-- frame 一致性:"; md5sum /tmp/k10.raw /tmp/frame.raw
echo "-- 删除:"; e87n-theme remove testtheme; e87n-theme list
uci set e87n-display.global.page=1; uci commit e87n-display
/etc/init.d/e87n-display stop >/dev/null 2>&1; killall sleep 2>/dev/null
/etc/init.d/e87n-display start >/dev/null 2>&1; sleep 2
ps | grep e87n-display | grep -v grep | wc -l
echo "===== K12 连续切页 50 次"
i=0; fail=0; while [ $i -lt 50 ]; do p=$((i%4+1)); uci set e87n-display.global.page=$p; uci commit e87n-display; /etc/init.d/e87n-display restart >/dev/null 2>&1 || fail=$((fail+1)); i=$((i+1)); done
echo "fail=$fail procs=$(ps | grep e87n-display | grep -v grep | wc -l)"
uci set e87n-display.global.page=1; uci commit e87n-display; /etc/init.d/e87n-display restart >/dev/null 2>&1
echo "===== K13 显示内存/句柄采样"
pid=$(pidof e87n-display); echo "pid=$pid"
grep -E "VmRSS|Threads" /proc/$pid/status 2>/dev/null
ls /proc/$pid/fd 2>/dev/null | wc -l
free -m | head -2
echo "===== K10 后主题列表"
e87n-theme list
