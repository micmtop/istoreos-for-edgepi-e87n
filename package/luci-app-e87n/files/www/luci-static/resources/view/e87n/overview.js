/*
 * E87N 风扇/屏幕控制 LuCI 页面（现代 view 模式）
 * - 后端: /cgi-bin/e87n (ash CGI, 返回 JSON)
 * - 风扇: 模式(auto/manual/off) + 手动 PWM + 实时状态轮询
 * - 屏幕: 背光开关 + 内容自定义(page/轮播/文本) + fb0 实时预览(canvas)
 */
'use strict';

'require ui';
'require view';
'require rpc';

/* 页面级小工具：字符串拼接等 */
function str(v) { return v == null ? '' : String(v); }

return view.extend({
    __init__: function() {
        this.last = null;
    },

    /* 调用 CGI 并解析 JSON */
    call: function(query) {
        var that = this;
        return new Promise(function(resolve, reject) {
            XHR.get('/cgi-bin/e87n?' + query, function(err, data) {
                if (err) {
                    reject(err);
                    return;
                }
                try {
                    var j = JSON.parse(data);
                    that.last = j;
                    resolve(j);
                } catch (e) {
                    reject(e);
                }
            });
        });
    },

    /* 获取并缓存状态，同时刷新状态栏文本 */
    refreshStatus: function() {
        var that = this;
        return this.call('action=status').then(function(j) {
            if (!j || !j.ok) {
                return j;
            }
            var el = document.getElementById('fan-status');
            if (el && j.fan && j.screen && j.display) {
                var mode = (j.fan.mode === 'manual' ? '手动'
                    : (j.fan.mode === 'off' ? '关闭' : '自动'));
                el.textContent =
                    '温度 ' + str(j.temp) + ' ℃, PWM ' + str(j.pwm) +
                    ', 模式 ' + mode +
                    (j.fan.running ? ', 风扇服务运行中' : ', 风扇服务停止') +
                    ' | 屏幕 ' + (j.screen.state === 'on' ? '点亮' : '熄灭') +
                    ' | 显示 ' + (j.display.running ? '运行' : '停止');
            }
            return j;
        }).catch(function(e) {
            var el = document.getElementById('fan-status');
            if (el) {
                el.textContent = '状态读取失败: ' + e;
            }
            return null;
        });
    },

    render: function() {
        var that = this;
        var container = E([]);

        /* base64 解码（预览帧） */
        function base64Decode(b64) {
            var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
            var lookup = {};
            for (var i = 0; i < 64; i++) {
                lookup[chars.charAt(i)] = i;
            }
            var out = '';
            var buffer = 0;
            var bits = 0;
            for (var j = 0; j < str(b64).length; j++) {
                var c = str(b64).charAt(j);
                if (c === '=') {
                    break;
                }
                var v = lookup[c];
                if (v === undefined) {
                    continue;
                }
                buffer = (buffer << 6) | v;
                bits += 6;
                if (bits >= 8) {
                    bits -= 8;
                    out += String.fromCharCode((buffer >> bits) & 0xff);
                }
            }
            return out;
        }

        // =========================================================
        //  风扇控制
        // =========================================================
        container.appendChild(E('h2', { class: 'cbi-section-title' }, _('风扇控制')));

        var fanForm = E('div', { class: 'cbi-section cbi-section-node' });
        container.appendChild(fanForm);

        var modeRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('模式')),
            E('div', { class: 'cbi-value-field' })
        );
        var modeField = modeRow.lastChild;
        var modeSel = E('select', { id: 'fan-mode' },
            E('option', { value: 'auto' }, _('自动（按温度曲线）')),
            E('option', { value: 'manual' }, _('手动')),
            E('option', { value: 'off' }, _('关闭'))
        );
        modeField.appendChild(modeSel);
        fanForm.appendChild(modeRow);

        var pwmRow = E('div', { class: 'cbi-value', style: 'display:none' },
            E('label', { class: 'cbi-value-title' }, _('PWM 值')),
            E('div', { class: 'cbi-value-field' })
        );
        var pwmField = pwmRow.lastChild;
        var pwmRange = E('input', { id: 'fan-pwm', type: 'range', min: '0', max: '255', value: '128' });
        var pwmReadout = E('span', { id: 'fan-pwm-out', class: 'cbi-value-description' }, '128 / 255');
        pwmField.appendChild(pwmRange);
        pwmField.appendChild(pwmReadout);
        fanForm.appendChild(pwmRow);

        var statRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('状态')),
            E('div', { class: 'cbi-value-field', id: 'fan-status' }, '--')
        );
        fanForm.appendChild(statRow);

        var applyBtn = E('button', { class: 'btn cbi-button-apply' }, _('应用'));
        fanForm.appendChild(E('div', { class: 'cbi-page-actions' }, applyBtn));

        // =========================================================
        //  屏幕控制
        // =========================================================
        container.appendChild(E('h2', { class: 'cbi-section-title', style: 'margin-top:2em' }, _('屏幕控制')));

        var scrForm = E('div', { class: 'cbi-section cbi-section-node' });
        container.appendChild(scrForm);

        var blRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('背光')),
            E('div', { class: 'cbi-value-field' })
        );
        var blBtn = E('button', { id: 'scr-toggle', class: 'btn cbi-button-reload' }, _('点亮/熄灭'));
        blRow.lastChild.appendChild(blBtn);
        scrForm.appendChild(blRow);

        var pgRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('显示页面')),
            E('div', { class: 'cbi-value-field' })
        );
        var pgSel = E('select', { id: 'disp-page' },
            E('option', { value: '1' }, _('1 - 系统概况')),
            E('option', { value: '2' }, _('2 - 时间')),
            E('option', { value: '3' }, _('3 - 网速图表')),
            E('option', { value: '4' }, _('4 - 圆弧状态')),
            E('option', { value: 'cycle' }, _('轮播 (cycle)'))
        );
        pgRow.lastChild.appendChild(pgSel);
        scrForm.appendChild(pgRow);

        var cyRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('轮播间隔(秒)')),
            E('div', { class: 'cbi-value-field' })
        );
        var cyInput = E('input', { id: 'disp-cycle', type: 'text', value: '10' });
        cyRow.lastChild.appendChild(cyInput);
        scrForm.appendChild(cyRow);

        var txRow = E('div', { class: 'cbi-value' },
            E('label', { class: 'cbi-value-title' }, _('自定义文本')),
            E('div', { class: 'cbi-value-field' })
        );
        var txInput = E('input', { id: 'disp-text', type: 'text',
            placeholder: _('附加到系统概况页顶部，可为空') });
        txRow.lastChild.appendChild(txInput);
        scrForm.appendChild(txRow);

        var dispApply = E('button', { class: 'btn cbi-button-apply' }, _('应用'));
        scrForm.appendChild(E('div', { class: 'cbi-page-actions' }, dispApply));

        scrForm.appendChild(E('h3', {}, _('屏幕实时预览')));
        var previewWrap = E('div', { style: 'text-align:center; padding:8px' });
        var canvas = E('canvas', { id: 'scr-preview', width: '142', height: '428',
            style: 'border:1px solid #999; image-rendering:pixelated; width:142px; height:428px; max-height:40vh;' });
        previewWrap.appendChild(canvas);
        previewWrap.appendChild(E('div', {},
            E('button', { id: 'preview-refresh', class: 'btn cbi-button-reload' }, _('刷新预览')),
            ' ',
            E('span', { id: 'preview-info', class: 'cbi-value-description' }, '')
        ));
        scrForm.appendChild(previewWrap);

        // =========================================================
        //  事件绑定
        // =========================================================
        modeSel.addEventListener('change', function() {
            pwmRow.style.display = (modeSel.value === 'manual') ? '' : 'none';
        });
        pwmRange.addEventListener('input', function() {
            pwmReadout.textContent = pwmRange.value + ' / 255';
        });

        applyBtn.addEventListener('click', function() {
            var mode = modeSel.value;
            var q = 'action=set_fan&mode=' + encodeURIComponent(mode);
            if (mode === 'manual') {
                q += '&pwm=' + encodeURIComponent(pwmRange.value);
            }
            that.call(q).then(function() {
                that.refreshStatus();
            });
        });

        blBtn.addEventListener('click', function() {
            that.call('action=status').then(function(s) {
                var next = (s && s.screen && s.screen.state === 'on') ? 'off' : 'on';
                return that.call('action=set_screen&state=' + next);
            }).then(function() {
                that.refreshStatus();
            });
        });

        dispApply.addEventListener('click', function() {
            var q = 'action=set_display&page=' + encodeURIComponent(pgSel.value) +
                    '&cycle=' + encodeURIComponent(cyInput.value || '10');
            if (txInput.value) {
                q += '&text=' + encodeURIComponent(txInput.value);
            }
            that.call(q).then(function() {
                that.refreshStatus();
            });
        });

        previewWrap.querySelector('#preview-refresh').addEventListener('click', function() {
            that.call('action=preview').then(function(r) {
                if (!r || !r.ok || !r.b64) {
                    return;
                }
                if (r.w !== canvas.width || r.h !== canvas.height) {
                    canvas.width = r.w;
                    canvas.height = r.h;
                }
                var ctx = canvas.getContext('2d');
                var img = ctx.createImageData(r.w, r.h);
                var raw = base64Decode(r.b64);
                var pixels = r.w * r.h;
                for (var i = 0, j = 0; i < Math.min(raw.length, pixels * 2); i += 2) {
                    var v = (raw.charCodeAt(i) << 8) | raw.charCodeAt(i + 1);
                    var r5 = (v >> 11) & 0x1f, g6 = (v >> 5) & 0x3f, b5 = v & 0x1f;
                    img.data[j++] = (r5 << 3) | (r5 >> 2);
                    img.data[j++] = (g6 << 2) | (g6 >> 4);
                    img.data[j++] = (b5 << 3) | (b5 >> 2);
                    img.data[j++] = 255;
                }
                ctx.putImageData(img, 0, 0);
                document.getElementById('preview-info').textContent =
                    r.w + 'x' + r.h + ' (' + str(r.len || '') + '/' + str(r.size) + ' bytes)';
            });
        });

        // 初始状态回填 + 轮询
        that.refreshStatus().then(function(s) {
            if (!s || !s.ok) {
                return;
            }
            if (s.fan.mode === 'manual') {
                modeSel.value = 'manual';
                pwmRow.style.display = '';
                var cur = parseInt(s.pwm, 10);
                if (!isNaN(cur)) { pwmRange.value = cur; pwmReadout.textContent = cur + ' / 255'; }
            } else if (s.fan.mode === 'off') {
                modeSel.value = 'off';
            }
            if (s.display) {
                if (s.display.page) {
                    pgSel.value = s.display.page;
                }
                if (s.display.cycle) {
                    cyInput.value = s.display.cycle;
                }
            }
        });
        setInterval(function() { that.refreshStatus(); }, 5000);

        return container;
    },

    handleSave: null,
    handleReset: null
});