/*
 * E87N 风扇控制 LuCI 页面
 * - 模式: 自动（按温度曲线）/ 手动 / 关闭
 * - 手动 PWM 滑杆
 * - 温控曲线展示（本地插值预览）
 */
'use strict';

'require view';

function el(tag, text, attrs) {
    var n = document.createElement(tag);
    if (text != null) { n.textContent = text; }
    if (attrs) {
        for (var k in attrs) { n.setAttribute(k, attrs[k]); }
    }
    return n;
}

return view.extend({
    call: function (query) {
        return new Promise(function (resolve, reject) {
            var x = new XMLHttpRequest();
            x.open('GET', '/cgi-bin/e87n?' + query, true);
            x.onreadystatechange = function () {
                if (x.readyState === 4) {
                    if (x.status === 200) {
                        try { resolve(JSON.parse(x.responseText)); }
                        catch (e) { reject(e); }
                    } else { reject(new Error('HTTP ' + x.status)); }
                }
            };
            x.send();
        });
    },

    render: function () {
        var that = this;
        var root = el('div', null, { class: 'cbi-map' });

        /* 标题 */
        root.appendChild(el('h2', '风扇控制'));

        /* 状态卡片 */
        var statCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var statLines = el('div', null, { id: 'fan-status' });
        statLines.appendChild(el('div', '读取中…'));
        statCard.appendChild(statLines);
        root.appendChild(statCard);

        /* 模式选择 */
        var modeCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var modeRow = el('div', null, { class: 'cbi-value' });
        modeRow.appendChild(el('label', '模式', { class: 'cbi-value-title' }));
        var modeWrap = el('div', { class: 'cbi-value-field' });
        var modeSel = el('select', null, { id: 'fan-mode' });
        [['auto', '自动（按温度曲线）'], ['manual', '手动'], ['off', '关闭']].forEach(function (o) {
            var opt = el('option', o[1]);
            opt.value = o[0];
            modeSel.appendChild(opt);
        });
        modeWrap.appendChild(modeSel);
        modeRow.appendChild(modeWrap);
        modeCard.appendChild(modeRow);

        /* 手动 PWM */
        var pwmRow = el('div', null, { class: 'cbi-value', id: 'pwm-row', style: 'display:none' });
        pwmRow.appendChild(el('label', '手动 PWM (0-255)', { class: 'cbi-value-title' }));
        var pwmWrap = el('div', { class: 'cbi-value-field' });
        var pwmRange = el('input', null, { id: 'fan-pwm', type: 'range', min: '0', max: '255', value: '128' });
        var pwmOut = el('span', '128 / 255', { class: 'cbi-value-description' });
        pwmRange.addEventListener('input', function () {
            pwmOut.textContent = pwmRange.value + ' / 255';
        });
        pwmWrap.appendChild(pwmRange);
        pwmWrap.appendChild(document.createTextNode(' '));
        pwmWrap.appendChild(pwmOut);
        pwmRow.appendChild(pwmWrap);
        modeCard.appendChild(pwmRow);

        /* 应用按钮 */
        var applyBtn = el('button', '应用', { class: 'btn cbi-button-apply' });
        applyBtn.addEventListener('click', function () {
            var q = 'action=set_fan&mode=' + encodeURIComponent(modeSel.value);
            if (modeSel.value === 'manual') {
                q += '&pwm=' + encodeURIComponent(pwmRange.value);
            }
            that.call(q).then(function () { refresh(); });
        });
        modeCard.appendChild(applyBtn);
        root.appendChild(modeCard);

        /* 温度曲线卡片 */
        var curveCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        curveCard.appendChild(el('h3', '温控曲线（温度 ℃ → 风扇 PWM）'));
        var curveBody = el('div', null, { id: 'fan-curve' });
        curveBody.appendChild(el('div', '读取中…'));
        curveCard.appendChild(curveBody);
        root.appendChild(curveCard);

        /* 刷新状态 */
        function refresh() {
            that.call('action=status').then(function (s) {
                if (!s || !s.ok) { return; }
                var mode = (s.fan.mode === 'manual') ? '手动'
                    : (s.fan.mode === 'off') ? '关闭' : '自动';
                var lines = [
                    '温度: ' + s.temp + ' ℃',
                    '当前 PWM: ' + s.pwm,
                    '模式: ' + mode + (s.fan.running ? '（服务运行中）' : '（服务已停止）')
                ];
                statLines.innerHTML = '';
                lines.forEach(function (t) { statLines.appendChild(el('div', t)); });

                modeSel.value = (s.fan.mode === 'manual') ? 'manual'
                    : (s.fan.mode === 'off') ? 'off' : 'auto';
                pwmRow.style.display = (s.fan.mode === 'manual') ? '' : 'none';
                if (s.fan.mode === 'manual') {
                    var pv = parseInt(s.pwm, 10);
                    if (!isNaN(pv) && s.pwm !== '--') { pwmRange.value = pv; pwmOut.textContent = pv + ' / 255'; }
                }

                /* 曲线渲染 */
                if (s.curve && s.curve.length) {
                    var tbl = el('table', null, { class: 'cbi-section-table' });
                    var trh = el('tr');
                    trh.appendChild(el('th', '温度 (℃)'));
                    trh.appendChild(el('th', 'PWM'));
                    trh.appendChild(el('th', '说明'));
                    tbl.appendChild(trh);
                    s.curve.forEach(function (pt) {
                        var tr = el('tr');
                        tr.appendChild(el('td', pt.t));
                        tr.appendChild(el('td', pt.pwm));
                        tr.appendChild(el('td', '≥' + pt.t + '℃ 时按线性插值到 ' + pt.pwm));
                        tbl.appendChild(tr);
                    });
                    curveBody.innerHTML = '';
                    curveBody.appendChild(tbl);
                } else {
                    curveBody.innerHTML = '';
                    curveBody.appendChild(el('div', '未配置温控曲线'));
                }
            }).catch(function (e) {
                statLines.innerHTML = '';
                statLines.appendChild(el('div', '状态获取失败: ' + e));
            });
        }

        refresh();
        setInterval(refresh, 5000);
        return root;
    },

    handleSave: null,
    handleReset: null
});