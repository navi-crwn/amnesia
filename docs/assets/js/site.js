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

  // ---------- GitHub numbers (stars, forks, latest version) ----------
  // Read straight from the public GitHub API by the visitor's browser. No cookies,
  // no referrer, cached for an hour. If it fails, the built-in values stay.
  (function () {
    var KEY = 'gh-repo', repo = 'https://api.github.com/repos/navi-crwn/amnesia-mac';
    function fmt(n) { return n >= 1000 ? (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, '') + 'k' : String(n); }
    function apply(d) {
      if (typeof d.stars === 'number') document.querySelectorAll('[data-gh=stars]').forEach(function (e) { e.textContent = fmt(d.stars); });
      if (typeof d.forks === 'number') document.querySelectorAll('[data-gh=forks]').forEach(function (e) { e.textContent = fmt(d.forks); });
      if (d.version) document.querySelectorAll('[data-gh=version]').forEach(function (e) { e.textContent = d.version; });
    }
    var c = null;
    try { c = JSON.parse(sessionStorage.getItem(KEY) || 'null'); } catch (e) {}
    if (c && Date.now() - c.t < 3600e3) { apply(c); return; }
    if (!window.fetch) return;
    var opt = { credentials: 'omit', referrerPolicy: 'no-referrer', headers: { Accept: 'application/vnd.github+json' } };
    Promise.all([
      fetch(repo, opt).then(function (r) { return r.ok ? r.json() : {}; }),
      fetch(repo + '/releases/latest', opt).then(function (r) { return r.ok ? r.json() : {}; })
    ]).then(function (res) {
      var d = { t: Date.now(), stars: res[0].stargazers_count, forks: res[0].forks_count, version: res[1].tag_name };
      if (d.version && d.version[0] !== 'v') d.version = 'v' + d.version;
      apply(d);
      try { sessionStorage.setItem(KEY, JSON.stringify(d)); } catch (e) {}
    }).catch(function () {});
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
