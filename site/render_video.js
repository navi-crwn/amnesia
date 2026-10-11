// Renders site/video.html to an MP4, frame by frame (the GSAP timeline is paused and seeked,
// so every frame is exact). Needs: node, the "playwright" npm package with Chromium, ffmpeg.
// Usage: node render_video.js <folder with video.html, logo.png, screens/> <en|id> <out.mp4>
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('child_process');
const fs = require('fs'), path = require('path'), http = require('http');

const [dir, lang = 'en', out = 'intro.mp4'] = process.argv.slice(2);
const FPS = 30, W = 1920, H = 1080;
const exe = process.env.CHROMIUM || undefined;
const gsapFile = process.env.GSAP_JS;   // optional local copy of gsap.min.js (offline rendering)

const types = { '.html': 'text/html', '.png': 'image/png', '.js': 'application/javascript' };
const server = http.createServer((q, r) => {
  const f = path.join(dir, decodeURIComponent(q.url.split('?')[0]));
  if (!f.startsWith(path.resolve(dir)) || !fs.existsSync(f)) { r.writeHead(404); return r.end(); }
  r.writeHead(200, { 'content-type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(r);
}).listen(0);

(async () => {
  const port = server.address().port;
  const browser = await chromium.launch({ executablePath: exe });
  const page = await browser.newPage({ viewport: { width: W, height: H } });
  await page.route(/^https:\/\//, async r => {
    const u = r.request().url();
    if (gsapFile && u.includes('gsap.min.js')) return r.fulfill({ body: fs.readFileSync(gsapFile), contentType: 'application/javascript' });
    try { const body = execFileSync('curl', ['-sS', '-A', 'Mozilla/5.0 Chrome/120', u]); return r.fulfill({ body, contentType: u.includes('css2') ? 'text/css' : (u.endsWith('.js') ? 'application/javascript' : 'font/woff2') }); }
    catch (e) { return r.continue(); }
  });
  await page.goto(`http://127.0.0.1:${port}/video.html?lang=${lang}`, { waitUntil: 'networkidle' });
  await page.evaluate(() => document.fonts.ready);
  const dur = await page.evaluate(() => window.DURATION);
  const frames = Math.ceil(dur * FPS);
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-preset', 'slow', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let i = 0; i < frames; i++) {
    await page.evaluate(t => window.TL.seek(t, false), i / FPS);
    const buf = await page.screenshot({ type: 'png', clip: { x: 0, y: 0, width: W, height: H } });
    if (!ff.stdin.write(buf)) await new Promise(res => ff.stdin.once('drain', res));
    if (i % 150 === 0) console.log(`frame ${i}/${frames}`);
  }
  ff.stdin.end();
  await new Promise(res => ff.on('close', res));
  await browser.close(); server.close();
  console.log('done', out, dur.toFixed(1) + 's');
})();
