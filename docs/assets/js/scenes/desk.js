/* 01 + 02: a Mac desk full of files. Scrolling presses Log Out:
   everything dissolves except Keep, Vault, Keep List and Apps, which glow green.
   Text 01 is already there when the icons appear and only leaves after they
   are wiped; then text 02 comes in.
   Desktop: the section is pinned while the story plays, with arrows/dots.
   Phone: no pin, the same story follows the scroll. */
(function () {
  'use strict';
  var S = window.AmnesiaScenes = window.AmnesiaScenes || {};

  S.desk = {
    init: function (mm) {
      var sec = document.getElementById('desk');
      if (!sec) return;
      var box = sec.querySelector('.pinbox');
      var s1 = sec.querySelector('.s1'), s2 = sec.querySelector('.s2');
      var gone = sec.querySelectorAll('.ico:not(.keep)');
      var halos = sec.querySelectorAll('.ico.keep .halo');
      var btn = sec.querySelector('.logout button');
      var screen = sec.querySelector('.screen');
      var UI = window.AmnesiaUI;

      mm.add({ desk: '(min-width: 901px)', mob: '(max-width: 900px)' }, function (ctx) {
        var desk = ctx.conditions.desk;
        gsap.set(s2, desk ? { autoAlpha: 0, y: 30 } : { autoAlpha: .2, y: 20 });

        var prog = sec.querySelector('.prog b');
        var parts = sec.querySelectorAll('.ico > svg, .ico > span');

        // 1. the desk fills up while the section scrolls into view (no pin yet).
        //    Text 01 is fully in before the first icon pops.
        gsap.timeline({ scrollTrigger: { trigger: sec, start: 'top 90%', end: desk ? 'top top' : 'top 25%', scrub: .5 } })
          .fromTo(s1, { y: 30, autoAlpha: 0 }, { y: 0, autoAlpha: 1, duration: .2, immediateRender: true }, 0)
          .from(screen, { y: 60, opacity: 0, duration: .35, ease: 'power2.out' }, .05)
          .from(parts, { scale: .4, opacity: 0, duration: .5, ease: 'back.out(1.6)', stagger: { each: .02, from: 'random' } }, .22);

        // 2. once it's in place: Log Out. Icons dissolve first; only then text 01 leaves.
        var tl = gsap.timeline({
          defaults: { ease: 'power2.inOut' },
          scrollTrigger: desk
            ? { trigger: box, start: 'top top', end: '+=110%', scrub: .6, pin: true, anticipatePin: 1, onUpdate: function (self) { pager.set(self.progress > .62 ? 1 : 0); } }
            : { trigger: screen, start: 'top 35%', end: 'bottom 20%', scrub: .5 }
        });
        tl.to(prog, { scaleX: 1, duration: .9, ease: 'none' }, 0)
          .to(btn, { scale: .92, duration: .06 }, 0)
          .to(btn, { scale: 1, duration: .08 }, .06)
          .fromTo(gone, { opacity: 1, scale: 1, y: 0, rotate: 0 }, { opacity: 0, scale: .6, y: -18, rotate: function () { return gsap.utils.random(-14, 14); }, duration: .45, stagger: { each: .025, from: 'random' }, immediateRender: false }, .08)
          .to(halos, { opacity: 1, duration: .25, stagger: .05 }, .85);
        if (desk) tl.fromTo(s1, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -30, duration: .2, immediateRender: false }, 1.0);
        tl.to(s2, { autoAlpha: 1, y: 0, duration: .3 }, desk ? 1.12 : .8);
        if (desk) tl.to({}, { duration: .25 });

        var pager = { set: function () {} };
        if (desk && UI && UI.pager) {
          var st = tl.scrollTrigger;
          pager = UI.pager(sec.querySelector('[data-pager=desk]'), 2, function (i) {
            UI.scrollTo(i === 0 ? st.start + 2 : st.end - 2);
          });
        }

        return function () {
          gsap.set([s1, s2, gone, halos, btn, prog, parts, screen], { clearProps: 'all' });
          var pg = sec.querySelector('[data-pager=desk]'); if (pg) pg.hidden = true;
        };
      });
    }
  };
})();
