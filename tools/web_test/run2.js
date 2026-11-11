// two independent clients: node run2.js <url> <actions.json>  (each action has "p":"A"|"B")
const { chromium } = require('playwright');
(async () => {
  const [url, actFile] = process.argv.slice(2);
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const pages = {};
  for (const k of ['A', 'B']) {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } });
    pages[k] = await ctx.newPage();
    pages[k].on('console', m => { const t = m.text(); if (/SCRIPT|ERROR: [^C]|\[Chat\]/.test(t)) console.log(k, t); });
    await pages[k].goto(url);
  }
  await pages.A.waitForTimeout(10000);
  for (const a of JSON.parse(require('fs').readFileSync(actFile, 'utf8'))) {
    const pg = pages[a.p || 'A'];
    if (a.wait) await pg.waitForTimeout(a.wait);
    if (a.click) await pg.mouse.click(a.click[0], a.click[1]);
    if (a.type) await pg.keyboard.type(a.type, { delay: 30 });
    if (a.key) await pg.keyboard.press(a.key);
    if (a.shot) await pg.screenshot({ path: a.shot });
  }
  await browser.close();
})();
