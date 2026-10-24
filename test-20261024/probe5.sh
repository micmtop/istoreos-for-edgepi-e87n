echo "===== init.d 列表"
ls /etc/init.d/ | grep -E "e87n|screen"
echo "===== K3 背光灭时抓帧"
screen-ctl off; sleep 2; screen-ctl snapshot /tmp/k3-off.raw; screen-ctl on; sleep 1
ls -l /tmp/k3-off.raw
echo "===== K4 页面 2"
uci set e87n-display.global.page=2; uci commit e87n-display
/etc/init.d/e87n-display restart; sleep 3
screen-ctl snapshot /tmp/k4-2.raw; ls -l /tmp/k4-2.raw
echo "===== K4 页面 3"
uci set e87n-display.global.page=3; uci commit e87n-display
/etc/init.d/e87n-display restart; sleep 3
screen-ctl snapshot /tmp/k4-3.raw; ls -l /tmp/k4-3.raw
echo "===== K4 页面 4"
uci set e87n-display.global.page=4; uci commit e87n-display
/etc/init.d/e87n-display restart; sleep 3
screen-ctl snapshot /tmp/k4-4.raw; ls -l /tmp/k4-4.raw
echo "===== 恢复页面 1"
uci set e87n-display.global.page=1; uci commit e87n-display
/etc/init.d/e87n-display restart; sleep 2
echo "page=$(uci get e87n-display.global.page)"
ps | grep -E "[e87n-display]"
