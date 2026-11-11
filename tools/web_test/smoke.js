// Smoke test do EXPORT REAL (corre no GitHub Actions depois do `godot --export-release`).
// Uso: node smoke.js <url-da-pasta-do-build> <ws-do-servidor-local> <pasta-capturas> [url-esperado-em-produção]
//  1. --check-scripts: todos os scripts compilam no runtime exportado;
//  2. --selftest-net: regras do endereço do servidor;
//  3. dois clientes (desktop + iPhone emulado, toque) ligam-se ao MESMO servidor ao mesmo tempo;
//  4. a página "de produção" (sem argumentos) mostra o servidor configurado no build.
const { chromium, devices } = require('playwright');
const fs = require('fs');
const path = require('path');

const [base, ws, shots, expected] = process.argv.slice(2);
let failed = 0;
const check = (ok, name) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failed++; };

function variant(args, name) {
  // cópia do index.html com argumentos de linha de comando no GODOT_CONFIG
  const html = fs.readFileSync(path.join(process.env.BUILD_DIR, 'index.html'), 'utf8');
  const out = html.replace('"args":[]', '"args":' + JSON.stringify(args));
  if (out === html) throw new Error('GODOT_CONFIG "args":[] não encontrado no index.html exportado');
  fs.writeFileSync(path.join(process.env.BUILD_DIR, name), out);
  return `${base}/${name}`;
}

async function page(browser, url, opts, waitMs) {
  const ctx = await browser.newContext(opts);
  const p = await ctx.newPage();
  const lines = [];
  p.on('console', m => lines.push(m.text()));
  p.on('pageerror', e => lines.push('PAGEERROR ' + e.message));
  await p.goto(url);
  await p.waitForTimeout(waitMs);
  return { p, ctx, lines };
}

(async () => {
  fs.mkdirSync(shots, { recursive: true });
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader'] });
  const desktop = { viewport: { width: 1280, height: 720 } };

  const c = await page(browser, variant(['--check-scripts'], 'ci_check.html'), desktop, 25000);
  const ok = c.lines.filter(l => l.includes('[check] ok')).length;
  const bad = c.lines.filter(l => /\[check\] ERRO|SCRIPT ERROR|PAGEERROR/.test(l));
  check(ok >= 20 && bad.length === 0, `scripts compilam no export (${ok} ok, ${bad.length} erros)`);
  bad.forEach(l => console.log('   ' + l));
  await c.ctx.close();

  const s = await page(browser, variant(['--selftest-net'], 'ci_selftest.html'), desktop, 15000);
  const sok = s.lines.filter(l => l.startsWith('[selftest] ok')).length;
  check(sok >= 8 && !s.lines.some(l => l.startsWith('[selftest] FAIL')), `endereço do servidor: ${sok} casos ok`);
  await s.ctx.close();

  // Dois jogadores ao mesmo tempo, um deles num iPhone emulado (WebKit não está disponível no runner: Chromium com
  // o perfil do iPhone — ecrã, toque, user agent). O servidor local conta as ligações.
  const two = variant(['--', '--server=' + ws], 'ci_two.html');
  const [a, b] = await Promise.all([
    page(browser, two, desktop, 15000),
    page(browser, two, { ...devices['iPhone 13'] }, 15000),
  ]);
  for (const [k, x] of [['desktop', a], ['iphone', b]]) {
    const conn = x.lines.find(l => l.startsWith('[Client] Servidor:')) || '';
    check(conn.includes(ws), `${k}: cliente usa o servidor de teste (${conn})`);
    check(!x.lines.some(l => /SCRIPT ERROR|PAGEERROR/.test(l)), `${k}: sem erros de script`);
    await x.p.screenshot({ path: path.join(shots, `${k}.png`) });
  }
  await a.ctx.close(); await b.ctx.close();

  if (expected) {
    const prod = await page(browser, `${base}/index.html?server=ws://evil.example:1`, desktop, 12000);
    const line = prod.lines.find(l => l.startsWith('[Client] Servidor:')) || '';
    check(line.includes(expected), `produção: página aponta para ${expected} e ignora ?server= (${line})`);
    await prod.ctx.close();
  }
  await browser.close();
  for (const f of ['ci_check.html', 'ci_selftest.html', 'ci_two.html']) fs.rmSync(path.join(process.env.BUILD_DIR, f), { force: true });
  console.log(failed ? `\n${failed} falharam` : '\nsmoke OK');
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
