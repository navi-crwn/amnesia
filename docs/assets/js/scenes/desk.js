/* 01 + 02: a Mac desk full of files. Scrolling presses Log Out:
   everything dissolves except Keep, Vault, Keep List and Apps, which glow green.
   Desktop: the section is pinned while the story plays. Phone: no pin,
   the same timeline simply follows the scroll. */
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

      mm.add({ desk: '(min-width: 901px)', mob: '(max-width: 900px)' }, function (ctx) {
        var desk = ctx.conditions.desk;
        gsap.set(s2, desk ? { autoAlpha: 0, y: 30 } : { autoAlpha: .2, y: 20 });

        var prog = sec.querySelector('.prog b');
        var parts = sec.querySelectorAll('.ico > svg, .ico > span');

        // 1. the desk fills up while the section scrolls into view (no pin yet)
        gsap.timeline({ scrollTrigger: { trigger: sec, start: 'top 85%', end: desk ? 'top top' : 'top 25%', scrub: .5 } })
          .from(sec.querySelector('.screen'), { y: 60, opacity: 0, duration: .4, ease: 'power2.out' })
          .from(parts, { scale: .4, opacity: 0, duration: .5, ease: 'back.out(1.6)', stagger: { each: .02, from: 'random' } }, .1)
          .from(s1, { y: 30, opacity: 0, duration: .4 }, 0);

        // 2. once it's in place: Log Out, everything else dissolves. Motion starts right away.
        var tl = gsap.timeline({
          defaults: { ease: 'power2.inOut' },
          scrollTrigger: desk
            ? { trigger: box, start: 'top top', end: '+=80%', scrub: .5, pin: true, anticipatePin: 1 }
            : { trigger: sec.querySelector('.screen'), start: 'top 35%', end: 'bottom 20%', scrub: .5 }
        });
        tl.to(prog, { scaleX: 1, duration: 1.1, ease: 'none' }, 0)
          .to(btn, { scale: .92, duration: .06 }, 0)
          .to(btn, { scale: 1, duration: .08 }, .06)
          .fromTo(gone, { opacity: 1, scale: 1, y: 0, rotate: 0 }, { opacity: 0, scale: .6, y: -18, rotate: function () { return gsap.utils.random(-14, 14); }, duration: .5, stagger: { each: .02, from: 'random' }, immediateRender: false }, .08)
          .to(halos, { opacity: 1, duration: .3, stagger: .05 }, .55);
        if (desk) tl.fromTo(s1, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -30, duration: .25, immediateRender: false }, .45);
        tl.to(s2, { autoAlpha: 1, y: 0, duration: .3 }, .65);

        return function () { gsap.set([s1, s2, gone, halos, btn, prog, parts, sec.querySelector('.screen')], { clearProps: 'all' }); };
      });
    }
  };
})();
