/* Amnesia website: language, copy buttons, navbar, then motion.
   Motion only starts when GSAP loaded and the visitor allows motion.
   Without it the page is complete and readable as plain HTML. */
(function () {
  'use strict';
  var root = document.documentElement;
  var Scenes = window.AmnesiaScenes || {};

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

  // ---------- copy buttons ----------
  document.querySelectorAll('.term .copy').forEach(function (b) {
    b.addEventListener('click', function () {
      var t = b.parentElement.querySelector('code').dataset.full || b.parentElement.querySelector('code').textContent;
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

  // ---------- motion ----------
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduced || !window.gsap || !window.ScrollTrigger) return;

  gsap.registerPlugin(ScrollTrigger);
  if (window.SplitText) gsap.registerPlugin(SplitText);
  root.classList.add('motion');

  // smooth scroll, kept in sync with ScrollTrigger
  var lenis = null;
  if (window.Lenis) {
    lenis = new Lenis({ duration: 1.1, smoothWheel: true });
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

  // generic reveal for section heads and cards
  var mm = gsap.matchMedia();
  ['hero', 'desk', 'story'].forEach(function (k) {
    if (Scenes[k]) Scenes[k].init(mm, lenis);
  });

  // reveal anything marked .head / .card / .feat text that a scene didn't take
  gsap.utils.toArray('.ref .head, .stage .head, .card, .tut li, .gloss .card, .faq details').forEach(function (el) {
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
})();
