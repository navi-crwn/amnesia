/* More 3D objects (three.js), next to the logo in shield3d.js:
   - 01 "Every commit": one column per day on a grid of tiles (weeks × weekdays),
     as tall as that day's commits, read from GitHub by site.js. Hover or tap a
     column for its date.
   - 05 Profile Vault: a small safe whose dial turns a combination and whose
     handle turns open, in the middle of the ring of apps.
   Phones: lower resolution. Reduce motion: still frames (the chart can still be
   hovered). No WebGL or the CDN fails: the flat versions stay. */
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const touch = matchMedia('(max-width: 900px), (pointer: coarse)').matches;
const root = document.documentElement;
const pointer = { x: 0, y: 0 };
addEventListener('pointermove', (e) => {
  pointer.x = e.clientX / innerWidth - 0.5;
  pointer.y = e.clientY / innerHeight - 0.5;
}, { passive: true });

function hasWebGL() {
  try { const c = document.createElement('canvas'); return !!(c.getContext('webgl2') || c.getContext('webgl')); }
  catch (e) { return false; }
}
function isLight() { return (window.AmnesiaUI && window.AmnesiaUI.theme && window.AmnesiaUI.theme()) === 'light'; }
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

// one renderer + scene + camera in a host element, drawn only while on screen
function stage(host, { fov = 30, envK = 0.5, tone = THREE.ACESFilmicToneMapping } = {}) {
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  host.appendChild(canvas);
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, touch ? 1.5 : 2));
  renderer.toneMapping = tone;
  renderer.toneMappingExposure = 1;
  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = envK;
  pmrem.dispose();
  const camera = new THREE.PerspectiveCamera(fov, 1, 0.1, 200);
  const st = { canvas, renderer, scene, camera, frame: null, fit: null, on: false, raf: 0, clock: new THREE.Clock(false) };
  st.size = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    if (st.fit) st.fit(w, h);
    camera.updateProjectionMatrix();
    if (!st.on) st.draw();
  };
  st.draw = () => { if (st.frame) st.frame(st.clock.getElapsedTime()); renderer.render(scene, camera); };
  const loop = () => { st.draw(); st.raf = requestAnimationFrame(loop); };
  st.run = (v) => {
    if (reduced) v = false;
    if (v === st.on) return; st.on = v;
    if (v) { st.clock.start(); loop(); } else { cancelAnimationFrame(st.raf); st.clock.stop(); }
  };
  let inView = false;
  st.start = () => {
    st.size();
    if (window.ResizeObserver) new ResizeObserver(st.size).observe(canvas);
    st.draw();
    host.classList.add('live');
    if (window.IntersectionObserver) {
      new IntersectionObserver((e) => { inView = e[0].isIntersecting; st.run(inView && !document.hidden); if (inView && st.seen) st.seen(); }, { rootMargin: '80px' }).observe(host);
    } else { inView = true; st.run(true); if (st.seen) st.seen(); }
    document.addEventListener('visibilitychange', () => st.run(inView && !document.hidden));
  };
  return st;
}

// ---------------------------------------------------------------- commit chart
const BAR_COLORS = ['#22d3ee', '#38bdf8', '#6366f1', '#8b5cf6', '#a78bfa', '#ec4899', '#f472b6', '#f97316', '#fb923c', '#10b981', '#34d399', '#f43f5e'];

