/* The Amnesia logo in 3D (three.js): the gradient tile, the white shield with
   its keyhole cut through, and the three little dots drifting away (forgetting).
   It turns and tilts toward the cursor. Hero: plus a few floating glass shards.
   Phones: no cursor, a slow sway, fewer shards, lower resolution.
   Reduce motion: one still frame. No WebGL or the CDN fails: the flat logo stays. */
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

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

// ---------- shapes ----------
function roundedRect(w, h, r) {
  const s = new THREE.Shape(), x = -w / 2, y = -h / 2;
  s.moveTo(x + r, y);
  s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r);
  s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r);
  s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y);
  return s;
}
function shieldShape() {
  const s = new THREE.Shape();
  s.moveTo(0, 1.02);
  s.bezierCurveTo(0.3, 0.86, 0.58, 0.8, 0.84, 0.78);
  s.bezierCurveTo(0.86, 0.5, 0.86, 0.25, 0.84, 0.0);
  s.bezierCurveTo(0.8, -0.5, 0.42, -0.85, 0, -1.04);
  s.bezierCurveTo(-0.42, -0.85, -0.8, -0.5, -0.84, 0.0);
  s.bezierCurveTo(-0.86, 0.25, -0.86, 0.5, -0.84, 0.78);
  s.bezierCurveTo(-0.58, 0.8, -0.3, 0.86, 0, 1.02);
  // keyhole: a round top and a tapered stem, cut all the way through
  const r = 0.21, cy = 0.2, hw = 0.085;
  const yj = cy - Math.sqrt(r * r - hw * hw), a = Math.atan2(yj - cy, hw);
  const hole = new THREE.Path();
  hole.moveTo(hw, yj);
  hole.absarc(0, cy, r, a, Math.PI - a, false);
  hole.lineTo(-0.13, -0.42);
  hole.quadraticCurveTo(-0.13, -0.46, -0.09, -0.46);
  hole.lineTo(0.09, -0.46);
  hole.quadraticCurveTo(0.13, -0.46, 0.13, -0.42);
  hole.lineTo(hw, yj);
  s.holes.push(hole);
  return s;
}
// brand gradient baked into vertex colors: cyan top-left → indigo → pink bottom-right
function paint(geo, span) {
  const c1 = new THREE.Color('#22d3ee'), c2 = new THREE.Color('#6366f1'), c3 = new THREE.Color('#ec4899');
  const p = geo.attributes.position, col = new Float32Array(p.count * 3), c = new THREE.Color();
  for (let i = 0; i < p.count; i++) {
    let t = ((p.getX(i) - p.getY(i)) / (2 * span)) * 0.5 + 0.5;
    t = Math.min(1, Math.max(0, t));
    if (t < 0.5) c.copy(c1).lerp(c2, t * 2); else c.copy(c2).lerp(c3, (t - 0.5) * 2);
    col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
}

function mount(host) {
  const hero = host.dataset.shield3d === 'hero';
  const canvas = document.createElement('canvas');
  canvas.setAttribute('aria-hidden', 'true');
  host.appendChild(canvas);

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(devicePixelRatio || 1, touch ? 1.5 : 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 0.95;

  const scene = new THREE.Scene();
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
  scene.environmentIntensity = 0.45;
  pmrem.dispose();

  const camera = new THREE.PerspectiveCamera(28, 1, 0.1, 50);
  camera.position.set(0, 0, 10);

  const key = new THREE.DirectionalLight(0xffffff, 1.6); key.position.set(-3, 4, 6); scene.add(key);
  const cyan = new THREE.PointLight(0x22d3ee, 18, 12); cyan.position.set(-3, 1, 3); scene.add(cyan);
  const pink = new THREE.PointLight(0xec4899, 18, 12); pink.position.set(3, -2, 3); scene.add(pink);

  const logo = new THREE.Group();
  scene.add(logo);

  // the tile
  const tileGeo = new THREE.ExtrudeGeometry(roundedRect(2.7, 2.7, 0.62), { depth: 0.22, bevelEnabled: true, bevelThickness: 0.07, bevelSize: 0.07, bevelSegments: 6, curveSegments: 24 });
  tileGeo.center(); paint(tileGeo, 1.35);
  const tile = new THREE.Mesh(tileGeo, new THREE.MeshPhysicalMaterial({ vertexColors: true, roughness: 0.35, metalness: 0, clearcoat: 0.6, clearcoatRoughness: 0.2 }));
  logo.add(tile);

  // the shield, standing out in front of the tile
  const shGeo = new THREE.ExtrudeGeometry(shieldShape(), { depth: 0.24, bevelEnabled: true, bevelThickness: 0.08, bevelSize: 0.05, bevelSegments: 8, curveSegments: 48 });
  shGeo.center();
  const shield = new THREE.Mesh(shGeo, new THREE.MeshPhysicalMaterial({ color: 0xf6f7ff, roughness: 0.16, metalness: 0.05, clearcoat: 1, clearcoatRoughness: 0.06, sheen: 0.6, sheenColor: new THREE.Color('#a5b4fc'), iridescence: 0.3, iridescenceIOR: 1.3 }));
  shield.position.set(0, -0.04, 0.34);
  shield.scale.setScalar(0.92);
  logo.add(shield);

  // three dots, drifting away like a fading memory
  const dotMat = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.2, clearcoat: 1, transparent: true });
  const dots = [[0.98, 0.52, 0.075], [1.1, 0.7, 0.055], [1.18, 0.86, 0.04]].map(([x, y, r], i) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 24, 16), dotMat.clone());
    m.position.set(x, y, 0.26); m.userData = { x, y, ph: i * 0.33 };
    logo.add(m); return m;
  });

  // glass shards around the hero logo
  const shards = [];
  if (hero) {
    const geos = [new THREE.OctahedronGeometry(0.22), new THREE.TetrahedronGeometry(0.2), new THREE.IcosahedronGeometry(0.16)];
    const cols = ['#22d3ee', '#6366f1', '#ec4899', '#a78bfa', '#22d3ee', '#ec4899'];
    const spots = [[-1.9, 1.3, -0.4], [1.95, -1.15, 0.2], [-1.65, -1.4, 0.5], [1.8, 1.45, -0.6], [-2.15, 0.1, -0.9], [2.2, 0.25, 0.4]];
    spots.slice(0, touch ? 3 : 6).forEach(([x, y, z], i) => {
      const m = new THREE.Mesh(geos[i % 3], new THREE.MeshPhysicalMaterial({ color: new THREE.Color(cols[i]), roughness: 0.08, metalness: 0.2, clearcoat: 1, iridescence: 0.8, transparent: true, opacity: 0.88 }));
      m.position.set(x, y, z); m.userData = { x, y, z, s: 0.6 + Math.random() * 0.6, ph: Math.random() * 6 };
      scene.add(m); shards.push(m);
    });
  }

  function size() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    // keep the logo about two thirds of the box
    camera.position.z = (hero ? 9.2 : 8.4) / Math.min(1, camera.aspect);
    camera.updateProjectionMatrix();
  }
  size();
  if (window.ResizeObserver) new ResizeObserver(size).observe(canvas);

  const rot = { x: 0.12, y: -0.35 };
  logo.rotation.set(rot.x, rot.y, 0);
  const clock = new THREE.Clock();

  function frame() {
    const t = clock.getElapsedTime();
    const sway = Math.sin(t * 0.6) * 0.18;
    const tx = touch ? 0.12 + Math.sin(t * 0.45) * 0.08 : pointer.y * 0.6 + 0.1;
    const ty = touch ? -0.32 + sway : pointer.x * 1.1 + sway * 0.4 - 0.38;
    rot.x += (tx - rot.x) * 0.06; rot.y += (ty - rot.y) * 0.06;
    logo.rotation.set(rot.x, rot.y, rot.y * -0.08);
    logo.position.y = Math.sin(t * 0.9) * 0.06;
    cyan.position.x = -3 + pointer.x * 2; pink.position.y = -2 - pointer.y * 2;
    dots.forEach((d) => {
      const k = (t * 0.22 + d.userData.ph) % 1;
      d.position.set(d.userData.x + k * 0.35, d.userData.y + k * 0.42, 0.26 + k * 0.5);
      d.material.opacity = k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85;
    });
    shards.forEach((m) => {
      const u = m.userData;
      m.rotation.x = t * 0.4 * u.s + u.ph; m.rotation.y = t * 0.55 * u.s;
      m.position.set(u.x - pointer.x * 0.5 * (1 + u.z), u.y + Math.sin(t * u.s + u.ph) * 0.12 + pointer.y * 0.4, u.z);
    });
    renderer.render(scene, camera);
  }

  if (reduced) {
    frame();
    host.classList.add('live');
    return;
  }
  let on = false, raf = 0;
  function loop() { frame(); raf = requestAnimationFrame(loop); }
  function setOn(v) {
    if (v === on) return; on = v;
    if (on) { clock.start(); loop(); } else { cancelAnimationFrame(raf); clock.stop(); }
  }
  frame();
  host.classList.add('live');
  let inView = true;
  if (window.IntersectionObserver) {
    new IntersectionObserver((e) => { inView = e[0].isIntersecting; setOn(inView && !document.hidden); }, { rootMargin: '100px' }).observe(host);
  }
  document.addEventListener('visibilitychange', () => setOn(inView && !document.hidden));
  setOn(true);
}

if (hasWebGL()) {
  document.querySelectorAll('[data-shield3d]').forEach((h) => {
    try { mount(h); } catch (e) { /* the flat logo stays */ }
  });
}
