/*
 * E87N 自定义显示（LVGL 工程产物）LuCI 页面
 * - 上传交叉编译好的 aarch64 ELF 显示程序
 * - 启动 / 停止 / 删除自定义程序
 * - 说明：工程需在电脑/CI 上用 aarch64 交叉编译链产出 ELF
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

        root.appendChild(el('h2', '自定义显示（LVGL 工程）'));

        /* ---------- 说明 ---------- */
        var infoCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        infoCard.appendChild(el('p',
            '上传你用 LVGL 编写的自定义屏幕程序（交叉编译为 aarch64 ELF）。' +
            '上传后可在内置显示（系统概况/时间等）与你自己的程序间切换。'));
        var hint = el('ul');
        [['编译', '电脑/CI 上用 aarch64 交叉编译链（如 aarch64-openwrt-linux-musl-gcc）编译你的 LVGL 工程'],
         ['写入', '程序直接写 /dev/fb0（142x428 RGB565），背光由系统管理'],
         ['安全', '仅接受 aarch64 ELF，上限 20MB；运行失败不会影响系统']].forEach(function (r) {
            var li = el('li', r[0] + '：' + r[1]);
            hint.appendChild(li);
        });
        infoCard.appendChild(hint);
        root.appendChild(infoCard);

        /* ---------- 状态 ---------- */
        var statCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var statLines = el('div', null, { id: 'app-status' });
        statLines.appendChild(el('div', '读取中…'));
        statCard.appendChild(statLines);
        root.appendChild(statCard);

        /* ---------- 上传 ---------- */
        var upCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        upCard.appendChild(el('h3', '上传自定义显示程序'));
        var upRow = el('div', null, { class: 'cbi-value' });
        upRow.appendChild(el('label', '选择 ELF 文件', { class: 'cbi-value-title' }));
        var upWrap = el('div', null, { class: 'cbi-value-field' });
        var upInput = el('input', null, { id: 'app-file', type: 'file', accept: '.bin,.elf,application/octet-stream' });
        upWrap.appendChild(upInput);
        upRow.appendChild(upWrap);
        upCard.appendChild(upRow);
        var upMsg = el('div', '', { class: 'cbi-value-description', id: 'app-msg' });
        upCard.appendChild(upMsg);
        var upBtn = el('button', '上传', { class: 'btn cbi-button-apply' });
        upBtn.addEventListener('click', function () { uploadApp(); });
        upCard.appendChild(upBtn);
        root.appendChild(upCard);

        /* ---------- 控制按钮 ---------- */
        var ctlCard = el('div', null, { class: 'cbi-section cbi-section-node' });
        var ctlRow = el('div', null, { class: 'cbi-value' });
        var startBtn = el('button', '启动自定义程序', { class: 'btn cbi-button-apply' });
        var stopBtn = el('button', '停止', { class: 'btn cbi-button-reload' });
        var delBtn = el('button', '删除程序', { class: 'btn cbi-button-reset' });
        startBtn.addEventListener('click', function () { appCmd('start'); });
        stopBtn.addEventListener('click', function () { appCmd('stop'); });
        delBtn.addEventListener('click', function () { appCmd('remove'); });
        ctlRow.appendChild(startBtn);
        ctlRow.appendChild(document.createTextNode(' '));
        ctlRow.appendChild(stopBtn);
        ctlRow.appendChild(document.createTextNode(' '));
        ctlRow.appendChild(delBtn);
        ctlCard.appendChild(ctlRow);
        root.appendChild(ctlCard);

        function uploadApp() {
            var file = upInput.files[0];
            if (!file) { upMsg.textContent = '请先选择编译好的 ELF 文件'; return; }
            if (file.size > 20 * 1024 * 1024) { upMsg.textContent = '文件超过 20MB 上限'; return; }
            var reader = new FileReader();
            reader.onload = function () {
                var x = new XMLHttpRequest();
                x.open('POST', '/cgi-bin/e87n?action=import_app', true);
                x.onreadystatechange = function () {
                    if (x.readyState === 4) {
                        if (x.status === 200) {
                            try {
                                var r = JSON.parse(x.responseText);
                                upMsg.textContent = (r && r.ok) ? ('上传成功：' + r.out)
                                    : ('上传失败：' + (r && r.err || x.responseText));
                            } catch (e) { upMsg.textContent = '上传失败'; }
                            refresh();
                        } else { upMsg.textContent = 'HTTP ' + x.status; }
                    }
                };
                upMsg.textContent = '上传中…';
                x.send(reader.result);
            };
            reader.readAsArrayBuffer(file);
        }

        function appCmd(cmd) {
            that.call('action=app&cmd=' + cmd).then(function (r) {
                upMsg.textContent = (r && r.ok) ? (r.out || '') : ('失败：' + (r && r.err || ''));
                refresh();
            }).catch(function (e) { upMsg.textContent = '操作失败: ' + e; });
        }

        function refresh() {
            that.call('action=app&cmd=status').then(function (r) {
                if (!r || !r.ok) { return; }
                var lines = [
                    '程序已安装: ' + (r.installed ? '是（/usr/bin/e87n-app-custom）' : '否'),
                    '运行状态: ' + (r.running ? '运行中' : '未运行')
                ];
                statLines.innerHTML = '';
                lines.forEach(function (t) { statLines.appendChild(el('div', t)); });
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
