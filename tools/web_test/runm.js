// mobile: node runm.js <url> <actions.json>   (iPhone-like portrait, touch taps)
const { chromium, devices } = require('playwright');
(async () => {
  const [url, actFile] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('console', m => { const t = m.text(); if (/SCRIPT|ERROR: [^C]/.test(t)) console.log(t); });
  await page.goto(url);
  await page.waitForTimeout(10000);
  for (const a of JSON.parse(require('fs').readFileSync(actFile, 'utf8'))) {
    if (a.wait) await page.waitForTimeout(a.wait);
    if (a.tap) await page.touchscreen.tap(a.tap[0], a.tap[1]);
    if (a.type) await page.keyboard.type(a.type, { delay: 30 });
    if (a.key) await page.keyboard.press(a.key);
    if (a.shot) await page.screenshot({ path: a.shot });
  }
  await browser.close();
})();
