/* 08: the Amnesia main window as a puzzle.
   Wide screens: the section is pinned. The pieces fly in and lock together,
   then one piece at a time is lifted out while the rest break apart, and its
   explanation shows on the left. At the end everything snaps back together.
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
      var rail = gsap.utils.toArray(sec.querySelectorAll('.pz-rail li'));
      var drop = sec.querySelector('.mb-drop');
      steps.forEach(function (el) { el.dataset.scene = 1; });

      function byKey(k) { return stage.querySelector('.pc[data-p="' + k + '"]'); }

      // direction each piece moves when the window "breaks": away from the window centre
      function burst(el, i) {
        var r = el.getBoundingClientRect(), w = win.getBoundingClientRect();
        var dx = (r.left + r.width / 2) - (w.left + w.width / 2);
        var dy = (r.top + r.height / 2) - (w.top + w.height / 2);
        var len = Math.hypot(dx, dy) || 1;
        return { x: dx / len * 64, y: dy / len * 56, r: (i % 2 ? 1 : -1) * 5 };
      }

      mm.add('(min-width: 901px)', function () {
        var dirs = pieces.map(burst);
        var tl = gsap.timeline({
          defaults: { ease: 'power2.inOut', duration: .5 },
          scrollTrigger: {
            trigger: box, start: 'top top', end: '+=' + (steps.length * 55) + '%',
            scrub: .6, pin: true, anticipatePin: 1,
            onUpdate: function () { markRail(); }
          }
        });

        gsap.set(steps, { autoAlpha: 0, y: 24 });

        // 1. pieces fly in from all sides and lock into the window
        tl.from(pieces, {
          x: function () { return gsap.utils.random(-260, 260); },
          y: function () { return gsap.utils.random(-200, 200); },
          rotate: function () { return gsap.utils.random(-25, 25); },
          opacity: 0, scale: .7, duration: .8, stagger: .03, ease: 'power3.out'
        }).from(win, { opacity: .3, duration: .6 }, 0);

        var labels = [];
        steps.forEach(function (st, i) {
          var key = st.dataset.p, at = 'step' + i;
          tl.addLabel(at, '+=.15');
          labels.push(at);
          if (key) {
            var focus = byKey(key);
            // everyone else breaks away and dims
            tl.to(pieces, {
              x: function (j, el) { return el === focus ? 0 : dirs[j].x; },
              y: function (j, el) { return el === focus ? -6 : dirs[j].y; },
              rotate: function (j, el) { return el === focus ? 0 : dirs[j].r; },
              scale: function (j, el) { return el === focus ? 1.14 : .92; },
              opacity: function (j, el) { return el === focus ? 1 : .22; },
              '--hl': function (j, el) { return el === focus ? 1 : 0; },
              zIndex: function (j, el) { return el === focus ? 2 : 1; }
            }, at);
            tl.to(drop, { opacity: key === 'menu' ? 1 : 0, duration: .3 }, at);
          } else {
            // last step: snap everything back together
            tl.to(pieces, { x: 0, y: 0, rotate: 0, scale: 1, opacity: 1, '--hl': 0, zIndex: 1, stagger: .02 }, at);
            tl.to(drop, { opacity: 0, duration: .3 }, at);
            tl.fromTo(win, { boxShadow: '0 40px 120px rgba(0,0,0,.6)' }, { boxShadow: '0 40px 120px rgba(0,0,0,.6), 0 0 0 1px rgba(34,211,238,.5), 0 0 80px rgba(99,102,241,.35)', duration: .4 }, at + '+=.3');
          }
          if (i > 0) tl.to(steps[i - 1], { autoAlpha: 0, y: -24, duration: .3 }, at);
          tl.to(st, { autoAlpha: 1, y: 0, duration: .35 }, at + '+=.15');
          tl.to({}, { duration: .55 });
        });

        function markRail() {
          var t = tl.time(), cur = -1;
          labels.forEach(function (l, i) { if (t >= tl.labels[l]) cur = i; });
          rail.forEach(function (d, i) { d.classList.toggle('on', i === cur); d.classList.toggle('done', i < cur); });
        }
        markRail();

        return function () {
          gsap.set(pieces.concat(steps, [win, drop]), { clearProps: 'all' });
          rail.forEach(function (d) { d.className = ''; });
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
