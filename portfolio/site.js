// The two views and the build log's status button. Nothing else: the kit runs the nav, motion and the moment.
const root = document.documentElement;
const reduce = matchMedia('(prefers-reduced-motion: reduce)');
const buttons = [...document.querySelectorAll('[data-mode-set]')];

function paint(view) {
  root.dataset.view = view;
  for (const b of buttons) b.setAttribute('aria-pressed', String(b.dataset.modeSet === view));
}

function setView(view, { scroll = true } = {}) {
  if (view === root.dataset.view) return;
  try { sessionStorage.setItem('view', view); } catch (e) { /* private mode: the choice lasts until reload */ }
  const swap = () => {
    paint(view);
    if (scroll && scrollY > innerHeight * 0.5) scrollTo({ top: 0, behavior: 'instant' });
    root.classList.add('is-rewriting');
    setTimeout(() => root.classList.remove('is-rewriting'), 420);
    window.dispatchEvent(new Event('resize'));   // the kit's moment re-measures its section
  };
  if (reduce.matches) return swap();
  root.classList.add('is-switching');
  setTimeout(() => { swap(); requestAnimationFrame(() => root.classList.remove('is-switching')); }, 160);
}

paint(root.dataset.view === 'dev' ? 'dev' : 'client');
for (const b of buttons) b.addEventListener('click', () => setView(b.dataset.modeSet));

// footer links that belong to the other view switch to it first
for (const a of document.querySelectorAll('[data-mode-link]')) {
  a.addEventListener('click', (e) => {
    const view = a.dataset.modeLink;
    if (view === root.dataset.view) return;
    e.preventDefault();
    setView(view, { scroll: false });
    setTimeout(() => document.querySelector(a.getAttribute('href'))?.scrollIntoView(), reduce.matches ? 0 : 200);
  });
}

// the status button opens the build log under the bar
const chip = document.querySelector('.status-chip');
const pop = document.getElementById('log-pop');
if (chip && pop) {
  const open = (on) => { pop.hidden = !on; chip.setAttribute('aria-expanded', String(on)); };
  chip.addEventListener('click', () => open(pop.hidden));
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !pop.hidden) { open(false); chip.focus(); } });
  document.addEventListener('click', (e) => { if (!pop.hidden && !pop.contains(e.target) && !chip.contains(e.target)) open(false); });
  addEventListener('scroll', () => { if (!pop.hidden && !pop.contains(document.activeElement)) open(false); }, { passive: true });
}
