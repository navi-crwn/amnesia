/* Windows page only: two more 3D objects (three.js), in the style of
   ../assets/js/scenes/objects3d.js.
   - "sweep" (Safe at sign out): a grid of folder tiles. A light sweeps over it like
     a sign out: ordinary folders sink away, while Keep, cloud folders and virtual
     machines stay and light up. Then a new day starts and the folders come back.
   - "safebox" (Locks): the Safe box. Files drop into a box, the lid closes, a lock
     snaps shut and turns green (closed = one locked file), then it opens again.
   Phones: lower resolution, no cursor. Reduce motion: one still frame.
   No WebGL or the CDN fails: the flat drawing in the HTML stays. */
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';

const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
const touch = matchMedia('(max-width: 900px), (pointer: coarse)').matches;
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
const clamp01 = (t) => Math.max(0, Math.min(1, t));

// one renderer + scene + camera in a host element, drawn only while on screen
function stage(host, { fov = 30, envK = 0.55 } = {}) {
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  host.appendChild(canvas);
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, touch ? 1.5 : 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
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
  st.draw = () => { if (st.frame) st.frame(reduced ? st.still || 0 : st.clock.getElapsedTime()); renderer.render(scene, camera); };
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
      new IntersectionObserver((e) => { inView = e[0].isIntersecting; st.run(inView && !document.hidden); }, { rootMargin: '80px' }).observe(host);
    } else { inView = true; st.run(true); }
    document.addEventListener('visibilitychange', () => st.run(inView && !document.hidden));
    document.addEventListener('amnesia:theme', () => { if (st.theme) st.theme(); if (!st.on) st.draw(); });
  };
  return st;
}
function lights(scene) {
  scene.add(new THREE.HemisphereLight(0xffffff, 0x303050, 0.7));
  const key = new THREE.DirectionalLight(0xffffff, 1.4); key.position.set(-3, 6, 6); scene.add(key);
  const rim = new THREE.PointLight(0xec4899, 12, 14); rim.position.set(4, 2, -2); scene.add(rim);
  const cy = new THREE.PointLight(0x22d3ee, 12, 14); cy.position.set(-4, 3, 3); scene.add(cy);
}

// ---------------------------------------------------------------- sign out sweep
// k = kind: '' wiped at sign out, keep, cloud, vm
const GRID = [
  ['', 'cloud', '', '', 'keep'],
  ['', '', 'vm', '', ''],
  ['keep', '', '', 'cloud', ''],
];
const KIND = { keep: 0x10b981, cloud: 0x22d3ee, vm: 0xa78bfa, '': 0xf97316 };

function folderShape() {
  // a folder seen from above: a tab on the back left
  const s = new THREE.Shape();
  const w = 0.9, h = 0.7, r = 0.08;
  s.moveTo(-w / 2 + r, -h / 2);
  s.lineTo(w / 2 - r, -h / 2); s.quadraticCurveTo(w / 2, -h / 2, w / 2, -h / 2 + r);
  s.lineTo(w / 2, h / 2 - r); s.quadraticCurveTo(w / 2, h / 2, w / 2 - r, h / 2);
  s.lineTo(-0.02, h / 2); s.lineTo(-0.1, h / 2 + 0.12); s.lineTo(-w / 2 + r, h / 2 + 0.12);
  s.quadraticCurveTo(-w / 2, h / 2 + 0.12, -w / 2, h / 2 + 0.12 - r);
  s.lineTo(-w / 2, -h / 2 + r); s.quadraticCurveTo(-w / 2, -h / 2, -w / 2 + r, -h / 2);
  return s;
}

