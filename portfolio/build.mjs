// Builds index.html from content.mjs. No dependencies: `node build.mjs`.
import fs from 'node:fs';
import { site, contact, status, projects, services, skills, experience, exploring, about } from './content.mjs';

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const day = (iso) => { const [y, m, d] = iso.split('-').map(Number); return `${d} ${months[m - 1]} ${y}`; };
const short = (iso) => { const [, m, d] = iso.split('-').map(Number); return `${d} ${months[m - 1]}`; };
const arrow = '<svg class="m-arrow" viewBox="0 0 12 12" aria-hidden="true"><path class="m-arrow__stem" d="M1 6h8"/><path class="m-arrow__head" d="M4.5 2.5 8 6l-3.5 3.5"/></svg>';
const both = (o) => `<span data-only="client">${esc(o.client)}</span><span data-only="dev">${esc(o.dev)}</span>`;

const shown = projects.filter((p) => p.public);
const lead = shown.find((p) => p.images.length) ?? shown[0];
const rest = shown.filter((p) => p !== lead);
const email = contact.email ?? contact.emailStandIn;
const mailto = (subject) => `mailto:${email}?subject=${encodeURIComponent(subject)}`;
const START = 'Start a project';
const EMAIL = 'Email me';

const pic = (img, sizes, eager = false) => `<picture><source type="image/webp" srcset="${img.src}-640.webp 640w, ${img.src}-1280.webp 1280w" sizes="${sizes}"><img src="${img.src}-1280.webp" width="${img.w}" height="${img.h}" alt="${esc(img.alt)}" ${eager ? 'fetchpriority="high"' : 'loading="lazy" decoding="async"'} data-source="client" data-subject="${esc(img.alt)}"></picture>`;

// ---------- the build log (signature) ----------
const statusWord = status.available
  ? { client: 'Open to new projects', dev: 'Open to new projects and roles' }
  : { client: 'Booked for now', dev: 'Not taking new work' };

const buildLog = (id, compact = false) => `
<div class="blog${compact ? ' blog--compact' : ''}" ${id ? `id="${id}"` : ''} aria-label="Build log">
  <div class="blog__head">
    <span class="blog__title">build.log</span>
    <span class="blog__meta">updated <time datetime="${status.updated}">${day(status.updated)}</time></span>
  </div>
  <dl class="blog__state">
    <div><dt>status</dt><dd><span class="blog__dot${status.available ? '' : ' is-off'}" aria-hidden="true"></span>${both(statusWord)}</dd></div>
    <div><dt>building</dt><dd>${both(status.building)}</dd></div>
    <div><dt>focus</dt><dd>${both(status.focus)}</dd></div>
    <div><dt>latest</dt><dd>${both(status.latest)}</dd></div>
  </dl>
  <ol class="blog__log">
${status.log.map((e) => `    <li><time datetime="${e.date}">${short(e.date)}</time><span class="blog__line">${both(e)}</span><a class="blog__ref" data-only="dev" href="${contact.github}/Angola-life-sim/commit/${e.ref}" aria-label="Commit ${e.ref} on GitHub">${e.ref}</a></li>`).join('\n')}
  </ol>
</div>`;

// ---------- nav ----------
const navItem = (href, word, only) => `<div class="nav__item"${only ? ` data-only="${only}"` : ''}><a class="nav__link" href="${href}">${word}</a></div>`;
const modeSwitch = `
    <div class="mode" role="group" aria-label="Choose a view">
      <button type="button" class="mode__btn" data-mode-set="client" aria-pressed="true">Client</button>
      <button type="button" class="mode__btn" data-mode-set="dev" aria-pressed="false">Developer</button>
    </div>`;

