// usage: node run.js <url> <out.png> <seconds> [actions.json]
const { chromium } = require('playwright');
(async () => {
  const [url, out, secs, actFile] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const logs = [];
  page.on('console', m => logs.push(m.text()));
  page.on('pageerror', e => logs.push('PAGEERROR ' + e.message));
  await page.goto(url);
  const acts = actFile ? JSON.parse(require('fs').readFileSync(actFile, 'utf8')) : [];
  let t0 = Date.now();
  await page.waitForTimeout(parseFloat(secs) * 1000);
  let n = 0;
  for (const a of acts) {
    if (a.wait) await page.waitForTimeout(a.wait);
    if (a.click) await page.mouse.click(a.click[0], a.click[1]);
    if (a.type) await page.keyboard.type(a.type, { delay: 30 });
    if (a.key) await page.keyboard.press(a.key);
    if (a.down) await page.keyboard.down(a.down);
    if (a.up) await page.keyboard.up(a.up);
    if (a.tap) { await page.touchscreen?.tap?.(a.tap[0], a.tap[1]).catch(() => page.mouse.click(a.tap[0], a.tap[1])); }
    if (a.shot) await page.screenshot({ path: a.shot });
  }
  await page.screenshot({ path: out });
  console.log(logs.join('\n'));
  await browser.close();
})();