function mountCommits(host, days) {
  if (host._mounted || !days || !days.length) return;
  host._mounted = true;
  const st = stage(host, { fov: 26, envK: 0.35, tone: THREE.NeutralToneMapping });
  const { scene, camera } = st;
  const tip = host.querySelector('.cm-tip');

  scene.add(new THREE.HemisphereLight(0xffffff, 0x404060, 0.9));
  const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(-6, 14, 10); scene.add(key);

  const grid = new THREE.Group(); scene.add(grid);
  const S = 1, GAP = 0.26, P = S + GAP;
  const first = new Date(days[0][0] + 'T12:00:00Z');
  const offset = (first.getUTCDay() + 6) % 7; // Monday = row 0
  const cols = Math.ceil((days.length + offset) / 7);
  const max = Math.max(1, ...days.map((d) => d[1]));
  const W = cols * P - GAP, D = 7 * P - GAP;

  const tileGeo = new RoundedBoxGeometry(S, 0.16, S, 2, 0.05);
  const tileMat = new THREE.MeshStandardMaterial({ color: isLight() ? 0xd9dce8 : 0x1d1f2b, roughness: 0.7, metalness: 0.1 });
  const barGeo = new RoundedBoxGeometry(S * 0.86, 1, S * 0.86, 3, 0.09);
  barGeo.translate(0, 0.5, 0);
  const bars = [];
  days.forEach(([date, n], i) => {
    const k = i + offset, c = Math.floor(k / 7), r = k % 7;
    const x = c * P - W / 2 + S / 2, z = r * P - D / 2 + S / 2;
    const tile = new THREE.Mesh(tileGeo, tileMat); tile.position.set(x, -0.08, z); grid.add(tile);
    if (!n) return;
    const col = new THREE.Color(BAR_COLORS[Math.floor(c * BAR_COLORS.length / Math.max(cols, 1)) % BAR_COLORS.length]);
    const mat = new THREE.MeshPhysicalMaterial({ color: col, roughness: 0.38, metalness: 0.05, clearcoat: 0.5, clearcoatRoughness: 0.3, emissive: col, emissiveIntensity: 0.06 });
    const bar = new THREE.Mesh(barGeo, mat);
    const h = 0.45 + (n / max) * 3.6;
    bar.position.set(x, 0, z); bar.scale.y = reduced ? h : 0.001;
    bar.userData = { date, n, h, delay: c * 0.05 + r * 0.02 };
    grid.add(bar); bars.push(bar);
  });

  const target = new THREE.Vector3(0, 0.9, 0);
  st.fit = (w, h) => {
    // keep the whole grid in view from a three-quarter angle
    const span = Math.max(W, D) * 0.5 + 1.2;
    const dist = span / Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) / Math.min(1.2, Math.max(0.55, camera.aspect * 0.9));
    camera.position.set(dist * 0.38, dist * 0.5, dist * 0.78);
    camera.lookAt(target);
  };

  let grow = reduced ? 1 : 0, growing = false, t0 = 0;
  st.seen = () => { if (!growing && grow < 1) { growing = true; t0 = performance.now(); } };
  const rot = { x: 0, y: -0.18 };
  st.frame = (t) => {
    if (growing) {
      grow = Math.min(1, (performance.now() - t0) / 1600);
      if (grow >= 1) growing = false;
    }
    bars.forEach((b) => {
      const g = Math.min(1, Math.max(0, (grow * 1.6 - b.userData.delay) / 0.6));
      b.scale.y = Math.max(0.001, ease(g) * b.userData.h);
    });
    const ty = (touch ? Math.sin(t * 0.3) * 0.12 : pointer.x * 0.5) - 0.18;
    const tx = touch ? 0 : pointer.y * 0.12;
    rot.x += (tx - rot.x) * 0.05; rot.y += (ty - rot.y) * 0.05;
    grid.rotation.set(rot.x, rot.y, 0);
  };

  // hover / tap a column: date and count
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  let hot = null;
  function pick(e) {
    const r = st.canvas.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ndc, camera);
    const hit = ray.intersectObjects(bars, false)[0];
    const b = hit ? hit.object : null;
    if (hot && hot !== b) hot.material.emissiveIntensity = 0.06;
    hot = b;
    if (!b) { tip.hidden = true; if (!st.on) st.draw(); return; }
    b.material.emissiveIntensity = 0.45;
    const d = new Date(b.userData.date + 'T12:00:00Z');
    const id = root.lang === 'id';
    const when = d.toLocaleDateString(id ? 'id-ID' : 'en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
    tip.textContent = '';
    const bold = document.createElement('b'); bold.textContent = b.userData.n + (id ? ' commit' : b.userData.n === 1 ? ' commit' : ' commits');
    tip.appendChild(bold); tip.appendChild(document.createTextNode(' · ' + when));
    tip.style.left = (e.clientX - r.left) + 'px'; tip.style.top = (e.clientY - r.top) + 'px';
    tip.hidden = false;
    if (!st.on) st.draw();
  }
  st.canvas.addEventListener('pointermove', pick);
  st.canvas.addEventListener('pointerdown', pick);
  st.canvas.addEventListener('pointerleave', () => { if (hot) hot.material.emissiveIntensity = 0.06; hot = null; tip.hidden = true; if (!st.on) st.draw(); });
  document.addEventListener('amnesia:theme', () => { tileMat.color.set(isLight() ? 0xd9dce8 : 0x1d1f2b); if (!st.on) st.draw(); });

  st.start();
}

