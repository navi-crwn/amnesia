/* 03 to 11: smaller scenes.
   stays (list first, then the strike follows the scroll), vault (apps fly in,
   lock closes, password types), daily (line draws), backup (lines draw),
   privacy (pills pop), popups (bento cards rise), install (command types
   itself, output prints, the app drags into Applications), FAQ cards. */
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
        // the list arrives first...
        gsap.from(stays.querySelectorAll('.col'), { y: 40, opacity: 0, duration: .7, stagger: .12, ease: 'power3.out', scrollTrigger: once(stays.querySelector('.ledger'), 'top 85%') });
        gsap.from(stays.querySelectorAll('.col.safe li'), { x: -12, opacity: 0, duration: .5, stagger: .1, ease: 'power3.out', scrollTrigger: once(stays.querySelector('.col.safe'), 'top 75%') });
        // ...and the strike-through only runs once the "wiped" list sits well inside the screen,
        // line by line as you keep scrolling
        var gone = stays.querySelector('.col.gone');
        gsap.timeline({ scrollTrigger: { trigger: gone, start: 'top 52%', end: 'bottom 48%', scrub: .6 } })
          .to(gone.querySelectorAll('.strike'), { scaleX: 1, duration: .5, stagger: .35, ease: 'power2.inOut' })
          .to(gone.querySelectorAll('li'), { opacity: .45, duration: .4, stagger: .35 }, .25);
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

      // ---- 08 popups: bento cards rise, then their colored boxes slide in ----
      var pops = document.querySelector('.bento.pops');
      if (pops) {
        pops.querySelectorAll('.cell').forEach(function (c, i) {
          c.dataset.scene = 1;
          var t = gsap.timeline({ scrollTrigger: once(c, 'top 88%') });
          t.from(c, { y: 40, opacity: 0, duration: .7, ease: 'power3.out', delay: (i % 3) * .08 })
            .from(c.querySelectorAll('.ps, .legend li, .pop-chk, .pop-btns'), { x: -14, opacity: 0, duration: .45, stagger: .08, ease: 'power2.out' }, '-=.35');
        });
      }

      // ---- 11 FAQ + install cards ----
      gsap.utils.toArray('.faq .cell, .installs .cell').forEach(function (c, i) {
        c.dataset.scene = 1;
        gsap.from(c, { y: 34, opacity: 0, duration: .7, ease: 'power3.out', delay: (i % 2) * .08, scrollTrigger: once(c, 'top 90%') });
      });

      // ---- 09 install: the command types itself, then brew prints its output ----
      document.querySelectorAll('.term.type code').forEach(function (c) {
        var out = c.closest('.shell') && c.closest('.shell').querySelectorAll('.sh-out span');
        var t = gsap.timeline({ paused: true }).add(typeIn(c, {}));
        if (out && out.length) {
          gsap.set(out, { opacity: 0 });
          t.to(out, { opacity: 1, duration: .05, stagger: .45, ease: 'none' }, '+=.3');
        }
        ScrollTrigger.create({ trigger: c, start: 'top 85%', once: true, onEnter: function () { t.play(); } });
      });
      gsap.from('.badges .bdg', { y: 14, opacity: 0, duration: .5, stagger: .07, ease: 'back.out(1.6)', scrollTrigger: once('.badges', 'top 90%') });
      // the app icon drags itself into Applications, again and again while visible
      var dmg = document.querySelector('.i-dmg .dmgwin');
      if (dmg) {
        var ghost = dmg.querySelector('.dm-ghost'), app = dmg.querySelector('.dm-app img'), dst = dmg.querySelector('.dm-dst svg');
        var drag = gsap.timeline({ repeat: -1, repeatDelay: 1, paused: true });
        drag.call(function () {
          var w = dmg.getBoundingClientRect(), a = app.getBoundingClientRect(), d = dst.getBoundingClientRect();
          gsap.set(ghost, { left: a.left - w.left, top: a.top - w.top, x: 0, y: 0, scale: 1, opacity: 0 });
          ghost._dx = d.left - a.left; ghost._dy = d.top - a.top;
        })
          .to(ghost, { opacity: .85, duration: .25 })
          .to(ghost, { x: function () { return ghost._dx; }, y: function () { return ghost._dy; }, duration: 1.1, ease: 'power2.inOut' })
          .to(ghost, { scale: .4, opacity: 0, duration: .3 })
          .fromTo(dst, { scale: 1 }, { scale: 1.15, duration: .15, yoyo: true, repeat: 1, transformOrigin: '50% 50%' }, '<');
        ScrollTrigger.create({ trigger: dmg, start: 'top 95%', end: 'bottom 5%', onToggle: function (self) { self.isActive ? drag.play() : drag.pause(); } });
      }
    }
  };
})();
