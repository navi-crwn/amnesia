/* Hero: headline rises in word by word, the shield floats, and on scroll
   the word "everything." breaks into particles that drift away. */
(function () {
  'use strict';
  var S = window.AmnesiaScenes = window.AmnesiaScenes || {};

  S.hero = {
    init: function (mm) {
      var hero = document.querySelector('.hero');
      if (!hero) return;
      // ---- intro ----
      var lines = [], after = [];
      if (window.SplitText) {
        hero.querySelectorAll('h1 .split').forEach(function (el) {
          var w = new SplitText(el, { type: 'words', mask: 'words' }).words;
          (el.classList.contains('after') ? after : lines).push.apply(el.classList.contains('after') ? after : lines, w);
        });
      }
      var tl = gsap.timeline({ defaults: { ease: 'power3.out' }, delay: .15 });
      if (lines.length) tl.from(lines, { yPercent: 110, duration: 1, stagger: .06 });
      tl.from(hero.querySelectorAll('h1 em.word'), { y: 40, opacity: 0, duration: 1.1 }, lines.length ? '-=.7' : 0);
      if (after.length) tl.from(after, { yPercent: 110, duration: .9, stagger: .04 }, '-=.8');
      tl.from(hero.querySelectorAll('.lead, .cta, .term, .meta, .warnline'), { y: 20, opacity: 0, duration: .8, stagger: .08 }, '-=.6')
        .from('.shield', { scale: .85, opacity: 0, duration: 1.4 }, .2);

      // ---- float ----
      gsap.to('.shield img', { y: -14, duration: 3, ease: 'sine.inOut', yoyo: true, repeat: -1 });

      // ---- particles ----
      mm.add({ desk: '(min-width: 901px)', mob: '(max-width: 900px)' }, function (ctx) {
        var max = ctx.conditions.desk ? 1500 : 500;
        return particles(hero, max);
      });
    }
  };

  function visibleWord(hero) {
    var list = hero.querySelectorAll('h1 em.word');
    for (var i = 0; i < list.length; i++) if (list[i].offsetParent) return list[i];
    return null;
  }

  function particles(hero, max) {
    var canvas = document.createElement('canvas');
    canvas.id = 'hero-particles';
    canvas.setAttribute('aria-hidden', 'true');
    hero.appendChild(canvas);
    var ctx2 = canvas.getContext('2d');
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var pts = [], word = null, box = null, pad = 160, last = -1;

    function build() {
      word = visibleWord(hero);
      if (!word) return;
      var r = word.getBoundingClientRect(), hr = hero.getBoundingClientRect();
      box = { x: r.left - hr.left - pad, y: r.top - hr.top - pad, w: r.width + pad * 2, h: r.height + pad * 2 };
      canvas.style.left = box.x + 'px';
      canvas.style.top = box.y + 'px';
      canvas.style.width = box.w + 'px';
      canvas.style.height = box.h + 'px';
      canvas.width = Math.round(box.w * dpr);
      canvas.height = Math.round(box.h * dpr);

      // draw the word offscreen with the same font, then sample its pixels
      var cs = getComputedStyle(word);
      var off = document.createElement('canvas');
      off.width = Math.ceil(r.width + 24); off.height = Math.ceil(r.height);
      var o = off.getContext('2d');
      o.font = cs.fontStyle + ' ' + cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
      o.textBaseline = 'middle';
      o.fillStyle = '#fff';
      o.fillText(word.textContent, 0, r.height / 2);
      var data = o.getImageData(0, 0, off.width, off.height).data;
      var area = off.width * off.height;
      var step = Math.max(2, Math.ceil(Math.sqrt(area / (max * 3.5))));
      pts = [];
      for (var y = 0; y < off.height; y += step) {
        for (var x = 0; x < off.width; x += step) {
          if (data[(y * off.width + x) * 4 + 3] > 128) {
            var t = x / off.width;
            pts.push({
              x: x + pad, y: y + pad,
              dx: (Math.random() - .3) * 260, dy: -Math.random() * 220 - 40,
              c: t < .5 ? mix([34, 211, 238], [99, 102, 241], t * 2) : mix([99, 102, 241], [236, 72, 153], (t - .5) * 2),
              s: Math.random() * 1.2 + .8
            });
          }
        }
      }
      if (pts.length > max) pts = pts.filter(function (_, i) { return i % Math.ceil(pts.length / max) === 0; });
      last = -1;
    }

    function mix(a, b, t) {
      return 'rgb(' + Math.round(a[0] + (b[0] - a[0]) * t) + ',' + Math.round(a[1] + (b[1] - a[1]) * t) + ',' + Math.round(a[2] + (b[2] - a[2]) * t) + ')';
    }

    function draw(p) {
      if (!word || p === last) return;
      last = p;
      ctx2.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx2.clearRect(0, 0, box.w, box.h);
      word.style.opacity = p > 0.02 ? 0 : 1;
      if (p <= 0.02) return;
      var e = p * p * (3 - 2 * p);
      ctx2.globalAlpha = Math.max(0, 1 - p * 1.15);
      for (var i = 0; i < pts.length; i++) {
        var q = pts[i];
        ctx2.fillStyle = q.c;
        ctx2.fillRect(q.x + q.dx * e, q.y + q.dy * e, q.s, q.s);
      }
    }

    build();
    var st = ScrollTrigger.create({
      trigger: hero, start: 'top top', end: '60% top', scrub: true,
      onUpdate: function (self) { draw(+self.progress.toFixed(3)); },
      onRefresh: function (self) { build(); draw(self.progress); }
    });
    function onLang() { hero.querySelectorAll('h1 em.word').forEach(function (w) { w.style.opacity = 1; }); requestAnimationFrame(function () { build(); draw(st.progress); }); }
    document.addEventListener('amnesia:lang', onLang);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(function () { build(); last = -1; draw(st.progress); });

    return function () {
      st.kill();
      document.removeEventListener('amnesia:lang', onLang);
      canvas.remove();
      hero.querySelectorAll('h1 em.word').forEach(function (w) { w.style.opacity = ''; });
    };
  }
})();