// ---------------------------------------------------------------- vault safe
function mountSafe(host) {
  const st = stage(host, { fov: 28, envK: 0.6 });
  const { scene, camera } = st;
  scene.add(new THREE.HemisphereLight(0xffffff, 0x303050, 0.7));
  const key = new THREE.DirectionalLight(0xffffff, 1.5); key.position.set(-3, 4, 6); scene.add(key);
  const rim = new THREE.PointLight(0xec4899, 14, 10); rim.position.set(3, -2, 3); scene.add(rim);
  const cy = new THREE.PointLight(0x22d3ee, 12, 10); cy.position.set(-3, 2, 3); scene.add(cy);

  const safe = new THREE.Group(); scene.add(safe);
  const metal = new THREE.MeshPhysicalMaterial({ color: 0x2b2f5c, metalness: 0.55, roughness: 0.32, clearcoat: 0.8, clearcoatRoughness: 0.2 });
  const body = new THREE.Mesh(new RoundedBoxGeometry(2.5, 2.5, 1.5, 4, 0.24), metal);
  safe.add(body);

  // round door with a brand-coloured rim
  const doorZ = 0.75;
  const door = new THREE.Mesh(new THREE.CylinderGeometry(0.92, 0.92, 0.12, 64).rotateX(Math.PI / 2), new THREE.MeshPhysicalMaterial({ color: 0x353a70, metalness: 0.6, roughness: 0.28, clearcoat: 1 }));
  door.position.set(-0.18, 0, doorZ + 0.04); safe.add(door);
  const ringMat = new THREE.MeshPhysicalMaterial({ color: 0x6366f1, metalness: 0.3, roughness: 0.2, clearcoat: 1, emissive: 0x6366f1, emissiveIntensity: 0.25 });
  const ring = new THREE.Mesh(new THREE.TorusGeometry(0.95, 0.05, 16, 96), ringMat);
  ring.position.set(-0.18, 0, doorZ + 0.1); safe.add(ring);

  // the dial, with ticks, and a little pointer above it
  const dial = new THREE.Group(); dial.position.set(-0.18, 0, doorZ + 0.12); safe.add(dial);
  const white = new THREE.MeshPhysicalMaterial({ color: 0xf2f3ff, roughness: 0.2, metalness: 0.1, clearcoat: 1 });
  dial.add(new THREE.Mesh(new THREE.CylinderGeometry(0.46, 0.5, 0.16, 64).rotateX(Math.PI / 2), white));
  const tickMat = new THREE.MeshBasicMaterial({ color: 0x2b2f5c });
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2, long = i % 6 === 0;
    const tk = new THREE.Mesh(new THREE.BoxGeometry(0.03, long ? 0.12 : 0.07, 0.02), tickMat);
    tk.position.set(Math.sin(a) * 0.36, Math.cos(a) * 0.36, 0.09); tk.rotation.z = -a; dial.add(tk);
  }
  const knob = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.18, 0.14, 32).rotateX(Math.PI / 2), white);
  knob.position.z = 0.12; dial.add(knob);
  const mark = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.12, 3), new THREE.MeshBasicMaterial({ color: 0xec4899 }));
  mark.rotation.z = Math.PI; mark.position.set(-0.18, 0.62, doorZ + 0.14); safe.add(mark);

  // three-spoke handle at the right
  const handle = new THREE.Group(); handle.position.set(0.9, -0.55, doorZ + 0.08); safe.add(handle);
  const chrome = new THREE.MeshPhysicalMaterial({ color: 0xdfe3ff, metalness: 0.9, roughness: 0.18 });
  handle.add(new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.14, 24).rotateX(Math.PI / 2), chrome));
  for (let i = 0; i < 3; i++) {
    const sp = new THREE.Group(); sp.rotation.z = (i / 3) * Math.PI * 2;
    const rod = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.3, 12), chrome); rod.position.y = 0.17; sp.add(rod);
    const tipb = new THREE.Mesh(new THREE.SphereGeometry(0.055, 16, 12), chrome); tipb.position.y = 0.33; sp.add(tipb);
    sp.position.z = 0.04; handle.add(sp);
  }
  // hinges on the left edge
  [-0.7, 0.7].forEach((y) => {
    const h = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.34, 16), chrome);
    h.position.set(-1.27, y, 0.5); safe.add(h);
  });

  st.fit = () => {
    camera.position.set(0, 0, 9.4 / Math.min(1, camera.aspect));
    camera.lookAt(0, 0, 0);
  };

  // a combination: right, left, right; then the handle turns and the rim lights up
  const steps = [[0, 0], [1.1, 2.2], [1.6, -1.4], [2.3, 0.9], [2.8, 0.9]];
  const rot = { x: 0.1, y: -0.45 };
  st.frame = (t) => {
    const T = 7, k = (t % T);
    let a = 0;
    for (let i = 1; i < steps.length; i++) {
      const [ts, v] = steps[i], [tp, pv] = steps[i - 1];
      if (k >= ts) a = v; else { a = pv + (v - pv) * ease(Math.max(0, (k - tp) / (ts - tp))); break; }
    }
    dial.rotation.z = a;
    const open = k > 3 && k < 5.6 ? ease(Math.min(1, (k - 3) / 0.6)) : k >= 5.6 ? 1 - ease(Math.min(1, (k - 5.6) / 0.8)) : 0;
    handle.rotation.z = -open * Math.PI / 2;
    ringMat.emissiveIntensity = 0.25 + open * 0.9;
    ringMat.emissive.set(open > 0.5 ? 0x10b981 : 0x6366f1);
    const ty = (touch ? Math.sin(t * 0.5) * 0.25 : pointer.x * 0.9) - 0.42;
    const tx = (touch ? 0 : pointer.y * 0.5) + 0.1;
    rot.x += (tx - rot.x) * 0.06; rot.y += (ty - rot.y) * 0.06;
    safe.rotation.set(rot.x, rot.y, 0);
    safe.position.y = Math.sin(t * 0.9) * 0.06;
  };
  if (reduced) { dial.rotation.z = 0.9; }
  host.closest('.vaultviz').classList.add('has3d');
  st.start();
}

if (hasWebGL()) {
  document.querySelectorAll('[data-obj3d=safe]').forEach((h) => { try { mountSafe(h); } catch (e) { /* the flat shield stays */ } });
  const cm = document.querySelector('[data-obj3d=commits]');
  if (cm) {
    const go = (d) => { try { mountCommits(cm, d && d.days); } catch (e) { /* the message stays */ } };
    if (window.AmnesiaUI && window.AmnesiaUI.gh) go(window.AmnesiaUI.gh);
    document.addEventListener('amnesia:gh', (e) => go(e.detail));
  }
}
