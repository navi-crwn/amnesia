// Membentuk musik latar per video dari lagu sumber (music/src-<skenario>.mp3), mengikuti adegan:
//  - tiap adegan punya "mood": volume + filter redam (lowpass) untuk bagian tegang, lalu terbuka saat cerita jalan
//  - adegan jeda (duh, goodkid) = musik berhenti mendadak, lalu masuk lagi
//  - adegan flash = efek "rewind" (potongan lagu diputar mundur, cepat)
//  - adegan penutup (cta) = bagian AKHIR asli lagu, dipasang supaya akord terakhirnya jatuh tepat di akhir video
//    (disambung pada ketukan yang sama supaya tidak terdengar loncat)
// Dipakai render.js:  buildMusic(cut, scenes, silence, total, outWav) -> true kalau berhasil
const { spawnSync } = require('child_process');
const fs = require('fs'), path = require('path');

const DIR = path.join(__dirname, 'music');
// sumber: file, tempo (bpm), ketukan pertama (detik), kapan akord terakhir selesai berbunyi (detik), mulai dari detik ke-
const SRC = {
  spy:     { bpm: 80.7,  beat0: 0.30, end: 53.8,  from: 0.30 },
  parents: { bpm: 89.1,  beat0: 0.21, end: 66.6,  from: 0.21 },
  borrow:  { bpm: 112.3, beat0: 0.60, end: 125.6, from: 0.60 },
};
// mood per adegan: v = volume relatif, lp = redam suara tinggi (Hz), stop = musik berhenti, rewind = efek putar mundur
const MOOD = {
  agent: { v: .75, lp: 1700 }, login: { v: .85, lp: 3800 }, empty: { v: .9 }, duh: { stop: 1 }, flash: { v: 1, rewind: .7 },
  parents: { v: .7, lp: 1500 }, savelo: { v: .9 }, tovault: { v: 1 }, parentlogin: { v: .85 }, goodkid: { stop: 1 },
  borrow: { v: .72, lp: 2000 }, busy: { v: .85 }, savevault: { v: 1 }, lend2: { v: .85 }, back: { v: 1 },
};
const OWNER = {
  agent: 'spy', login: 'spy', empty: 'spy', duh: 'spy', flash: 'spy',
  parents: 'parents', savelo: 'parents', tovault: 'parents', parentlogin: 'parents', goodkid: 'parents',
  borrow: 'borrow', busy: 'borrow', savevault: 'borrow', lend2: 'borrow', back: 'borrow',
};
const isCta = id => id.startsWith('cta');
// lagu penutup per versi: versi gabungan ditutup dengan lagu yang paling hangat
const ENDING = { all: 'borrow' };

function lufs(f) { // kekerasan suara rata-rata lagu, supaya ketiga lagu sama keras
  const r = spawnSync('ffmpeg', ['-hide_banner', '-nostats', '-i', f, '-af', 'ebur128', '-f', 'null', '-'], { encoding: 'utf8' });
  const m = [...r.stderr.matchAll(/I:\s+(-?[\d.]+) LUFS/g)].pop();
  return m ? +m[1] : -16;
}

function buildMusic(cut, scenes, silence, total, out, scenarioOf) {
  const file = n => path.join(DIR, `src-${n}.mp3`);
  const main = cut === 'all' ? null : scenarioOf(cut);
  const need = new Set(scenes.map(s => isCta(s.id) ? (ENDING[cut] || main) : OWNER[s.id] || main));
  for (const n of need) if (!fs.existsSync(file(n))) { console.warn(`! musik sumber belum ada: ${file(n)}`); return false; }
  const gain = {}; for (const n of need) gain[n] = Math.pow(10, (-16 - lufs(file(n))) / 20);

  const X = .03, pieces = []; // X = sambungan halus antar potongan
  const pos = {};              // posisi lagu (detik) yang sedang diputar per sumber
  let last = null;             // potongan terakhir yang berbunyi (untuk menyamakan ketukan penutup)
  for (const s of scenes) {
    const mood = { ...(MOOD[s.id] || {}) };
    if (silence.some(([a, b]) => s.start >= a - .01 && s.start < b)) mood.stop = 1;
    if (isCta(s.id)) {
      const n = ENDING[cut] || main, S = SRC[n], P = 60 / S.bpm;
      let from = S.end - s.dur;
      // ketukan disamakan: selisih posisi dengan potongan sebelumnya (lagu sama) dibulatkan ke kelipatan 1 ketukan
      if (last && last.n === n) from = last.srcEnd + Math.round((from - last.srcEnd) / P) * P;
      else from = S.beat0 + Math.round((from - S.beat0) / P) * P;
      pieces.push({ n, src: Math.max(0, from), at: s.start, dur: s.dur, v: 1.05, fadeIn: last && last.n === n ? .25 : .4 });
      last = null; continue;
    }
    const n = OWNER[s.id] || main, S = SRC[n];
    if (mood.stop) { last = null; continue; }
    if (pos[n] === undefined) pos[n] = S.from;
    let at = s.start, dur = s.dur;
    if (mood.rewind) { // potongan sebelumnya diputar mundur 2x lebih cepat
      pieces.push({ n, src: Math.max(0, pos[n] - mood.rewind * 2), at, dur: mood.rewind, v: .8, rev: 1, fadeIn: .05 });
      at += mood.rewind; dur -= mood.rewind;
    }
    const prevStopped = !last || last.n !== n || last.end < at - .05;
    pieces.push({ n, src: pos[n], at, dur, v: mood.v || 1, lp: mood.lp, fadeIn: prevStopped ? .12 : X });
    last = { n, end: at + dur, srcEnd: pos[n] + dur };
    pos[n] += dur;
  }
  // potongan yang diikuti jeda: berhenti cepat (seperti jarum piringan diangkat)
  for (let i = 0; i < pieces.length; i++) {
    const p = pieces[i], q = pieces[i + 1];
    p.cut = !q || q.at > p.at + p.dur + .05 ? .08 : 0;
  }
  const ins = [], parts = [], labels = [];
  pieces.forEach((p, i) => {
    ins.push('-i', file(p.n));
    const len = p.rev ? p.dur * 2 : p.dur + X;
    let f = `[${i}:a]atrim=${p.src.toFixed(4)}:${(p.src + len).toFixed(4)},asetpts=PTS-STARTPTS,aresample=44100,aformat=channel_layouts=stereo`;
    if (p.rev) f += `,areverse,asetrate=88200,aresample=44100`;
    if (p.lp) f += `,lowpass=f=${p.lp}`;
    f += `,volume=${(gain[p.n] * p.v).toFixed(4)}`;
    const d = p.rev ? p.dur : p.dur + X;
    f += `,afade=t=in:d=${p.fadeIn}`;
    if (p.cut) f += `,afade=t=out:st=${Math.max(0, p.dur - p.cut)}:d=${p.cut}`;
    else if (pieces[i + 1]) f += `,afade=t=out:st=${(d - X).toFixed(4)}:d=${X}`;
    const ms = Math.round(p.at * 1000);
    f += `,adelay=${ms}|${ms}[m${i}]`;
    parts.push(f); labels.push(`[m${i}]`);
  });
  parts.push(`${labels.join('')}amix=inputs=${labels.length}:normalize=0,apad=whole_dur=${total},atrim=0:${total}[out]`);
  const r = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', ...ins, '-filter_complex', parts.join(';'), '-map', '[out]', out], { stdio: 'inherit' });
  return r.status === 0;
}
module.exports = { buildMusic };
