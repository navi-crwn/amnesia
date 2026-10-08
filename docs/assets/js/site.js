/* Amnesia website: language, theme, copy buttons, navbar, GitHub numbers,
   arrows/dots for the slide scenes, then motion.
   Motion only starts when GSAP loaded and the visitor allows motion.
   Without it the page is complete and readable as plain HTML. */
(function () {
  'use strict';
  var root = document.documentElement;
  var Scenes = window.AmnesiaScenes || {};
  var UI = window.AmnesiaUI = window.AmnesiaUI || {};

  // ---------- language ----------
  function setLang(l) {
    root.lang = l;
    document.getElementById('lang-en').setAttribute('aria-pressed', String(l === 'en'));
    document.getElementById('lang-id').setAttribute('aria-pressed', String(l === 'id'));
    try { localStorage.setItem('lang', l); } catch (e) {}
    // screenshots follow the language
    document.querySelectorAll('img[data-shot]').forEach(function (img) {
      var src = 'screens/' + l + '/' + img.dataset.shot + '.png';
      if (img.getAttribute('src') !== src) { img.style.display = ''; img.src = src; }
    });
    document.dispatchEvent(new CustomEvent('amnesia:lang', { detail: l }));
  }
  document.getElementById('lang-en').addEventListener('click', function () { setLang('en'); });
  document.getElementById('lang-id').addEventListener('click', function () { setLang('id'); });
  setLang(root.lang === 'id' ? 'id' : 'en');

  // ---------- theme: follows the system until the visitor picks one ----------
  var sysLight = window.matchMedia('(prefers-color-scheme: light)');
  UI.theme = function () {
    var t = root.getAttribute('data-theme');
    return t === 'light' || t === 'dark' ? t : (sysLight.matches ? 'light' : 'dark');
  };
  function themeChanged() {
    var btn = document.getElementById('theme');
    var light = UI.theme() === 'light';
    btn.setAttribute('aria-pressed', String(light));
    btn.setAttribute('aria-label', light ? 'Switch to dark mode' : 'Switch to light mode');
    document.dispatchEvent(new CustomEvent('amnesia:theme', { detail: UI.theme() }));
  }
  document.getElementById('theme').addEventListener('click', function () {
    var next = UI.theme() === 'light' ? 'dark' : 'light';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('theme', next); } catch (e) {}
    themeChanged();
  });
  if (sysLight.addEventListener) sysLight.addEventListener('change', function () { if (!root.hasAttribute('data-theme')) themeChanged(); });
  themeChanged();

  // ---------- copy buttons ----------
  document.querySelectorAll('.term .copy').forEach(function (b) {
    b.addEventListener('click', function () {
      var code = b.parentElement.querySelector('code');
      var t = code.dataset.full || code.textContent;
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(t).then(function () {
        b.textContent = '✓';
        setTimeout(function () { b.textContent = 'Copy'; }, 1500);
      });
    });
  });

  // ---------- navbar turns solid after scrolling ----------
  var nav = document.getElementById('nav');
  function navState() { nav.classList.toggle('solid', window.scrollY > 24); }
  window.addEventListener('scroll', navState, { passive: true });
  navState();

  // ---------- running text: two copies so the loop is seamless ----------
  document.querySelectorAll('.mq-track').forEach(function (t) {
    t.innerHTML += t.innerHTML;
  });

  // ---------- GitHub numbers (version, languages, commits, releases…) ----------
  // Read straight from the public GitHub API by the visitor's browser. No cookies,
  // no referrer, cached for an hour. If it fails, the built-in values stay.
  // The star count is never shown, only the "Star this repo" button.
  (function () {
    var KEY = 'gh-repo-v2', repo = 'https://api.github.com/repos/navi-crwn/amnesia';
    var COLORS = ['var(--orange)', 'var(--green)', 'var(--cyan)', 'var(--indigo)', 'var(--pink)', 'var(--violet)'];
    var data = null;
    function all(sel, f) { document.querySelectorAll('[data-gh=' + sel + ']').forEach(f); }
    function num(n) { return typeof n === 'number' ? n.toLocaleString(root.lang === 'id' ? 'id-ID' : 'en-US') : null; }
    function day(iso) {
      return new Date(iso).toLocaleDateString(root.lang === 'id' ? 'id-ID' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    }
    function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
    function apply(d) {
      if (d.version) all('version', function (e) { e.textContent = d.version; });
      [['commits', d.commits], ['releases', d.releases], ['contributors', d.contributors]].forEach(function (x) {
        var v = num(x[1]); if (v) all(x[0], function (e) { e.textContent = v; });
      });
      if (d.pushed) all('pushed', function (e) { e.textContent = day(d.pushed); });
      if (d.days && d.days.length) all('since', function (e) {
        var n = d.days.reduce(function (a, x) { return a + x[1]; }, 0);
        var since = day(d.days[0][0] + 'T12:00:00Z');
        e.textContent = root.lang === 'id' ? n + ' commit sejak ' + since : n + (n === 1 ? ' commit' : ' commits') + ' since ' + since;
      });
      if (d.langs && d.langs.length) {
        all('langbar', function (e) {
          e.textContent = '';
          d.langs.forEach(function (l, i) { var s = el('i'); s.style.width = l[1] + '%'; s.style.setProperty('--c', COLORS[i % COLORS.length]); e.appendChild(s); });
          e.hidden = false;
        });
        all('langs', function (e) {
          e.textContent = '';
          d.langs.forEach(function (l, i) {
            var s = el('span'), dot = el('i'); dot.style.setProperty('--c', COLORS[i % COLORS.length]);
            s.appendChild(dot); s.appendChild(document.createTextNode(l[0] + ' ')); s.appendChild(el('small', null, l[1].toFixed(1) + '%'));
            e.appendChild(s);
          });
          e.hidden = false;
        });
        all('langs-mini', function (e) {
          e.textContent = '';
          d.langs.slice(0, 2).forEach(function (l, i) {
            var s = el('span'), dot = el('i'); dot.style.setProperty('--c', COLORS[i]);
            s.appendChild(dot); s.appendChild(document.createTextNode(l[0])); e.appendChild(s);
          });
        });
      }
    }
    function done(d) {
      data = UI.gh = d; apply(d);
      document.dispatchEvent(new CustomEvent('amnesia:gh', { detail: d }));
    }
    document.addEventListener('amnesia:lang', function () { if (data) apply(data); });

    var c = null;
    try { c = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) {}
    if (c && Date.now() - c.t < 3600e3) { done(c); return; }
    if (!window.fetch) return;
    var opt = { credentials: 'omit', referrerPolicy: 'no-referrer', headers: { Accept: 'application/vnd.github+json' } };
    function get(path) {
      return fetch(repo + path, opt).then(function (r) {
        if (!r.ok) return { json: null, link: '' };
        return r.json().then(function (j) { return { json: j, link: r.headers.get('Link') || '' }; });
      }).catch(function () { return { json: null, link: '' }; });
    }
    // a list asked for 1 per page: the last page number in the Link header is the total
    function count(res) {
      if (!res.json) return undefined;
      var m = /[?&]page=(\d+)>;\s*rel="last"/.exec(res.link);
      return m ? +m[1] : res.json.length;
    }
    Promise.all([
      get(''), get('/releases/latest'), get('/languages'), get('/commits?per_page=100'),
      get('/commits?per_page=1'), get('/releases?per_page=1'), get('/contributors?per_page=1&anon=1')
    ]).then(function (r) {
      var d = { t: Date.now() };
      if (r[0].json) d.pushed = r[0].json.pushed_at;
      if (r[1].json && r[1].json.tag_name) d.version = (r[1].json.tag_name[0] === 'v' ? '' : 'v') + r[1].json.tag_name;
      if (r[2].json) {
        var tot = 0, k;
        for (k in r[2].json) tot += r[2].json[k];
        d.langs = Object.keys(r[2].json).map(function (k) { return [k, r[2].json[k] * 100 / (tot || 1)]; })
          .filter(function (l) { return l[1] >= 0.5; });
      }
      if (r[3].json && r[3].json.length) {
        // commits per day, from the oldest commit in the list (max 84 days back) to today
        var per = {};
        r[3].json.forEach(function (x) { var t = ((x.commit || {}).author || {}).date; if (t) per[t.slice(0, 10)] = (per[t.slice(0, 10)] || 0) + 1; });
        var keys = Object.keys(per).sort(), end = new Date(), start = new Date(keys[0] + 'T00:00:00Z');
        if ((end - start) / 864e5 > 83) start = new Date(end - 83 * 864e5);
        d.days = [];
        for (var t = new Date(start.toISOString().slice(0, 10) + 'T00:00:00Z'); t <= end; t = new Date(+t + 864e5)) {
          var ks = t.toISOString().slice(0, 10); d.days.push([ks, per[ks] || 0]);
        }
      }
      d.commits = count(r[4]); d.releases = count(r[5]); d.contributors = count(r[6]);
      if (!r[0].json && !r[1].json) return; // GitHub didn't answer: keep the built-in values
      done(d);
      try { localStorage.setItem(KEY, JSON.stringify(d)); } catch (e) {}
    });
  })();

  // ---------- bento: a light that follows the cursor ----------
  document.querySelectorAll('.cell, .feats.bento > div').forEach(function (el) {
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      el.style.setProperty('--mx', (e.clientX - r.left) + 'px');
      el.style.setProperty('--my', (e.clientY - r.top) + 'px');
    });
  });

  // ---------- arrows + dots for the slide scenes ----------
  // pager(el, n, go): builds the dots, wires the arrows, returns set(i).
  UI.pager = function (el, n, go) {
    if (!el) return { set: function () {} };
    if (el._pg) UI.keyed.splice(UI.keyed.indexOf(el._pg), 1);
    var dots = el.querySelector('.pg-dots'), prev = el.querySelector('.pg-prev'), next = el.querySelector('.pg-next');
    var num = dots.classList.contains('num'), cur = 0, btns = [];
    dots.innerHTML = '';
    for (var i = 0; i < n; i++) {
      var li = document.createElement('li'), b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('aria-label', (root.lang === 'id' ? 'Langkah ' : 'Step ') + (i + 1));
      if (num) b.textContent = i + 1;
      b.addEventListener('click', go.bind(null, i));
      li.appendChild(b); dots.appendChild(li); btns.push(b);
    }
    prev.onclick = function () { go(Math.max(0, cur - 1)); };
    next.onclick = function () { go(Math.min(n - 1, cur + 1)); };
    el.hidden = false;
    function set(i) {
      cur = i;
      btns.forEach(function (b, j) { b.classList.toggle('on', j === i); b.classList.toggle('done', j < i); b.setAttribute('aria-current', j === i ? 'step' : 'false'); });
      prev.disabled = i <= 0; next.disabled = i >= n - 1;
    }
    set(0);
    var api = { set: set, prev: function () { prev.onclick(); }, next: function () { next.onclick(); }, el: el };
    UI.keyed.push(api);
    el._pg = api;
    return api;
  };
  // keyboard ← → moves the slide scene that fills the middle of the screen
  UI.keyed = [];
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
    if (e.altKey || e.ctrlKey || e.metaKey || /input|textarea|select/i.test((document.activeElement || {}).tagName || '')) return;
    var mid = innerHeight / 2;
    for (var i = 0; i < UI.keyed.length; i++) {
      var p = UI.keyed[i], sec = p.el.closest('section');
      if (p.el.hidden || !sec) continue;
      var r = sec.getBoundingClientRect();
      if (r.top < mid && r.bottom > mid && getComputedStyle(p.el).display !== 'none') {
        e.preventDefault();
        e.key === 'ArrowLeft' ? p.prev() : p.next();
        return;
      }
    }
  });
  // smooth scroll to a page position (Lenis when it runs)
  UI.scrollTo = function (y) {
    if (UI.lenis) UI.lenis.scrollTo(y, { duration: 1.1 });
    else window.scrollTo({ top: y, behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  };

  // ---------- motion ----------
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var motion = !reduced && window.gsap && window.ScrollTrigger;

  if (motion) {
    gsap.registerPlugin(ScrollTrigger);
    if (window.SplitText) gsap.registerPlugin(SplitText);
    root.classList.add('motion');

    // smooth scroll, kept in sync with ScrollTrigger
    if (window.Lenis) {
      var lenis = UI.lenis = new Lenis({ duration: 1.1, smoothWheel: true });
      lenis.on('scroll', ScrollTrigger.update);
      gsap.ticker.add(function (t) { lenis.raf(t * 1000); });
      gsap.ticker.lagSmoothing(0);
      // in-page links go through Lenis so they glide too
      document.querySelectorAll('a[href^="#"]').forEach(function (a) {
        a.addEventListener('click', function (e) {
          var id = a.getAttribute('href');
          var el = id.length > 1 && document.querySelector(id);
          if (!el) return;
          e.preventDefault();
          lenis.scrollTo(el, { offset: id === '#top' ? 0 : -72 });
          if (id === '#main') el.focus && el.focus();
        });
      });
    }

    // navbar fades in
    gsap.from(nav, { y: -20, opacity: 0, duration: .8, ease: 'power3.out', delay: .1 });

    var mm = gsap.matchMedia();
    ['hero', 'desk', 'puzzle', 'story'].forEach(function (k) {
      if (Scenes[k]) Scenes[k].init(mm, UI.lenis);
    });
    UI.mm = mm;
  }

  // the tutorial player works with or without motion
  if (Scenes.tutorial) Scenes.tutorial.setup({ motion: !!motion, mm: UI.mm, gsap: !reduced && window.gsap });

  if (motion) {
    // reveal anything marked .head / .card that a scene didn't take
    gsap.utils.toArray('.ref .head, .stage .head, .card').forEach(function (el) {
      if (el.dataset.scene) return;
      gsap.from(el, {
        y: 28, opacity: 0, duration: .8, ease: 'power3.out',
        scrollTrigger: { trigger: el, start: 'top 88%', once: true }
      });
    });
    document.addEventListener('amnesia:lang', function () {
      requestAnimationFrame(function () { ScrollTrigger.refresh(); });
    });
    window.addEventListener('load', function () { ScrollTrigger.refresh(); });
  }
})();