const nav = `
<header class="nav nav--centre">
  <div class="wrap nav__bar">
    <a class="skip-link" href="#top">Skip to content</a>
    <div class="nav__brand">
      <a class="nav__logo" href="#top"><span class="mark" data-mark="stack" aria-hidden="true"></span>${esc(site.name)}</a>
      <button type="button" class="status-chip" aria-expanded="false" aria-controls="log-pop"><span class="blog__dot${status.available ? '' : ' is-off'}" aria-hidden="true"></span><span>${status.available ? 'Available' : 'Booked'}</span><span class="visually-hidden">: open the build log</span></button>
    </div>
    <nav class="nav__links" aria-label="Main">
      ${navItem('#work', 'Work', 'client')}
      ${navItem('#services', 'Services', 'client')}
      ${navItem('#projects', 'Projects', 'dev')}
      ${navItem('#skills', 'Skills', 'dev')}
      ${navItem('#experience', 'Experience', 'dev')}
      ${navItem('#about', 'About')}
    </nav>
    <div class="nav__actions">${modeSwitch}
      <a class="btn btn--primary" data-only="client" href="${mailto('New project')}">${START}</a>
      <a class="btn btn--primary" data-only="dev" href="${mailto('Hello from your portfolio')}">${EMAIL}</a>
    </div>
    <button class="nav__toggle" type="button" aria-expanded="false" aria-label="Menu">
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true"><path d="M2 5h14M2 13h14" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
    </button>
  </div>
  <div class="log-pop" id="log-pop" hidden>
    <div class="wrap">${buildLog(null, true)}</div>
  </div>
</header>`;

// ---------- client view ----------
const hero = `
  <section class="hero hero--split" data-enter aria-labelledby="hero-h">
    <div class="wrap"><div class="hero-text grid hero__grid">
      <div class="hero__text span-5">
        <h1 id="hero-h"><span data-only="client">Websites and web apps for businesses</span><span data-only="dev">Full-stack developer for web and games</span></h1>
        <p class="hero__lead"><span data-only="client">I’m an independent developer. I design and build websites, applications and online shops, and the software that runs behind them.</span><span data-only="dev">Python and JavaScript on servers and the web, Godot for games. My public code includes a multiplayer game whose server owns every rule.</span></p>
        <div class="btn-row" data-only="client"><a class="btn btn--primary" href="${mailto('New project')}">${START}${arrow}</a><a class="btn btn--secondary" href="#work">See selected work</a></div>
        <div class="btn-row" data-only="dev"><a class="btn btn--primary" href="${mailto('Hello from your portfolio')}">${EMAIL}${arrow}</a><a class="btn btn--secondary" href="${contact.github}">Read my code on GitHub</a></div>
      </div>
      <div class="hero__media hero__media--log span-6 start-7">${buildLog('log')}</div>
    </div></div>
  </section>`;

const cover = (p, i) => p.images.length
  ? `<div class="pframe">${pic(p.images[0], '(min-width: 1024px) 50vw, 100vw')}</div>`
  : `<div class="pframe cover cover--${i % 4}" role="img" aria-label="${esc(p.name)}"><span class="cover__cat">${esc(p.category)}</span><span class="cover__name">${esc(p.name)}</span></div>`;

const facts = (p) => {
  const rows = [];
  if (p.contribution) rows.push(['My part', esc(p.contribution)]);
  if (p.tech.length) rows.push(['Built with', esc(p.tech.slice(0, 4).join(', '))]);
  return rows.length ? `<dl class="pfacts">${rows.map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`).join('')}</dl>` : '';
};

const projectCard = (p, i, span) => `
          <article class="card card--open work-card ${span}">
            ${p.url ? `<a class="m-zoom" href="${p.url}" aria-label="Open ${esc(p.name)}">${cover(p, i)}</a>` : cover(p, i)}
            ${p.images.length ? `<p class="t-label muted work-card__cat">${esc(p.category)}</p>` : ''}
            <h3>${esc(p.name)}</h3>
            <p>${esc(p.summary)}</p>
            ${facts(p)}
            ${p.url ? `<a class="link" href="${p.url}">Open ${esc(p.name)}</a>` : ''}
          </article>`;

const spans = [['span-6', 'span-6 start-7'], ['span-6', 'span-6 start-7']];
const work = `
  <section class="section g2" id="work" data-only="client" aria-labelledby="work-h">
    <div class="wrap">
      <div class="group">
        <div class="section-head"><h2 id="work-h">Selected work. <span class="muted">${shown.length} projects, from shops to games.</span></h2></div>
        <div class="grid feature">
          <div class="feature__text span-5">
            <p class="t-label muted">${esc(lead.category)}</p>
            <h3 class="feature__name">${esc(lead.name)}</h3>
            <p>${esc(lead.summary)}</p>
            ${facts(lead)}
            ${lead.url ? `<a class="link" href="${lead.url}">Play it in the browser</a>` : ''}
          </div>
          <div class="feature__media span-6 start-7">${lead.url ? `<a class="m-zoom" href="${lead.url}" aria-label="Open ${esc(lead.name)}">` : ''}${pic(lead.images[0], '(min-width: 1024px) 58vw, 100vw')}${lead.url ? '</a>' : ''}</div>
        </div>
      </div>
      <div class="group">
