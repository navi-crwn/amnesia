/* 03 to 09: smaller scenes.
   stays (strike + fade), vault (apps fly in, lock closes, password types),
   daily (line draws), backup (lines draw), privacy (pills pop),
   glossary (tiny grids), install (command types itself). */
(function () {
  'use strict';
  var S = window.AmnesiaScenes = window.AmnesiaScenes || {};

  function once(el, start) { return { trigger: el, start: start || 'top 75%', once: true }; }

  // types the text of `el` from empty, keeping the full text for copy
  function typeIn(el, opts) {
    var full = el.textContent;
    el.dataset.full = full;
    var o = { n: 0 };
    el.textContent = '';
    return gsap.to(o, Object.assign({
      n: full.length, duration: full.length * .035, ease: 'none',
      onUpdate: function () { el.textContent = full.slice(0, Math.round(o.n)); }
    }, opts || {}));
  }

  S.story = {
    init: function (mm) {
      // ---- 03 stays ----
      var stays = document.getElementById('stays');
      if (stays) {
        stays.querySelector('.head').dataset.scene = 1;
        var tl3 = gsap.timeline({ scrollTrigger: once(stays.querySelector('.ledger'), 'top 70%') });
        tl3.from(stays.querySelectorAll('.col'), { y: 40, opacity: 0, duration: .7, stagger: .12, ease: 'power3.out' })
          .to(stays.querySelectorAll('.col.gone .strike'), { scaleX: 1, duration: .45, stagger: .15, ease: 'power2.inOut' }, '+=.1')
          .to(stays.querySelectorAll('.col.gone li'), { opacity: .45, duration: .4, stagger: .15 }, '<.2')
          .from(stays.querySelectorAll('.col.safe li'), { x: -12, opacity: 0, duration: .5, stagger: .1, ease: 'power3.out' }, '<');
        gsap.from(stays.querySelector('.head'), { y: 30, opacity: 0, duration: .8, ease: 'power3.out', scrollTrigger: once(stays) });
      }

      // ---- 04 vault ----
      var vault = document.getElementById('vault');
      if (vault) {
        vault.querySelector('.head').dataset.scene = 1;
        var apps = vault.querySelectorAll('.v-app');
        var dots = vault.querySelector('.pw .dots');
        var tl4 = gsap.timeline({ scrollTrigger: once(vault, 'top 65%') });
        tl4.from(vault.querySelector('.v-shield'), { scale: .8, opacity: 0, transformOrigin: '50% 50%', duration: .8, ease: 'power3.out' })
          .from(vault.querySelector('.pw'), { y: 16, opacity: 0, duration: .4 }, '-=.3')
          .add(typeIn(dots, {}))
          .to(vault.querySelector('.v-shackle'), { y: 8, duration: .25, ease: 'back.in(3)' })
          .from(apps, {
            x: function (i) { return Math.cos(i / apps.length * Math.PI * 2 - Math.PI / 2) * 140; },
            y: function (i) { return Math.sin(i / apps.length * Math.PI * 2 - Math.PI / 2) * 140; },
            opacity: 0, scale: .4, transformOrigin: '50% 50%', duration: .9, ease: 'power3.out', stagger: .06
          }, '-=.05');
        gsap.from(vault.querySelectorAll('.head > *'), { y: 24, opacity: 0, duration: .7, stagger: .08, ease: 'power3.out', scrollTrigger: once(vault) });
      }

      // ---- 05 daily ----
      var daily = document.getElementById('how');
      if (daily) {
        daily.querySelector('.head').dataset.scene = 1;
        var line = daily.querySelector('.daily-line .draw');
        gsap.set(line, { attr: { 'stroke-dasharray': 1000, 'stroke-dashoffset': 1000 } });
        gsap.to(line, { attr: { 'stroke-dashoffset': 0 }, ease: 'none', scrollTrigger: { trigger: daily.querySelector('.daily-track'), start: 'top 80%', end: 'bottom 55%', scrub: .5 } });
        gsap.from(daily.querySelectorAll('.dstep'), { y: 30, opacity: 0, duration: .7, stagger: .15, ease: 'power3.out', scrollTrigger: once(daily.querySelector('.daily-track'), 'top 80%') });
        gsap.from(daily.querySelector('.head'), { y: 30, opacity: 0, duration: .8, ease: 'power3.out', scrollTrigger: once(daily) });
        gsap.from(daily.querySelector('.pausenote'), { y: 20, opacity: 0, duration: .7, scrollTrigger: once(daily.querySelector('.pausenote'), 'top 90%') });
      }

      // ---- 06 backup ----
      var backup = document.getElementById('backup');
      if (backup) {
        backup.querySelector('.head').dataset.scene = 1;
        var paths = backup.querySelectorAll('.links path');
        paths.forEach(function (p) { var l = p.getTotalLength(); gsap.set(p, { attr: { 'stroke-dasharray': l, 'stroke-dashoffset': l } }); });
        var tl6 = gsap.timeline({ scrollTrigger: once(backup.querySelector('.netviz'), 'top 70%') });
        tl6.from(backup.querySelector('.core'), { scale: .6, opacity: 0, transformOrigin: '50% 50%', duration: .6, ease: 'back.out(1.8)' })
          .to(paths, { attr: { 'stroke-dashoffset': 0 }, duration: .9, stagger: .07, ease: 'power2.inOut' })
          .from(backup.querySelectorAll('.dest'), { opacity: 0, scale: .8, transformOrigin: '50% 50%', duration: .4, stagger: .07 }, '-=.8')
          .from(backup.querySelector('.pkts'), { opacity: 0, duration: .4 });
        gsap.from(backup.querySelectorAll('.head > *'), { y: 24, opacity: 0, duration: .7, stagger: .08, ease: 'power3.out', scrollTrigger: once(backup) });
      }

      // ---- 07 privacy ----
      var priv = document.getElementById('private');
      if (priv) {
        gsap.from(priv.querySelectorAll('.pill'), { y: 20, opacity: 0, scale: .9, duration: .5, stagger: .06, ease: 'back.out(1.7)', scrollTrigger: once(priv.querySelector('.pills'), 'top 85%') });
        priv.querySelectorAll('.feats > div').forEach(function (el) { el.dataset.scene = 1; });
        gsap.from(priv.querySelectorAll('.feats > div'), { opacity: 0, y: 20, duration: .6, stagger: .05, ease: 'power3.out', scrollTrigger: once(priv.querySelector('.feats'), 'top 80%') });
      }

      // ---- 09 glossary: three tiny grids show the three kinds of forgetting ----
      document.querySelectorAll('.mini').forEach(function (m) {
        var sq = m.querySelectorAll('i'), kind = m.dataset.kind, t = gsap.timeline({ repeat: -1, repeatDelay: 1.2, paused: true });
        if (kind === 'sel') {
          var gone = [].filter.call(sq, function (_, i) { return i % 4 !== 0; });
          t.to(gone, { scale: 0, opacity: 0, duration: .4, stagger: .06, ease: 'power2.in' }).to(gone, { scale: 1, opacity: 1, duration: .4, stagger: .04, delay: 1 });
        } else if (kind === 'glob') {
          t.to(sq, { backgroundColor: '#ef4444', duration: .3, stagger: .03 }).to(sq, { scale: 0, opacity: 0, duration: .35, stagger: .03 }, '+=.3').to(sq, { scale: 1, opacity: 1, backgroundColor: 'rgba(239,68,68,.35)', duration: .3, delay: 1 });
        } else {
          t.from(sq, { x: function () { return gsap.utils.random(-40, 40); }, y: function () { return gsap.utils.random(-30, 30); }, opacity: 0, duration: .6, stagger: .06, ease: 'power3.out' }).to({}, { duration: 1 });
        }
        ScrollTrigger.create({ trigger: m, start: 'top 90%', end: 'bottom 10%', onToggle: function (self) { self.isActive ? t.play() : t.pause(); } });
      });

      // ---- 10 install: the command types itself ----
      document.querySelectorAll('.term.type code').forEach(function (c) {
        var tw = typeIn(c, { paused: true });
        ScrollTrigger.create({ trigger: c, start: 'top 85%', once: true, onEnter: function () { tw.play(); } });
      });
    }
  };
})();
