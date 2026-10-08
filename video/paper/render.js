// Render video paper craft jadi MP4: gambar frame demi frame dari index.html + suara (Bill), efek suara dan musik.
//   node render.js <cut> <h|v> <out.mp4>          cut: 30 | 15 | p30 | b30 | all
// Butuh: node, paket npm "playwright" (Chromium), ffmpeg.
// Suara diambil dari:  ../vo2/<kalimat>-en.mp3   sfx/<efek>.mp3   music/<skenario>.mp3   (dibuat make_audio.py)
// File yang belum ada dilewati (video tetap jadi, hanya tanpa suara itu).
const { chromium } = require('playwright');
const { spawn, spawnSync } = require('child_process');
const fs = require('fs'), path = require('path'), os = require('os');

const [cut = '30', ar = 'h', out = `out/${cut}-${ar}.mp4`] = process.argv.slice(2);
const DIR = __dirname, W = ar === 'v' ? 1080 : 1920, H = ar === 'v' ? 1920 : 1080, OUT_FPS = 24;
const VO = path.join(DIR, '..', 'vo2'), SFX = path.join(DIR, 'sfx'), MUS = path.join(DIR, 'music');
const dur = f => +spawnSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).stdout.toString().trim();
{ // naskah selalu yang terbaru (disalin hanya kalau berubah, supaya gambar lama tetap bisa dipakai)
  const a = fs.readFileSync(path.join(DIR, '..', 'script.js')), bf = path.join(DIR, 'script.js');
  if (!fs.existsSync(bf) || !a.equals(fs.readFileSync(bf))) fs.writeFileSync(bf, a);
}

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto(`file://${path.join(DIR, 'index.html')}?raw&cut=${cut}&ar=${ar}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.READY === true);
  await page.evaluate(() => document.fonts.ready);
  if (errs.length) { console.error(errs.join('\n')); process.exit(1); }
  const info = await page.evaluate(() => ({ DUR: window.DURATION, STEP: 12, AUDIO: window.AUDIO, SFXQ: window.SFXQ, SILENCE: window.SILENCE, SCENES: window.SCENES }));
  const total = info.DUR, frames = Math.ceil(total * info.STEP);

  // 1) gambar: 12 gambar per detik (stop motion), disimpan sebagai video 24 fps tanpa suara di out/silent/.
  //    Kalau animasi (index.html, script.js) tidak berubah sejak render terakhir, gambar lama dipakai lagi (cepat).
  fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true });
  const silent = path.join(DIR, 'out', 'silent', `${cut}-${ar}.mp4`);
  fs.mkdirSync(path.dirname(silent), { recursive: true });
  const newest = Math.max(...['index.html', 'script.js', 'sound.js'].map(f => fs.statSync(path.join(DIR, f)).mtimeMs));
  if (!fs.existsSync(silent) || fs.statSync(silent).mtimeMs < newest || process.env.FRESH) {
    const tmpv = silent + '.part.mp4';
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(info.STEP), '-i', '-',
      '-r', String(OUT_FPS), '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '17', '-preset', 'slow', '-tune', 'animation', tmpv], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let i = 0; i < frames; i++) {
      await page.evaluate(t => window.STEP_TO(t), i / info.STEP);
      const buf = await page.screenshot({ type: 'jpeg', quality: 94 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 60 === 0) console.log(`${cut}-${ar} gambar ${i}/${frames}`);
    }
    ff.stdin.end(); await new Promise(r => ff.on('close', r));
    fs.renameSync(tmpv, silent);
  } else console.log('gambar lama dipakai lagi:', silent);
  await browser.close();
  const tmp = silent;

  // 2) suara
  const made = fs.existsSync(path.join(VO, 'made.json')) ? JSON.parse(fs.readFileSync(path.join(VO, 'made.json'), 'utf8')) : null;
  global.window = {}; require(path.join(DIR, 'script.js')); require(path.join(DIR, 'sound.js'));
  const S = window.SCRIPT, SOUND = window.SOUND;
  const ins = ['-i', tmp], parts = [], vo = [], fx = [];
  const add = f => { ins.push('-i', f); return ins.filter(x => x === '-i').length - 1; };
  for (const a of info.AUDIO) {
    const f = path.join(VO, `${a.line}-en.mp3`);
    if (!fs.existsSync(f) || (made && (made[`${a.line}-en.mp3`] || {}).text !== S.lines[a.line].en)) { console.warn(`! suara belum ada / belum sesuai naskah: ${a.line}`); continue; }
    // kalimat sedikit kepanjangan (maks 10%): dipercepat halus supaya tidak terpotong, nada suara tetap
    const d = dur(f), tempo = d > a.max ? Math.min(1.1, d / a.max) : 1;
    if (d > a.max) console.warn(`! ${a.line} ${d.toFixed(2)}s lebih panjang dari adegannya (${a.max}s)` + (tempo > 1 ? `, dipercepat ${tempo.toFixed(3)}x` : ''));
    const k = add(f), ms = Math.round(a.at * 1000);
    parts.push(`[${k}:a]aresample=44100,aformat=channel_layouts=stereo${tempo > 1 ? `,atempo=${tempo.toFixed(4)}` : ''},adelay=${ms}|${ms}[v${k}]`); vo.push(`[v${k}]`);
  }
  for (const s of info.SFXQ) {
    const f = path.join(SFX, `${s.id}.mp3`);
    if (!fs.existsSync(f)) continue;
    const k = add(f), ms = Math.max(0, Math.round(s.at * 1000));
    parts.push(`[${k}:a]aresample=44100,aformat=channel_layouts=stereo,volume=${(s.gain * .5).toFixed(2)},adelay=${ms}|${ms}[f${k}]`); fx.push(`[f${k}]`);
  }
  // musik: dibentuk per adegan dari lagu sumber (music.js); kalau tidak ada, pakai music/<skenario>.mp3 apa adanya
  const scen = cut === 'all' ? 'all' : SOUND.scenario(cut);
  let mf = path.join(MUS, `${scen}.mp3`), shaped = false;
  const built = path.join(DIR, 'out', 'music', `${cut}.wav`);
  fs.mkdirSync(path.dirname(built), { recursive: true });
  if (require('./music.js').buildMusic(cut, info.SCENES, info.SILENCE, total, built, SOUND.scenario)) { mf = built; shaped = true; }
  const hasMusic = fs.existsSync(mf);
  if (!vo.length && !fx.length && !hasMusic) { fs.copyFileSync(tmp, out); console.log('selesai (tanpa suara)', out); return; }
  const pad = `apad=whole_dur=${total}`;
  parts.push(vo.length ? `${vo.join('')}amix=inputs=${vo.length}:normalize=0,${pad}[vo]` : `anullsrc=r=44100:cl=stereo,atrim=0:${total}[vo]`);
  parts.push(fx.length ? `${fx.join('')}amix=inputs=${fx.length}:normalize=0,${pad}[fx]` : `anullsrc=r=44100:cl=stereo,atrim=0:${total}[fx]`);
  if (hasMusic) {
    const m = add(mf);
    const mute = info.SILENCE.map(([a, b]) => `,volume=0.08:enable='between(t,${a + .15},${b - .1})'`).join('');
    parts.push(`[${m}:a]aresample=44100,aformat=channel_layouts=stereo,atrim=0:${total},volume=0.30${shaped ? '' : mute},afade=t=in:d=0.6,afade=t=out:st=${Math.max(0, total - (shaped ? .5 : 2))}:d=${shaped ? .5 : 2},${pad}[mu]`,
      `[vo]asplit[vo1][vo2]`, `[mu][vo1]sidechaincompress=threshold=0.03:ratio=7:attack=20:release=400[duck]`,
      `[duck][vo2][fx]amix=inputs=3:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.84:level=disabled[a]`);
  } else parts.push(`[vo][fx]amix=inputs=2:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,alimiter=limit=0.84:level=disabled[a]`);
  const r = spawnSync('ffmpeg', ['-y', '-loglevel', 'error', ...ins, '-filter_complex', parts.join(';'), '-map', '0:v', '-map', '[a]',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', String(total), '-movflags', '+faststart', out], { stdio: 'inherit' });
  if (r.status) process.exit(r.status);
  console.log('selesai', out, total + 's', `suara ${vo.length}/${info.AUDIO.length}, efek ${fx.length}/${info.SFXQ.length}${hasMusic ? ', musik' : ''}`);
})();
