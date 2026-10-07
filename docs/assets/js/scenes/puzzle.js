/* 08: the Amnesia main window as a puzzle.
   Wide screens: the section is pinned. The pieces fly in and lock together,
   then one piece at a time is lifted out while the rest break apart, a cursor
   clicks it, and its explanation shows on the left. At the end everything
   snaps back together. Arrows, dots and ← → jump between pieces.
   Phones: no pin. Each explanation gets a copy of its piece on top. */
(function () {
  'use strict';
  var S = window.AmnesiaScenes = window.AmnesiaScenes || {};

  S.puzzle = {
    init: function (mm) {
      var sec = document.getElementById('tour');
      if (!sec) return;
      var box = sec.querySelector('.puzzle');
      var stage = sec.querySelector('.pz-stage');
      var win = sec.querySelector('.appwin');
      var pieces = gsap.utils.toArray(stage.querySelectorAll('.pc'));
      var steps = gsap.utils.toArray(sec.querySelectorAll('.pz-step'));
      var drop = sec.querySelector('.mb-drop');
      var cur = stage.querySelector('.pz-cur'), rip = stage.querySelector('.pz-rip');
      var UI = window.AmnesiaUI;
      steps.forEach(function (el) { el.dataset.scene = 1; });

      function byKey(k) { return stage.querySelector('.pc[data-p="' + k + '"]'); }

      // direction each piece moves when the window "breaks": away from the window centre
      function burst(el, i) {
        var r = el.getBoundingClientRect(), w = win.getBoundingClientRect();
        var dx = (r.left + r.width / 2) - (w.left + w.width / 2);
        var dy = (r.top + r.height / 2) - (w.top + w.height / 2);
        var len = Math.hypot(dx, dy) || 1;
        return { x: dx / len * 60, y: dy / len * 52, r: (i % 2 ? 1 : -1) * 4 };
      }
      // where the cursor points for a piece, relative to the stage
      function aim(el) {
        var r = el.getBoundingClientRect(), s = stage.getBoundingClientRect();
        var z = stage.offsetWidth / (s.width || 1); // the stage may be zoomed on short screens
        var k = el.dataset.p;
        var fx = k === 'menu' ? .9 : k === 'settings' ? .5 : .62;
        return { x: (r.left - s.left + r.width * fx) * z, y: (r.top - s.top + r.height * .62) * z };
      }

      mm.add('(min-width: 901px)', function () {
        var dirs = pieces.map(burst);
        var aims = {};
        pieces.forEach(function (p) { aims[p.dataset.p] = aim(p); });
        var tl = gsap.timeline({
          defaults: { ease: 'power3.inOut', duration: .5 },
          scrollTrigger: {
            trigger: box, start: 'top top', end: '+=' + (steps.length * 50) + '%',
            scrub: 1, pin: true, anticipatePin: 1,
            onUpdate: function () { mark(); }
          }
        });

        gsap.set(steps, { autoAlpha: 0, y: 24 });
        gsap.set(pieces, { willChange: 'transform' });
        gsap.set(cur, { x: aims.home.x + 60, y: aims.home.y + 80, opacity: 0 });

        // 1. while the section scrolls in (before the pin), the pieces fly in from
        //    all sides and lock into the window, so the pin starts with a whole window
        var intro = gsap.timeline({ scrollTrigger: { trigger: box, start: 'top 85%', end: 'top 5%', scrub: true } });
        intro.fromTo(pieces, {
          x: function () { return gsap.utils.random(-260, 260); },
          y: function () { return gsap.utils.random(-200, 200); },
          rotate: function () { return gsap.utils.random(-25, 25); },
          opacity: 0, scale: .7
        }, { x: 0, y: 0, rotate: 0, opacity: 1, scale: 1, duration: .8, stagger: .03, ease: 'power3.out', immediateRender: true })
          .fromTo(win, { opacity: .3 }, { opacity: 1, duration: .6 }, 0);
        tl.to(cur, { opacity: 1, duration: .2 }, 0);

        var labels = [], rest = [], first = true;
        steps.forEach(function (st, i) {
          var key = st.dataset.p, at = 'step' + i;
          tl.addLabel(at, '+=.1');
          labels.push(at);
          if (key) {
            var focus = byKey(key), a = aims[key];
            // the cursor glides to the piece and clicks it
            tl.to(cur, { x: a.x, y: a.y, duration: .4, ease: 'power2.inOut' }, at)
              .fromTo(rip, { x: a.x, y: a.y, scale: .3, opacity: .9 }, { scale: 1.6, opacity: 0, duration: .3, ease: 'power1.out', immediateRender: false }, at + '+=.38');
            // everyone else breaks away and dims
            tl[first ? 'fromTo' : 'to'].apply(tl, (first ? [pieces, { x: 0, y: 0, rotate: 0, scale: 1, opacity: 1, '--hl': 0 }] : [pieces]).concat([{
              x: function (j, el) { return el === focus ? 0 : dirs[j].x; },
              y: function (j, el) { return el === focus ? -6 : dirs[j].y; },
              rotate: function (j, el) { return el === focus ? 0 : dirs[j].r; },
              scale: function (j, el) { return el === focus ? 1.12 : .93; },
              opacity: function (j, el) { return el === focus ? 1 : .14; },
              '--hl': function (j, el) { return el === focus ? 1 : 0; },
              zIndex: function (j, el) { return el === focus ? 2 : 1; },
              immediateRender: false
            }, at + '+=.3']));
            first = false;
            tl.to(drop, { opacity: key === 'menu' ? 1 : 0, duration: .3 }, at + '+=.3');
          } else {
            // last step: snap everything back together
            tl.to(cur, { opacity: 0, duration: .25 }, at);
            tl.to(pieces, { x: 0, y: 0, rotate: 0, scale: 1, opacity: 1, '--hl': 0, zIndex: 1, stagger: .02 }, at);
            tl.to(drop, { opacity: 0, duration: .3 }, at);
            tl.fromTo(win, { boxShadow: '0 0 0 0 rgba(0,0,0,0)' }, { boxShadow: '0 0 0 1px rgba(34,211,238,.5), 0 0 80px rgba(99,102,241,.35)', duration: .4 }, at + '+=.3');
          }
          if (i > 0) tl.to(steps[i - 1], { autoAlpha: 0, y: -20, duration: .3, ease: 'power2.in' }, at);
          tl.to(st, { autoAlpha: 1, y: 0, duration: .35, ease: 'power2.out' }, at + '+=.3');
          rest.push(tl.duration());
          tl.to({}, { duration: .45 });
        });

        var pager = UI.pager(sec.querySelector('[data-pager=tour]'), steps.length, function (i) {
          var st = tl.scrollTrigger;
          UI.scrollTo(st.start + (rest[i] / tl.duration()) * (st.end - st.start));
        });
        var last = -2;
        function mark() {
          var t = tl.time(), c = 0;
          labels.forEach(function (l, i) { if (t >= tl.labels[l]) c = i; });
          if (c !== last) { last = c; pager.set(c); }
        }
        mark();

        return function () {
          intro.scrollTrigger && intro.scrollTrigger.kill(); intro.kill();
          gsap.set(pieces.concat(steps, [win, drop, cur, rip]), { clearProps: 'all' });
          var pg = sec.querySelector('[data-pager=tour]'); if (pg) pg.hidden = true;
        };
      });

      mm.add('(max-width: 900px)', function () {
        // put a copy of each step's piece on top of its explanation
        var made = [];
        steps.forEach(function (st) {
          var p = st.dataset.p && byKey(st.dataset.p);
          if (!p) return;
          var slot = document.createElement('div');
          slot.className = 'pz-clone';
          slot.setAttribute('aria-hidden', 'true');
          var c = p.cloneNode(true);
          c.style.setProperty('--hl', 1);
          var d = c.querySelector('.mb-drop'); if (d) d.remove();
          slot.appendChild(c);
          st.insertBefore(slot, st.firstChild);
          made.push(slot);
          gsap.from(slot, { scale: .85, opacity: 0, y: 30, duration: .7, ease: 'back.out(1.6)', scrollTrigger: { trigger: st, start: 'top 85%', once: true } });
          gsap.from(st.querySelectorAll(':scope > :not(.pz-clone)'), { y: 20, opacity: 0, duration: .6, stagger: .05, scrollTrigger: { trigger: st, start: 'top 80%', once: true } });
        });
        gsap.from(pieces, {
          x: function () { return gsap.utils.random(-120, 120); },
          y: function () { return gsap.utils.random(-80, 80); },
          rotate: function () { return gsap.utils.random(-20, 20); },
          opacity: 0, duration: .9, stagger: .04, ease: 'power3.out',
          scrollTrigger: { trigger: stage, start: 'top 80%', once: true }
        });
        return function () { made.forEach(function (m) { m.remove(); }); };
      });
    }
  };
})();
