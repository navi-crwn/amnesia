// gambar contoh tiap adegan: node shots.js <cut> <h|v> <folder> [titik waktu per adegan, mis. .3,.7,.95]
const { chromium } = require('playwright'); const path = require('path'), fs = require('fs');
const [cut = '30', ar = 'h', out = 'shots', ks = '.35,.8'] = process.argv.slice(2);
const W = ar === 'v' ? 1080 : 1920, H = ar === 'v' ? 1920 : 1080;
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const p = await b.newPage({ viewport: { width: W, height: H } });
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
  await p.goto(`file://${path.join(__dirname, 'index.html')}?raw&cut=${cut}&ar=${ar}`);
  await p.waitForFunction(() => window.READY === true, null, { timeout: 20000 }).catch(() => {});
  if (errs.length) { console.error(errs.join('\n')); }
  await p.evaluate(() => document.fonts.ready);
  fs.mkdirSync(out, { recursive: true });
  const sc = await p.evaluate(() => window.SCENES); let n = 0;
  for (const s of sc) for (const k of ks.split(',').map(Number)) {
    const t = +(s.start + s.dur * k).toFixed(2);
    await p.evaluate(t => window.STEP_TO(t), t);
    await p.screenshot({ path: path.join(out, `${String(++n).padStart(2, '0')}_${s.id}_${t}s.png`) });
  }
  console.log('shots', n, errs.length ? 'ERR' : 'ok'); await b.close();
})();