${rest.map((p, i) => i % 2 === 0 ? `        <div class="grid work-row">${projectCard(p, i, spans[(i / 2) % 2][0])}${rest[i + 1] ? projectCard(rest[i + 1], i + 1, spans[(i / 2) % 2][1]) : ''}
        </div>` : '').join('\n')}
      </div>
    </div>
  </section>`;

const servicesSec = `
  <section class="section" id="services" data-only="client" aria-labelledby="services-h">
    <div class="wrap">
      <div class="section-head"><h2 id="services-h">Five kinds of work. <span class="muted">Each one designed, built and set up by me.</span></h2></div>
      <ol class="svc">
${services.map((s, i) => `        <li><span class="svc__n">0${i + 1}</span><h3 class="svc__name">${esc(s.name)}</h3><p>${esc(s.line)}</p></li>`).join('\n')}
      </ol>
    </div>
  </section>`;

// ---------- developer view ----------
const d = lead.dev;
const projectsSec = `
  <section class="section g2" id="projects" data-only="dev" aria-labelledby="projects-h">
    <div class="wrap">
      <div class="group">
        <div class="section-head"><h2 id="projects-h">${esc(lead.name)}. <span class="muted">${esc(lead.category)}, in the browser.</span></h2></div>
        <div class="grid">
          <div class="span-5 case">
            <h3 class="case__h">The problem</h3><p>${esc(d.problem)}</p>
            <h3 class="case__h">How it works</h3><p>${esc(d.architecture)}</p>
            <p class="case__links">${lead.repo ? `<a class="link" href="${lead.repo}">Read the repository</a>` : ''}${lead.url ? `<a class="link" href="${lead.url}">Play the live build</a>` : ''}</p>
          </div>
          <div class="case__media span-6 start-7">${pic(lead.images[1], '(min-width: 1024px) 50vw, 100vw')}</div>
        </div>
      </div>
      <div class="group">
        <div class="grid">
          <div class="span-5 case">
            <h3 class="case__h">Decisions</h3>
            <ul class="case__list">${d.decisions.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
            <h3 class="case__h">Hard parts</h3>
            <ul class="case__list">${d.challenges.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
          </div>
          <div class="span-6 start-7">
            <h3 class="case__h">Stack</h3>
            <p class="case__stack">${lead.tech.map((t) => `<span>${esc(t)}</span>`).join('')}</p>
            <h3 class="case__h">Other projects</h3>
            <ul class="rows other">
${rest.map((p) => `              <li><span class="rows__name">${esc(p.name)}<small>${esc(p.category)}</small></span>${p.repo ? `<a class="link rows__value" href="${p.repo}">Repository</a>` : p.url ? `<a class="link rows__value" href="${p.url}">Live site</a>` : ''}</li>`).join('\n')}
            </ul>
          </div>
        </div>
      </div>
    </div>
  </section>`;

const icon = (slug) => slug ? `<img class="sk__ic" src="assets/icons/logos/${slug}.svg" alt="" width="20" height="20" loading="lazy">` : '<span class="sk__ic sk__ic--none" aria-hidden="true"></span>';
const skillsSec = `
  <section class="section" id="skills" data-only="dev" aria-labelledby="skills-h">
    <div class="wrap">
      <div class="section-head"><h2 id="skills-h">Skills. <span class="muted">Only what my public code shows.</span></h2></div>
      <div class="grid sk">
${skills.filter((g) => g.items.length).map((g) => `        <div class="sk__group span-4"><h3 class="t-label muted">${esc(g.group)}</h3><ul>${g.items.map(([n, s]) => `<li>${icon(s)}${esc(n)}</li>`).join('')}</ul></div>`).join('\n')}
      </div>
    </div>
  </section>`;

const expSec = `
  <section class="section" id="experience" data-only="dev" aria-labelledby="experience-h">
    <div class="wrap">
      <div class="section-head"><h2 id="experience-h">Experience and current learning</h2></div>
      <div class="grid">
        <div class="span-5 explore">
          <ul class="rows exp">
${experience.map((e) => `            <li><span class="rows__name">${esc(e.role)}<small>${esc(e.where)}</small></span>${e.when ? `<span class="rows__value">${esc(e.when)}</span>` : ''}<p>${esc(e.line)}</p></li>`).join('\n')}
          </ul>
          <h3 class="t-label muted">Currently exploring</h3>
          <ul class="explore__list">${exploring.map((x) => `<li>${esc(x)}</li>`).join('')}</ul>
          <p class="explore__links"><a class="link" href="${contact.github}">My GitHub profile</a>${contact.linkedin ? `<a class="link" href="${contact.linkedin}">My LinkedIn profile</a>` : ''}</p>
        </div>
        <div class="case__media span-6 start-7">${pic(lead.images[2], '(min-width: 1024px) 50vw, 100vw')}</div>
      </div>
    </div>
  </section>`;

// ---------- shared ----------
const statementHtml = esc(about.statement).replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
const aboutSec = `
  <section class="section statement" id="about" data-moment="word-highlight" aria-labelledby="about-h">
    <div class="wrap">
      <h2 class="t-label" id="about-h">${esc(about.label)}</h2>
      <p class="mo-wh__text">${statementHtml}</p>
    </div>
  </section>`;

const contactLinks = [
  [`mailto:${email}`, 'Email'],
  contact.whatsapp && [`https://wa.me/${contact.whatsapp}`, 'WhatsApp'],
  contact.linkedin && [contact.linkedin, 'LinkedIn'],
  contact.github && [contact.github, 'GitHub'],
].filter(Boolean);

const footer = `
<footer class="footer closing footer--dark ground-inverse" id="contact" aria-labelledby="close-h">
  <div class="wrap">
    <div class="closing__cta close--type">
      <div class="section-head">
        <h2 id="close-h"><span data-only="client">Tell me about your project</span><span data-only="dev">Talk to me about a role</span></h2>
        <p class="t-small muted"><span data-only="client">Write what you need and by when. I reply with questions, then a plan and a price.</span><span data-only="dev">Interviews, contracts or a question about my code.</span></p>
      </div>
      <a class="btn btn--primary btn--xl" data-only="client" href="${mailto('New project')}">${START}${arrow}</a>
      <a class="btn btn--primary btn--xl" data-only="dev" href="${mailto('Hello from your portfolio')}">${EMAIL}${arrow}</a>
    </div>
    <div class="closing__links">
      <div class="grid">
        <div class="span-4 stack-4">
          <a class="nav__logo" href="#top"><span class="mark" data-mark="stack" aria-hidden="true"></span>${esc(site.name)}</a>
          <p class="footer__lede">Independent developer for websites, apps and games.</p>
        </div>
        <div class="span-2 start-7 footer__col"><h3>Client view</h3><ul><li><a href="#work" data-mode-link="client">Work</a></li><li><a href="#services" data-mode-link="client">Services</a></li></ul></div>
        <div class="span-2 footer__col"><h3>Developer view</h3><ul><li><a href="#projects" data-mode-link="dev">Projects</a></li><li><a href="#skills" data-mode-link="dev">Skills</a></li></ul></div>
        <div class="span-2 footer__col"><h3>Contact</h3><ul>${contactLinks.map(([h, t]) => `<li><a href="${h}">${t}</a></li>`).join('')}</ul></div>
      </div>
      <div class="footer__legal">
        <span>&copy; ${site.year} ${esc(site.name)}</span>
        <span>Product names and logos are trademarks of their owners</span>
      </div>
    </div>
  </div>
</footer>`;

const html = `<!doctype html>
<html lang="${site.lang}" data-type="service" data-radius="sharp" data-buttons="solid" data-motion>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(site.title)}</title>
<meta name="description" content="${esc(site.description)}">
<meta property="og:type" content="website">
<meta property="og:title" content="${esc(site.title)}">
<meta property="og:description" content="${esc(site.description)}">
<meta property="og:image" content="share.jpg">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<meta name="theme-color" content="#ffffff">
${site.domain ? `<link rel="canonical" href="${site.domain}/">` : '<!-- <link rel="canonical" href="https://[your domain]/"> -->'}
<meta name="site-kind" content="other">
<meta name="page-type" content="service">
<!-- generated by build.mjs from content.mjs: edit those, not this file -->
<script>
  // the view: client first on every new visit; a choice is kept for this browser session only
  (function () { var m = null; try { m = sessionStorage.getItem('view'); } catch (e) {}
    var q = new URLSearchParams(location.search).get('view'); if (q === 'developer') m = 'dev'; if (q === 'client') m = 'client';
    document.documentElement.dataset.view = m === 'dev' ? 'dev' : 'client'; })();
</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Newsreader:opsz,wght@6..72,400..700&family=Hanken+Grotesk:wght@400..600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="assets/system.css">
<link rel="stylesheet" href="assets/ui/cards.css">
<link rel="stylesheet" href="assets/motion/motion.css">
<link rel="stylesheet" href="assets/layout/layout.css">
<style>
:root {
  --p-bg: #ffffff; --p-surface: #f4f4f4; --p-ink: #111111; --p-muted: #6b6b6b;
  --p-accent: #1a4be0; --p-accent-ink: #ffffff; --p-action: #1a4be0; --p-action-ink: #ffffff;
  --p-inv-bg: #111111; --p-inv-surface: #1e1e1e; --p-inv-ink: #ffffff; --p-inv-muted: #9a9a9a;
  --p-inv-accent: #ffffff; --p-inv-accent-ink: #111111; --p-inv-action: #ffffff; --p-inv-action-ink: #111111;
  --font-display: "Newsreader", Georgia, serif;
  --font-text: "Hanken Grotesk", system-ui, sans-serif;
  --display-weight: 400;
  --display-tracking: -0.018em;
  --display-tracking-xl: -0.025em;
  --ly-scale: 1.06;
}
</style>
<link rel="stylesheet" href="site.css">
<script>document.documentElement.classList.add('m-enter');setTimeout(()=>document.documentElement.classList.add('m-enter-done'),700)</script>
<script>document.documentElement.classList.add('mo-js');setTimeout(()=>document.documentElement.classList.add('mo-safe'),2500)</script>
<link rel="modulepreload" href="assets/moments/moments.js">
<link rel="modulepreload" href="assets/moments/lib.js">
<link rel="modulepreload" href="assets/moments/word-highlight/moment.js">
</head>
<body>
<!-- type: service (an independent developer people hire)
     deal: hero split, nav nav-centre (nav-split re-dealt: it is made for places people visit), close close-type,
     footer footer-dark, rhythm surface-pairs, buttons solid, mark stack, palette white-link-blue
     (the brief asks for a white ground; the first palette was cool grey), type newsreader, radius sharp
     moments: word-highlight in #about
     signature: the build log, in the hero and behind the status button in the bar -->
${nav}

<main id="top">
${hero}
${work}
${projectsSec}
${servicesSec}
${skillsSec}
${expSec}
${aboutSec}
</main>
${footer}

<script type="module" src="assets/system.js"></script>
<script type="module" src="assets/motion/motion.js"></script>
<script type="module" src="assets/layout/layout.js"></script>
<script type="module" src="site.js"></script>
</body>
</html>
`;

fs.writeFileSync(new URL('./index.html', import.meta.url), html);
console.log('index.html written:', shown.length, 'projects,', html.length, 'bytes');
