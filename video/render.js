// Render video Amnesia dari video/index.html, frame demi frame (timeline GSAP diam lalu dilompati,
// jadi setiap frame tepat). Butuh: node, paket npm "playwright" (Chromium), ffmpeg.
//
//   node render.js video <cut> <lang> <h|v> <out.mp4> [voiceover.m4a]
//   node render.js shots <cut> <lang> <h|v> <folder>        gambar tiap adegan (untuk storyboard)
//
// GSAP dimuat dari jsDelivr; kalau offline, isi GSAP_JS=/path/ke/gsap.min.js.
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs'), path = require('path');

const [mode, cut = '60', lang = 'en', ar = 'h', out = 'out', vo] = process.argv.slice(2);
const dir = __dirname, FPS = 30;
const W = ar === 'v' ? 1080 : 1920, H = ar === 'v' ? 1920 : 1080;
(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  if (process.env.GSAP_JS) await page.route(/gsap\.min\.js/, r => r.fulfill({ body: fs.readFileSync(process.env.GSAP_JS), contentType: 'application/javascript' }));
  const errs = []; page.on('pageerror', e => errs.push(e.message));
  await page.goto(`file://${path.join(dir, 'index.html')}?raw&cut=${cut}&lang=${lang}&ar=${ar}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.READY === true);
  await page.evaluate(() => document.fonts.ready);
  if (errs.length) { console.error(errs.join('\n')); process.exit(1); }
  const dur = await page.evaluate(() => window.DURATION);
  const seek = t => page.evaluate(t => { window.TL.seek(t, false); }, t);   // jangan kembalikan timeline (tidak bisa dikirim balik)

  if (mode === 'shots') {
    fs.mkdirSync(out, { recursive: true });
    const scenes = await page.evaluate(() => window.SCENES);
    // 2 gambar per adegan: di tengah dan menjelang akhir
    let n = 0;
    for (const s of scenes) for (const k of [.5, .9]) {
      const t = +(s.start + s.dur * k).toFixed(2);
      await seek(t);
      await page.screenshot({ path: path.join(out, `${String(++n).padStart(2, '0')}_${s.id}_${t}s.png`) });
    }
    console.log('shots', n, out);
  } else {
    const frames = Math.round(dur * FPS);
    const args = ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-'];
    if (vo) args.push('-i', vo, '-c:a', 'aac', '-b:a', '192k', '-shortest');
    args.push('-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '18', '-preset', 'slow', '-movflags', '+faststart', out);
    const ff = spawn('ffmpeg', args, { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let i = 0; i < frames; i++) {
      await seek(i / FPS);
      const buf = await page.screenshot({ type: 'png' });
      if (!ff.stdin.write(buf)) await new Promise(res => ff.stdin.once('drain', res));
      if (i % 300 === 0) console.log(`frame ${i}/${frames}`);
    }
    ff.stdin.end();
    await new Promise(res => ff.on('close', res));
    console.log('done', out, dur + 's');
  }
  await browser.close();
})();