function mountSweep(host) {
  const st = stage(host, { fov: 30 });
  const { scene, camera } = st;
  lights(scene);
  const board = new THREE.Group(); scene.add(board);
  board.rotation.x = -0.95;

  const base = new THREE.Mesh(new RoundedBoxGeometry(6.6, 4.4, 0.18, 4, 0.12),
    new THREE.MeshPhysicalMaterial({ color: 0x1b1e3a, metalness: 0.3, roughness: 0.5, clearcoat: 0.6, transparent: true, opacity: 0.92 }));
  base.position.z = -0.12; board.add(base);

  const geo = new THREE.ExtrudeGeometry(folderShape(), { depth: 0.16, bevelEnabled: true, bevelThickness: 0.03, bevelSize: 0.03, bevelSegments: 2, curveSegments: 6 });
  geo.translate(0, -0.05, 0);
  const tiles = [];
  GRID.forEach((row, r) => row.forEach((k, c) => {
    const col = KIND[k];
    const mat = new THREE.MeshPhysicalMaterial({ color: k ? col : 0x4b5068, metalness: 0.2, roughness: 0.35, clearcoat: 1, emissive: col, emissiveIntensity: 0, transparent: true });
    const m = new THREE.Mesh(geo, mat);
    m.position.set((c - 2) * 1.22, (1 - r) * 1.18, 0);
    board.add(m);
    let halo = null;
    if (k) {
      halo = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.025, 8, 64), new THREE.MeshBasicMaterial({ color: col, transparent: true, opacity: 0 }));
      halo.position.set(m.position.x, m.position.y + 0.04, 0.02); board.add(halo);
    }
    tiles.push({ m, mat, halo, k, x: m.position.x });
  }));

  // the sweep: a thin bar of light that crosses the board
  const beamMat = new THREE.MeshBasicMaterial({ color: 0x8b8ff8, transparent: true, opacity: 0.55, blending: THREE.AdditiveBlending, depthWrite: false });
  const beam = new THREE.Mesh(new THREE.PlaneGeometry(0.12, 4.2), beamMat);
  beam.position.z = 0.5; board.add(beam);
  const glow = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 4.2), new THREE.MeshBasicMaterial({ color: 0x6366f1, transparent: true, opacity: 0.16, blending: THREE.AdditiveBlending, depthWrite: false }));
  glow.position.z = 0.48; board.add(glow);

  st.theme = () => { base.material.color.set(isLight() ? 0xdfe2f5 : 0x1b1e3a); };
  st.theme();
  st.fit = () => {
    camera.position.set(0, 0.2, 11.2 / Math.min(1, camera.aspect * 0.95));
    camera.lookAt(0, -0.2, 0);
  };
  // 0-1 rest, 1-4 sweep, 4-5.6 swept (kept ones glow), 5.6-7 a new day: the folders come back
  const T = 7.2, rot = { x: 0, y: 0 };
  st.still = 4.6;
  st.frame = (t) => {
    const k = t % T;
    const bx = -4 + 8 * ease(clamp01((k - 1) / 3));
    beam.position.x = glow.position.x = bx;
    beamMat.opacity = glow.material.opacity = k > 0.8 && k < 4.2 ? 0.55 : 0;
    glow.material.opacity *= 0.3;
    tiles.forEach((o) => {
      const passed = k >= 1 && bx > o.x;
      const back = clamp01((k - 5.6) / 1.2);
      if (!o.k) {
        const d = passed ? ease(clamp01((bx - o.x) / 1.2)) : 0;
        const v = k >= 5.6 ? 1 - ease(back) : d;
        o.m.position.z = -v * 0.9; o.m.scale.setScalar(1 - v * 0.35); o.mat.opacity = 1 - v * 0.92;
      } else {
        const g = passed ? clamp01((bx - o.x) / 0.6) : 0;
        const v = k >= 5.6 ? 1 - ease(back) : g;
        o.mat.emissiveIntensity = v * 0.55; o.m.position.z = v * 0.12;
        o.halo.material.opacity = v * 0.9; o.halo.scale.setScalar(1 + Math.sin(t * 3) * 0.03 * v);
      }
    });
    const ty = touch ? Math.sin(t * 0.4) * 0.12 : pointer.x * 0.35;
    const tx = touch ? 0 : pointer.y * 0.15;
    rot.x += (tx - rot.x) * 0.05; rot.y += (ty - rot.y) * 0.05;
    board.rotation.set(-0.95 + rot.x, 0, rot.y * 0.6);
  };
  host.closest('.sweepviz').classList.add('has3d');
  st.start();
}

