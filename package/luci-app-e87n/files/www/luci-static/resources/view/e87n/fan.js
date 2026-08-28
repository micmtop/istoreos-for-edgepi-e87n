/*
 * E87N 风扇控制 LuCI 页面
 * - 模式: 自动（按温度曲线）/ 手动 / 关闭
 * - PWM 显示等价风速百分比；手动滑杆用百分比
 * - 平面直角坐标系温控曲线：Canvas 画温度(℃) -> 风速(%) 折线，
 *   点击加点 / 拖拽移动 / 双击删点，保存回 uci
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
    call: function (query, body) {
        return new Promise(function (resolve, reject) {
            var x = new XMLHttpRequest();
            var method = body ? 'POST' : 'GET';
            x.open(method, '/cgi-bin/e87n?' + query, true);
            x.onreadystatechange = function () {
                if (x.readyState === 4) {
                    if (x.status === 200) {
                        try { resolve(JSON.parse(x.responseText)); }
                        catch (e) { reject(e); }
                    } else { reject(new Error('HTTP ' + x.status)); }
                }
            };
            x.send(body || null);
        });
    },

    render: function () {
        var that = this;
        var root = el('div', null, { class: 'cbi-map' });

        root.appendChild(el('h2', '风扇控制'));

        /* ---------- 状态卡片 ---------- */
        var statCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var statLines = el('div', null, { id: 'fan-status' });
        statLines.appendChild(el('div', '读取中…'));
        statCard.appendChild(statLines);
        root.appendChild(statCard);

        /* ---------- 模式选择 ---------- */
        var modeCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var modeRow = el('div', null, { class: 'cbi-value' });
        modeRow.appendChild(el('label', '模式', { class: 'cbi-value-title' }));
        var modeWrap = el('div', null, { class: 'cbi-value-field' });
        var modeSel = el('select', null, { id: 'fan-mode' });
        [['auto', '自动（按温度曲线）'], ['manual', '手动'], ['off', '关闭']].forEach(function (o) {
            var opt = el('option', o[1]);
            opt.value = o[0];
            modeSel.appendChild(opt);
        });
        modeWrap.appendChild(modeSel);
        modeRow.appendChild(modeWrap);
        modeCard.appendChild(modeRow);

        /* 手动风速百分比 */
        var pwmRow = el('div', null, { class: 'cbi-value', id: 'pwm-row', style: 'display:none' });
        pwmRow.appendChild(el('label', '手动风速 (%)', { class: 'cbi-value-title' }));
        var pwmWrap = el('div', null, { class: 'cbi-value-field' });
        var pwmRange = el('input', null, { id: 'fan-pwm', type: 'range', min: '0', max: '100', value: '50' });
        var pwmOut = el('span', '50 %', { class: 'cbi-value-description' });
        pwmRange.addEventListener('input', function () {
            pwmOut.textContent = pwmRange.value + ' %';
        });
        pwmWrap.appendChild(pwmRange);
        pwmWrap.appendChild(document.createTextNode(' '));
        pwmWrap.appendChild(pwmOut);
        pwmRow.appendChild(pwmWrap);
        modeCard.appendChild(pwmRow);

        var applyBtn = el('button', '应用', { class: 'btn cbi-button-apply' });
        applyBtn.addEventListener('click', function () {
            var q = 'action=set_fan&mode=' + encodeURIComponent(modeSel.value);
            if (modeSel.value === 'manual') {
                q += '&pwm=' + encodeURIComponent(Math.round(pwmRange.value * 255 / 100));
            }
            that.call(q).then(function () { refresh(); });
        });
        modeCard.appendChild(applyBtn);
        root.appendChild(modeCard);

        /* ---------- 温控曲线（平面直角坐标系） ---------- */
        var curveCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        curveCard.appendChild(el('h3', '温控曲线（温度 ℃ → 风速 %）'));
        curveCard.appendChild(el('div', '点击坐标添加控制点，拖动移动，双击删除。保存后实时生效。',
            { class: 'cbi-value-description' }));

        /* Canvas 画布：x=温度(20~95℃)，y=风速(0~100%) */
        var canvas = el('canvas', null, {
            id: 'fan-curve-canvas',
            width: '640', height: '400',
            style: 'border:1px solid #999; background:#fafafa; max-width:100%; touch-action:none'
        });
        var cvWrap = el('div', null, { style: 'text-align:center' });
        cvWrap.appendChild(canvas);
        curveCard.appendChild(cvWrap);

        var curveBar = el('div', null, { class: 'cbi-value' });
        var cvInfo = el('span', '', { class: 'cbi-value-description' });
        var saveCurveBtn = el('button', '保存曲线', { class: 'btn cbi-button-apply' });
        saveCurveBtn.addEventListener('click', function () { saveCurve(); });
        curveBar.appendChild(cvInfo);
        curveBar.appendChild(document.createTextNode(' '));
        curveBar.appendChild(saveCurveBtn);
        curveCard.appendChild(curveBar);
        root.appendChild(curveCard);

        /* ---------- 坐标映射 ---------- */
        var PADL = 48, PADR = 12, PADT = 16, PADB = 36;
        var XMIN = 20, XMAX = 95, YMAX = 100;
        function px(x) { return PADL + (x - XMIN) / (XMAX - XMIN) * (canvas.width - PADL - PADR); }
        function py(pct) { return PADT + (1 - pct / YMAX) * (canvas.height - PADT - PADB); }
        function ix(cx) { return Math.round(XMIN + (cx - PADL) / (canvas.width - PADL - PADR) * (XMAX - XMIN)); }
        function iy(cy) { return Math.round(YMAX - (cy - PADT) / (canvas.height - PADT - PADB) * YMAX); }

        var points = [];  // [{t, pct}]

        function draw() {
            var ctx = canvas.getContext('2d');
            ctx.clearRect(0, 0, canvas.width, canvas.height);
            ctx.fillStyle = '#fafafa'; ctx.fillRect(0, 0, canvas.width, canvas.height);
            /* 网格 + 坐标轴 */
            ctx.strokeStyle = '#ddd'; ctx.lineWidth = 1;
            for (var t = XMIN; t <= XMAX; t += 15) {
                var x = px(t);
                ctx.beginPath(); ctx.moveTo(x, PADT); ctx.lineTo(x, canvas.height - PADB); ctx.stroke();
                ctx.fillStyle = '#666'; ctx.font = '11px sans-serif';
                ctx.fillText(t + '℃', x - 10, canvas.height - PADB + 16);
            }
            for (var p = 0; p <= 100; p += 20) {
                var y = py(p);
                ctx.beginPath(); ctx.moveTo(PADL, y); ctx.lineTo(canvas.width - PADR, y); ctx.stroke();
                ctx.fillText(p + '%', 6, y + 4);
            }
            ctx.fillStyle = '#444'; ctx.font = 'bold 12px sans-serif';
            ctx.fillText('风速 %', 8, PADT + 4);
            /* 折线 */
            if (points.length) {
                ctx.strokeStyle = '#1a73e8'; ctx.lineWidth = 2;
                ctx.beginPath();
                points.forEach(function (pt, i) {
                    var x = px(pt.t), y = py(pt.pct);
                    if (i === 0) { ctx.moveTo(x, y); } else { ctx.lineTo(x, y); }
                });
                ctx.stroke();
                /* 控制点 */
                points.forEach(function (pt) {
                    var x = px(pt.t), y = py(pt.pct);
                    ctx.fillStyle = '#1a73e8';
                    ctx.beginPath(); ctx.arc(x, y, 5, 0, Math.PI * 2); ctx.fill();
                    ctx.fillStyle = '#fff';
                    ctx.beginPath(); ctx.arc(x, y, 2, 0, Math.PI * 2); ctx.fill();
                });
            }
            cvInfo.textContent = points.length ? '已编辑 ' + points.length + ' 个控制点' : '点击添加控制点';
        }

        function hitTest(cx, cy) {
            for (var i = 0; i < points.length; i++) {
                var dx = cx - px(points[i].t), dy = cy - py(points[i].pct);
                if (dx * dx + dy * dy < 100) { return i; }
            }
            return -1;
        }

        var dragIdx = -1;
        canvas.addEventListener('mousedown', function (e) {
            var rect = canvas.getBoundingClientRect();
            var cx = (e.clientX - rect.left) * canvas.width / rect.width;
            var cy = (e.clientY - rect.top) * canvas.height / rect.height;
            var idx = hitTest(cx, cy);
            if (idx >= 0) {
                dragIdx = idx;
            } else if (cx >= PADL && cx <= canvas.width - PADR && cy >= PADT && cy <= canvas.height - PADB) {
                points.push({ t: ix(cx), pct: iy(cy) });
                points.sort(function (a, b) { return a.t - b.t; });
                draw();
            }
        });
        canvas.addEventListener('mousemove', function (e) {
            if (dragIdx < 0) { return; }
            var rect = canvas.getBoundingClientRect();
            var cx = (e.clientX - rect.left) * canvas.width / rect.width;
            var cy = (e.clientY - rect.top) * canvas.height / rect.height;
            points[dragIdx].t = Math.max(XMIN, Math.min(XMAX, ix(cx)));
            points[dragIdx].pct = Math.max(0, Math.min(100, iy(cy)));
            points.sort(function (a, b) { return a.t - b.t; });
            draw();
        });
        window.addEventListener('mouseup', function () { dragIdx = -1; });
        canvas.addEventListener('dblclick', function (e) {
            var rect = canvas.getBoundingClientRect();
            var cx = (e.clientX - rect.left) * canvas.width / rect.width;
            var cy = (e.clientY - rect.top) * canvas.height / rect.height;
            var idx = hitTest(cx, cy);
            if (idx >= 0) {
                points.splice(idx, 1);
                draw();
            }
        });

        function saveCurve() {
            if (!points.length) { cvInfo.textContent = '曲线为空，无法保存'; return; }
            var q = 'action=set_curve&curve=' + encodeURIComponent(
                points.map(function (pt) { return pt.t + ':' + pt.pct; }).join(','));
            that.call(q).then(function (r) {
                cvInfo.textContent = (r && r.ok) ? '已保存并生效' : ('保存失败: ' + (r && r.err || ''));
            }).catch(function (e) { cvInfo.textContent = '保存失败: ' + e; });
        }

        /* ---------- 状态刷新 ---------- */
        var initialized = false;
        function refresh() {
            that.call('action=status').then(function (s) {
                if (!s || !s.ok) { return; }
                var mode = (s.fan.mode === 'manual') ? '手动'
                    : (s.fan.mode === 'off') ? '关闭' : '自动';
                var pct = (s.pwm_pct !== undefined && s.pwm_pct !== null) ? s.pwm_pct + ' %' : '--';
                var lines = [
                    '温度: ' + s.temp + ' ℃',
                    '当前风速: ' + pct + '（PWM ' + s.pwm + '）',
                    '模式: ' + mode + (s.fan.running ? '（服务运行中）' : '（服务已停止）')
                ];
                statLines.innerHTML = '';
                lines.forEach(function (t) { statLines.appendChild(el('div', t)); });

                modeSel.value = (s.fan.mode === 'manual') ? 'manual'
                    : (s.fan.mode === 'off') ? 'off' : 'auto';
                pwmRow.style.display = (s.fan.mode === 'manual') ? '' : 'none';
                if (s.fan.mode === 'manual') {
                    var pv = parseInt(s.pwm, 10);
                    if (!isNaN(pv) && s.pwm !== '--') {
                        var pcp = Math.round(pv * 100 / 255);
                        pwmRange.value = pcp; pwmOut.textContent = pcp + ' %';
                    }
                }

                /* 曲线：仅首次加载同步到 Canvas，之后不覆盖用户编辑 */
                if (!initialized) {
                    if (s.curve && s.curve.length) {
                        points = s.curve.map(function (pt) {
                            return { t: parseInt(pt.t, 10) || 0, pct: parseInt(pt.pct, 10) || 0 };
                        });
                        points.sort(function (a, b) { return a.t - b.t; });
                    }
                    initialized = true;
                    draw();
                }
            }).catch(function (e) {
                statLines.innerHTML = '';
                statLines.appendChild(el('div', '状态获取失败: ' + e));
            });
        }

        refresh();
        setInterval(refresh, 5000);
        draw();
        return root;
    },

    handleSave: null,
    handleReset: null
});
