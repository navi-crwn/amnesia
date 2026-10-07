/* 10: the tutorial player. A drawn Amnesia window plays each step like a
   screen recording: a cursor moves, clicks, types, and pages and popups
   change. The script for each page lives in the HTML:
     data-a="N"        order of the action on that page
     data-do="auto"    happens without the cursor
     data-type="…"     text typed into the element's .val
     data-fill=".bar"  a progress bar fills first
     data-on / data-off  selectors (or "self") that get / lose the class "on"
     data-wait="s"     pause afterwards
   Desktop with motion: pinned, scrolling moves through the steps.
   Otherwise: arrows, numbered dots and ← → switch steps.
   Reduced motion or no GSAP: every page shows its finished state, no cursor. */
(function () {
  'use strict';
  var S = window.AmnesiaScenes = window.AmnesiaScenes || {};
  var W = 560; // design width of the drawn window

  S.tutorial = {
    setup: function (o) {
      var sec = document.getElementById('tutorial');
      if (!sec) return;
      var UI = window.AmnesiaUI;
      var view = sec.querySelector('.tw-view'), body = sec.querySelector('.tw-body');
      var pages = [].slice.call(sec.querySelectorAll('.tp'));
      var texts = [].slice.call(sec.querySelectorAll('.t-step'));
      var cur = sec.querySelector('.tw-cur'), rip = sec.querySelector('.tw-rip');
      var G = o.gsap || null, n = pages.length, idx = -1, tls = [], visible = false, play = null;

      // ---- scale the 560px drawing to the card ----
      function fit() { view.style.setProperty('--tws', Math.min(view.clientWidth / W, 1.3).toFixed(4)); }
      fit();
      if (window.ResizeObserver) new ResizeObserver(fit).observe(view);

      // ---- remember each page's starting state ----
      pages.forEach(function (p) {
        p._init = [].map.call(p.querySelectorAll('*'), function (e) { return [e, e.getAttribute('class')]; });
        p._acts = [].slice.call(p.querySelectorAll('[data-a]')).sort(function (a, b) { return a.dataset.a - b.dataset.a; });
      });
      function reset(p) {
        p._init.forEach(function (x) { if (x[1] === null) x[0].removeAttribute('class'); else x[0].setAttribute('class', x[1]); });
        p.querySelectorAll('.val').forEach(function (v) { v.textContent = ''; });
        p.querySelectorAll('.bar b').forEach(function (b) { b.style.width = ''; });
      }
      function pick(p, el, list) {
        var out = [];
        (list || '').split(',').forEach(function (q) {
          q = q.trim(); if (!q) return;
          if (q === 'self') out.push(el); else out.push.apply(out, p.querySelectorAll(q));
        });
        return out;
      }
      function effects(p, el) {
        pick(p, el, el.dataset.off).forEach(function (e) { e.classList.remove('on'); });
        pick(p, el, el.dataset.on).forEach(function (e) { e.classList.add('on'); });
      }
      // finished state, for reduced motion and no-GSAP
      function finish(p) {
        reset(p);
        p._acts.forEach(function (a) {
          if (a.dataset.type) a.querySelector('.val').textContent = a.dataset.type;
          if (a.dataset.fill) p.querySelector(a.dataset.fill + ' b').style.width = '100%';
          effects(p, a);
        });
      }

      // ---- the recording for one page ----
      function pt(el) {
        var r = el.getBoundingClientRect(), b = body.getBoundingClientRect(), s = b.width / W || 1;
        return { x: (r.left - b.left + Math.min(r.width * .6, r.width - 8)) / s, y: (r.top - b.top + r.height * .6) / s };
      }
      function press(p, el) {
        el.classList.add('pressed');
        setTimeout(function () { el.classList.remove('pressed'); }, 160);
        if (el.dataset.type) { p.querySelectorAll('.ui-field.on').forEach(function (f) { f.classList.remove('on'); }); el.classList.add('on'); }
      }
      function build(i) {
        var p = pages[i];
        var tl = G.timeline({ paused: true, repeat: -1, repeatDelay: 1.6, onRepeat: function () { reset(p); } });
        tl.set(cur, { x: 470, y: 380, opacity: 0 }).set(rip, { opacity: 0 })
          .to(cur, { opacity: 1, duration: .3 });
        p._acts.forEach(function (a) {
          if (a.dataset.do !== 'auto') {
            var to = null;
            tl.to(cur, { x: function () { return (to = pt(a)).x - 4; }, y: function () { return to.y - 3; }, duration: .75, ease: 'power2.inOut' }, '+=.35')
              .call(press, [p, a])
              .fromTo(rip, { x: function () { return to.x; }, y: function () { return to.y; }, scale: .3, opacity: .9 }, { scale: 1.5, opacity: 0, duration: .45, ease: 'power1.out', immediateRender: false }, '<')
              .to({}, { duration: .2 });
          }
          if (a.dataset.type) {
            var val = a.querySelector('.val'), full = a.dataset.type, o2 = { n: 0 };
            tl.to(o2, { n: full.length, duration: full.length * .055, ease: 'none', onUpdate: function () { val.textContent = full.slice(0, Math.round(o2.n)); } });
          }
          if (a.dataset.fill) {
            tl.fromTo(p.querySelector(a.dataset.fill + ' b'), { width: '0%' }, { width: '100%', duration: 1.3, ease: 'power1.inOut', immediateRender: false });
          }
          tl.call(effects, [p, a]);
          if (a.dataset.wait) tl.to({}, { duration: +a.dataset.wait });
        });
        tl.to({}, { duration: 1.8 }).to(cur, { opacity: 0, duration: .3 });
        return tl;
      }

      // ---- switch steps ----
      var pager = UI.pager(sec.querySelector('[data-pager=tut]'), n, function (i) { go(i); });
      function show(i) {
        if (i === idx) return;
        if (play) { play.pause(); }
        if (idx >= 0 && G) reset(pages[idx]);
        idx = i;
        pages.forEach(function (p, j) { p.classList.toggle('cur', j === i); });
        texts.forEach(function (t, j) { t.classList.toggle('cur', j === i); });
        pager.set(i);
        if (G) {
          reset(pages[i]);
          play = tls[i] || (tls[i] = build(i));
          play.restart();
          if (!visible) play.pause();
        } else {
          finish(pages[i]);
        }
      }
      var go = function (i) { show(i); };
      show(0);

      // only play while the window is on screen
      if (window.IntersectionObserver) {
        new IntersectionObserver(function (e) {
          visible = e[0].isIntersecting;
          if (play) visible ? play.play() : play.pause();
        }, { threshold: .25 }).observe(view);
      } else visible = true;

      // ---- desktop with motion: pinned, scroll drives the steps ----
      if (o.motion && o.mm) {
        o.mm.add('(min-width: 901px)', function () {
          var st = ScrollTrigger.create({
            trigger: sec.querySelector('.tutbox'), start: 'top top', end: '+=' + (n * 45) + '%',
            pin: true, anticipatePin: 1,
            onUpdate: function (self) { show(Math.min(n - 1, Math.floor(self.progress * n * .999))); }
          });
          go = function (i) { UI.scrollTo(st.start + ((i + .5) / n) * (st.end - st.start)); };
          return function () { go = function (i) { show(i); }; };
        });
      }
      // the language switch changes text widths: let the cursor re-aim
      document.addEventListener('amnesia:lang', function () {
        tls.forEach(function (t) { if (t) t.kill(); });
        tls = []; var k = idx; idx = -1; show(k);
      });
    }
  };
})();