// ---------------------------------------------------------------- safe box
function mountSafeBox(host) {
  const st = stage(host, { fov: 28, envK: 0.6 });
  const { scene, camera } = st;
  lights(scene);
  const box = new THREE.Group(); scene.add(box);

  const shell = new THREE.MeshPhysicalMaterial({ color: 0x2b2f5c, metalness: 0.5, roughness: 0.3, clearcoat: 0.9, clearcoatRoughness: 0.2 });
  const W = 2.6, D = 1.8, H = 1.1, t = 0.1;
  // open tray: a floor and four walls
  const parts = [
    [W, t, D, 0, -H / 2, 0], [W, H, t, 0, 0, D / 2 - t / 2], [W, H, t, 0, 0, -D / 2 + t / 2],
    [t, H, D, W / 2 - t / 2, 0, 0], [t, H, D, -W / 2 + t / 2, 0, 0],
  ];
  parts.forEach(([w, h, d, x, y, z]) => {
    const m = new THREE.Mesh(new RoundedBoxGeometry(w, h, d, 2, 0.04), shell);
    m.position.set(x, y, z); box.add(m);
  });
  const rimMat = new THREE.MeshPhysicalMaterial({ color: 0x6366f1, metalness: 0.3, roughness: 0.2, clearcoat: 1, emissive: 0x6366f1, emissiveIntensity: 0.3 });
  const rim = new THREE.Mesh(new RoundedBoxGeometry(W + 0.04, 0.06, D + 0.04, 2, 0.03), rimMat);
  rim.position.y = H / 2; box.add(rim);

  // the lid hinges on the back edge
  const hinge = new THREE.Group(); hinge.position.set(0, H / 2 + 0.03, -D / 2); box.add(hinge);
  const lid = new THREE.Mesh(new RoundedBoxGeometry(W + 0.06, 0.14, D + 0.06, 3, 0.06), shell);
  lid.position.set(0, 0.05, D / 2); hinge.add(lid);
  const lidLine = new THREE.Mesh(new RoundedBoxGeometry(W * 0.7, 0.02, 0.06, 1, 0.01), rimMat);
  lidLine.position.set(0, 0.13, D / 2 + 0.2); hinge.add(lidLine);

  // the files: thin sheets with a coloured stripe
  const files = [];
  const cols = [0x22d3ee, 0xec4899, 0xf97316, 0x10b981];
  cols.forEach((c, i) => {
    const g = new THREE.Group();
    const paper = new THREE.Mesh(new RoundedBoxGeometry(0.9, 0.04, 1.15, 1, 0.02), new THREE.MeshPhysicalMaterial({ color: 0xf2f3ff, roughness: 0.4, clearcoat: 0.5 }));
    const strip = new THREE.Mesh(new THREE.BoxGeometry(0.9, 0.045, 0.22), new THREE.MeshPhysicalMaterial({ color: c, roughness: 0.3, emissive: c, emissiveIntensity: 0.2 }));
    strip.position.z = -0.42; g.add(paper, strip);
    g.userData = { x: (i - 1.5) * 0.52, z: (i % 2 ? 0.12 : -0.08), r: (i - 1.5) * 0.18, y0: -H / 2 + 0.1 + i * 0.05 };
    box.add(g); files.push(g);
  });

  // the padlock on the front
  const lock = new THREE.Group(); lock.position.set(0, -0.02, D / 2 + 0.12); box.add(lock);
  const lockMat = new THREE.MeshPhysicalMaterial({ color: 0xdfe3ff, metalness: 0.85, roughness: 0.18, emissive: 0x10b981, emissiveIntensity: 0 });
  const lb = new THREE.Mesh(new RoundedBoxGeometry(0.5, 0.42, 0.16, 3, 0.06), lockMat); lock.add(lb);
  const shackle = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.04, 12, 32, Math.PI), lockMat);
  shackle.position.y = 0.21; lock.add(shackle);
  const hole = new THREE.Mesh(new THREE.CircleGeometry(0.05, 20), new THREE.MeshBasicMaterial({ color: 0x1b1e3a }));
  hole.position.z = 0.081; lock.add(hole);

  st.fit = () => {
    camera.position.set(0, 3.2, 8.6 / Math.min(1, camera.aspect));
    camera.lookAt(0, 0, 0);
  };
  // 0-2.2 files drop in, 2.2-3 lid closes, 3-3.4 lock snaps, 3.4-5.6 closed, 5.6-7.6 open again
  const T = 8, rot = { x: 0, y: 0 };
  st.still = 4.4;
  st.frame = (tt) => {
    const k = tt % T;
    files.forEach((f, i) => {
      const s = clamp01((k - i * 0.4) / 0.8);
      const out = clamp01((k - 6.4) / 1.2);
      const d = ease(s) * (1 - ease(out));
      f.position.set(f.userData.x * (1 - d * 0.35), 2.4 - d * (2.4 - f.userData.y0), f.userData.z);
      f.rotation.set(0, f.userData.r, (1 - d) * 0.6 * (i % 2 ? 1 : -1));
    });
    const close = clamp01((k - 2.2) / 0.8), open = clamp01((k - 5.6) / 0.8);
    hinge.rotation.x = -(1 - ease(close) + ease(open)) * 1.75;
    if (k < 2.2) hinge.rotation.x = -1.75;
    const snap = clamp01((k - 3) / 0.4) * (1 - clamp01((k - 5.5) / 0.3));
    shackle.position.y = 0.21 + (1 - snap) * 0.12;
    lockMat.emissiveIntensity = snap * 0.5;
    rimMat.emissive.set(snap > 0.5 ? 0x10b981 : 0x6366f1);
    rimMat.emissiveIntensity = 0.3 + snap * 0.6;
    const ty = (touch ? Math.sin(tt * 0.5) * 0.25 : pointer.x * 0.8) - 0.35;
    const tx = touch ? 0 : pointer.y * 0.3;
    rot.x += (tx - rot.x) * 0.06; rot.y += (ty - rot.y) * 0.06;
    box.rotation.set(rot.x, rot.y, 0);
    box.position.y = Math.sin(tt * 0.9) * 0.05;
  };
  host.closest('.sbviz').classList.add('has3d');
  st.start();
}

if (hasWebGL()) {
  document.querySelectorAll('[data-win3d=sweep]').forEach((h) => { try { mountSweep(h); } catch (e) { /* the flat drawing stays */ } });
  document.querySelectorAll('[data-win3d=safebox]').forEach((h) => { try { mountSafeBox(h); } catch (e) { /* the flat drawing stays */ } });
}
