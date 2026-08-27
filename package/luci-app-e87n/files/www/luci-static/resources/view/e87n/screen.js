/*
 * E87N 屏幕控制 LuCI 页面
 * - 背光: 点亮 / 熄灭（基于 fb0/blank，实时反映状态）
 * - 内容: 显示页面选择 / 轮播间隔 / 自定义文本
 * - 预览: fb0 帧 base64 -> canvas
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

function base64Decode(b64) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var lookup = {};
    for (var i = 0; i < 64; i++) { lookup[chars.charAt(i)] = i; }
    var out = '', buffer = 0, bits = 0;
    for (var j = 0; j < String(b64).length; j++) {
        var c = String(b64).charAt(j);
        if (c === '=') { break; }
        var v = lookup[c];
        if (v === undefined) { continue; }
        buffer = (buffer << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out += String.fromCharCode((buffer >> bits) & 0xff);
        }
    }
    return out;
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

        root.appendChild(el('h2', '屏幕控制'));

        /* ---------- 背光 ---------- */
        var blCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var blRow = el('div', null, { class: 'cbi-value' });
        blRow.appendChild(el('label', '背光状态', { class: 'cbi-value-title' }));
        var blField = el('div', { class: 'cbi-value-field' });
        var blState = el('span', '未知', { class: 'cbi-value-description', id: 'bl-state' });
        var onBtn = el('button', '点亮', { class: 'btn cbi-button-apply' });
        var offBtn = el('button', '熄灭', { class: 'btn cbi-button-reload' });
        onBtn.addEventListener('click', function () { setBl('on'); });
        offBtn.addEventListener('click', function () { setBl('off'); });
        blField.appendChild(onBtn);
        blField.appendChild(document.createTextNode(' '));
        blField.appendChild(offBtn);
        blField.appendChild(document.createTextNode('  '));
        blField.appendChild(blState);
        blRow.appendChild(blField);
        blCard.appendChild(blRow);
        root.appendChild(blCard);

        function setBl(state) {
            that.call('action=set_screen&state=' + state).then(function (r) {
                blState.textContent = (r && r.out ? r.out : '') + ' -> ' + state;
                refresh();
            });
        }

        /* ---------- 显示页面 ---------- */
        var dispCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        dispCard.appendChild(el('h3', '内容设置'));

        var pgRow = el('div', null, { class: 'cbi-value' });
        pgRow.appendChild(el('label', '显示页面', { class: 'cbi-value-title' }));
        var pgWrap = el('div', { class: 'cbi-value-field' });
        var pgSel = el('select', null, { id: 'disp-page' });
        [['1', '1 - 系统概况'], ['2', '2 - 时间'], ['3', '3 - 网速图表'],
         ['4', '4 - 圆弧状态'], ['cycle', '轮播 (cycle)']].forEach(function (o) {
            var opt = el('option', o[1]);
            opt.value = o[0];
            pgSel.appendChild(opt);
        });
        pgWrap.appendChild(pgSel);
        pgRow.appendChild(pgWrap);
        dispCard.appendChild(pgRow);

        var cyRow = el('div', null, { class: 'cbi-value' });
        cyRow.appendChild(el('label', '轮播间隔(秒)', { class: 'cbi-value-title' }));
        var cyWrap = el('div', { class: 'cbi-value-field' });
        var cyInput = el('input', null, { id: 'disp-cycle', type: 'text', value: '10', size: 4 });
        cyWrap.appendChild(cyInput);
        cyRow.appendChild(cyWrap);
        dispCard.appendChild(cyRow);

        var txRow = el('div', null, { class: 'cbi-value' });
        txRow.appendChild(el('label', '自定义文本', { class: 'cbi-value-title' }));
        var txWrap = el('div', { class: 'cbi-value-field' });
        var txInput = el('input', null, { id: 'disp-text', type: 'text', placeholder: '可为空' });
        txWrap.appendChild(txInput);
        txRow.appendChild(txWrap);
        dispCard.appendChild(txRow);

        var dispBtn = el('button', '应用', { class: 'btn cbi-button-apply' });
        dispBtn.addEventListener('click', function () {
            var q = 'action=set_display&page=' + encodeURIComponent(pgSel.value) +
                    '&cycle=' + encodeURIComponent(cyInput.value || '10');
            if (txInput.value) { q += '&text=' + encodeURIComponent(txInput.value); }
            that.call(q).then(function () { refresh(); });
        });
        dispCard.appendChild(dispBtn);
        root.appendChild(dispCard);

        /* ---------- 预览 ---------- */
        var pvCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        pvCard.appendChild(el('h3', '屏幕实时预览'));
        var canvas = el('canvas', null, { id: 'scr-preview', width: '142', height: '428',
            style: 'border:1px solid #999; image-rendering:pixelated; max-height:50vh' });
        var pvBtn = el('button', '刷新预览', { class: 'btn cbi-button-reload' });
        var pvInfo = el('span', '', { class: 'cbi-value-description' });
        pvCard.appendChild(el('div', null, { style: 'text-align:center' }));
        pvCard.lastChild.appendChild(canvas);
        pvCard.appendChild(el('div', null, { style: 'text-align:center' }));
        pvCard.lastChild.appendChild(pvBtn);
        pvCard.lastChild.appendChild(document.createTextNode(' '));
        pvCard.lastChild.appendChild(pvInfo);
        root.appendChild(pvCard);

        pvBtn.addEventListener('click', function () { loadPreview(); });

        function loadPreview() {
            that.call('action=preview').then(function (r) {
                if (!r || !r.ok || !r.b64) { return; }
                canvas.width = r.w;
                canvas.height = r.h;
                var ctx = canvas.getContext('2d');
                var img = ctx.createImageData(r.w, r.h);
                var raw = base64Decode(r.b64);
                var n = Math.min(raw.length, r.w * r.h * 2);
                var j = 0;
                for (var i = 0; i < n; i += 2) {
                    var v = (raw.charCodeAt(i) << 8) | raw.charCodeAt(i + 1);
                    var r5 = (v >> 11) & 0x1f, g6 = (v >> 5) & 0x3f, b5 = v & 0x1f;
                    img.data[j++] = (r5 << 3) | (r5 >> 2);
                    img.data[j++] = (g6 << 2) | (g6 >> 4);
                    img.data[j++] = (b5 << 3) | (b5 >> 2);
                    img.data[j++] = 255;
                }
                ctx.putImageData(img, 0, 0);
                pvInfo.textContent = r.w + 'x' + r.h;
            });
        }

        function refresh() {
            that.call('action=status').then(function (s) {
                if (!s || !s.ok) { return; }
                blState.textContent = (s.screen.state === 'on') ? '当前：点亮' : '当前：熄灭';
                if (s.display) {
                    if (s.display.page) { pgSel.value = s.display.page; }
                    if (s.display.cycle) { cyInput.value = s.display.cycle; }
                }
            });
        }

        refresh();
        loadPreview();
        setInterval(refresh, 5000);
        return root;
    },

    handleSave: null,
    handleReset: null
});