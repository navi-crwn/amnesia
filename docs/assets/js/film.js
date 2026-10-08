/* Amnesia website: the paper craft videos.
   - videos marked data-auto play muted (no sound) only while they are on screen, and load only then
   - the big story video has a sound button
   - a reel opens in a player with sound (dialog); Esc, the close button or a click outside closes it
   - visitors who ask for less motion (or save data) see the still picture until they press play */
(function () {
  'use strict';
  var calm = window.matchMedia('(prefers-reduced-motion: reduce)').matches ||
    (navigator.connection && navigator.connection.saveData);

  // torn paper edge: a polygon with small random bumps, the same on every visit
  var paper = document.querySelector('.film .paper-sheet');
  if (paper) {
    var seed = 7, rnd = function () { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    var pts = [], n = 46, j = function (a) { return (rnd() * a).toFixed(2); };
    for (var i = 0; i <= n; i++) pts.push((i / n * 100).toFixed(2) + '% ' + j(1.1) + '%');
    for (i = 1; i <= n / 2; i++) pts.push((100 - +j(.7)) + '% ' + (i / (n / 2) * 100).toFixed(2) + '%');
    for (i = n - 1; i >= 0; i--) pts.push((i / n * 100).toFixed(2) + '% ' + (100 - +j(1.1)) + '%');
    for (i = n / 2 - 1; i >= 1; i--) pts.push(j(.7) + '% ' + (i / (n / 2) * 100).toFixed(2) + '%');
    paper.style.clipPath = 'polygon(' + pts.join(',') + ')';
  }

  function play(v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); }
  var autos = [].slice.call(document.querySelectorAll('video[data-auto]'));
  if (!calm && 'IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        var v = e.target;
        if (e.isIntersecting) { if (v.preload === 'none') v.preload = 'auto'; play(v); }
        else v.pause();
      });
    }, { threshold: .35 });
    autos.forEach(function (v) { io.observe(v); });
  }

  // big story video: sound on/off. Turning sound on starts the story from the beginning.
  var fv = document.querySelector('.film .fv'), snd = document.querySelector('.film .sound');
  if (fv && snd) {
    snd.addEventListener('click', function () {
      var on = fv.muted;
      fv.muted = !on;
      if (on) { fv.currentTime = 0; fv.loop = false; play(fv); } else fv.loop = true;
      snd.setAttribute('aria-pressed', String(on));
    });
    fv.addEventListener('ended', function () { fv.muted = true; fv.loop = true; snd.setAttribute('aria-pressed', 'false'); play(fv); });
    if (calm) fv.controls = true;
  }

  // reels: open in the player with sound
  var box = document.getElementById('film-box');
  if (!box || !box.showModal) return;
  var bv = box.querySelector('video');
  function close() { bv.pause(); box.close(); }
  document.querySelectorAll('.reel').forEach(function (r) {
    r.addEventListener('click', function () {
      bv.poster = r.dataset.poster; bv.src = r.dataset.film; bv.muted = false;
      autos.forEach(function (v) { v.pause(); });
      box.showModal(); play(bv);
    });
  });
  box.querySelector('.fb-close').addEventListener('click', close);
  box.addEventListener('click', function (e) { if (e.target === box) close(); });
  box.addEventListener('close', function () {
    bv.pause(); bv.removeAttribute('src'); bv.load();
    if (!calm) autos.forEach(function (v) { var b = v.getBoundingClientRect(); if (b.bottom > 0 && b.top < innerHeight && v.preload !== 'none') play(v); });
  });
})();
