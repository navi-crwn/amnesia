// Amnesia for Windows, the page side. Talks to C# (Bridge.cs) through WebView2 messages.
(function () {
  'use strict';
  var wv = window.chrome && window.chrome.webview;
  var waiting = {}, next = 1;
  if (wv) wv.addEventListener('message', function (e) {
    var m = e.data, w = waiting[m.id];
    if (!w) return;
    delete waiting[m.id];
    m.ok ? w.ok(m.data) : w.fail(new Error(m.error || 'Unknown error'));
  });
  function ask(cmd) {
    return new Promise(function (ok, fail) {
      if (!wv) return fail(new Error('Open this page inside the Amnesia app.'));
      var id = next++;
      waiting[id] = { ok: ok, fail: fail };
      wv.postMessage({ id: id, cmd: cmd });
    });
  }

  var T = {
    en: {},
    id: {
      badge: 'Versi awal',
      statusTitle: 'Belum aktif',
      statusText: 'Ini versi Windows yang pertama. Amnesia cuma menunjukkan apa yang akan dihapus. Tidak ada yang dihapus, baik saat logout maupun kapan pun.',
      previewTitle: 'Yang akan dihapus',
      previewText: 'Simulasi di folder user kamu. Folder Keep, Keep List dan semua yang dibutuhkan Windows untuk login selalu aman.',
      previewBtn: 'Lihat simulasi',
      keptTitle: 'Yang tetap ada',
      site: 'Website Amnesia',
      busy: 'Sedang mengecek folder user kamu...',
      sum: function (n) { return n + ' item akan dihapus. Ini cuma simulasi, tidak ada yang disentuh.'; },
      more: function (n) { return '...dan ' + n + ' lainnya'; },
      file: 'file', folder: 'folder', kept: 'aman'
    }
  };
  var EN = {
    busy: 'Checking your user folder...',
    sum: function (n) { return n + ' item' + (n === 1 ? '' : 's') + ' would be deleted. This is only a preview, nothing was touched.'; },
    more: function (n) { return '...and ' + n + ' more'; },
    file: 'file', folder: 'folder', kept: 'stays'
  };
  var L = EN;
  function setLang(lang) {
    if (lang !== 'id') return;
    L = Object.assign({}, EN, T.id);
    document.documentElement.lang = 'id';
    document.querySelectorAll('[data-t]').forEach(function (el) { var v = T.id[el.dataset.t]; if (v) el.textContent = v; });
  }

  var $ = function (id) { return document.getElementById(id); };
  function fill(ul, rows, cap) {
    ul.textContent = '';
    rows.slice(0, cap).forEach(function (r) {
      var li = document.createElement('li'), k = document.createElement('span'), p = document.createElement('span');
      k.className = 'k'; k.textContent = r.kind; p.textContent = r.path;
      li.append(k, p); ul.append(li);
    });
    if (rows.length > cap) { var li = document.createElement('li'); li.textContent = L.more(rows.length - cap); ul.append(li); }
  }

  ask('info').then(function (i) {
    $('ver').textContent = 'v' + i.version;
    $('win').textContent = i.windows;
    setLang(i.lang);
  }).catch(function (e) { $('msg').textContent = e.message; });

  $('run').addEventListener('click', function () {
    var b = this;
    b.disabled = true; $('msg').textContent = L.busy; $('result').hidden = true;
    ask('preview').then(function (r) {
      var items = [].concat(r.items || []), kept = [].concat(r.kept || []);
      $('msg').textContent = '';
      $('sum').textContent = L.sum(r.count);
      fill($('items'), items.map(function (x) { return { kind: L[x.kind] || x.kind, path: x.path }; }), 500);
      fill($('kept'), kept.map(function (p) { return { kind: L.kept, path: p }; }), 500);
      $('result').hidden = false;
    }).catch(function (e) { $('msg').textContent = e.message; })
      .then(function () { b.disabled = false; });
  });
})();
