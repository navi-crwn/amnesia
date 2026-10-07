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

        // the desk fills up as it scrolls into view
        // (intro animates the inner svg/label so it never fights the scrub timeline below)
        gsap.from(sec.querySelector('.screen'), { y: 40, opacity: 0, duration: .8, ease: 'power3.out', scrollTrigger: { trigger: sec, start: 'top 70%', once: true } });
        gsap.from(sec.querySelectorAll('.ico > svg, .ico > span'), {
          scale: .5, opacity: 0, duration: .6, ease: 'back.out(1.6)',
          stagger: { each: .04, from: 'random' },
          scrollTrigger: { trigger: sec, start: 'top 70%', once: true }
        });
        gsap.from(s1, { y: 30, opacity: 0, duration: .8, ease: 'power3.out', scrollTrigger: { trigger: sec, start: 'top 70%', once: true } });

        var tl = gsap.timeline({
          defaults: { ease: 'power2.inOut' },
          scrollTrigger: desk
            ? { trigger: box, start: 'top top', end: '+=140%', scrub: .6, pin: true, anticipatePin: 1 }
            : { trigger: sec.querySelector('.screen'), start: 'top 75%', end: 'bottom 30%', scrub: .6 }
        });
        tl.to({}, { duration: .3 })
          .to(btn, { scale: .92, duration: .08 })
          .to(btn, { scale: 1, duration: .1 })
          .fromTo(gone, { opacity: 1, scale: 1, y: 0, rotate: 0 }, { opacity: 0, scale: .6, y: -18, rotate: function () { return gsap.utils.random(-14, 14); }, duration: .5, stagger: { each: .025, from: 'random' }, immediateRender: false }, '<')
          .to(halos, { opacity: 1, duration: .3, stagger: .05 }, '-=.25');
        if (desk) tl.fromTo(s1, { autoAlpha: 1, y: 0 }, { autoAlpha: 0, y: -30, duration: .25, immediateRender: false }, '<-.35');
        tl.to(s2, { autoAlpha: 1, y: 0, duration: .3 }, '>-.05')
          .to({}, { duration: .3 });

        return function () { gsap.set([s1, s2, gone, halos, btn], { clearProps: 'all' }); };
      });
    }
  };
})();
