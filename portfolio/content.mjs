// Everything the site says lives in this file. Edit it, then run `node build.mjs` to rebuild index.html.
//
// Rules this file keeps:
// - Nothing invented. A field set to null (or an empty list) is simply left off the page.
// - A project shows only when `public: true`.
// - Text in `client` fields is for business owners; text in `dev` fields is for developers and recruiters.

export const site = {
  name: 'edthedsigner',                     // TODO(owner): your real name or studio name
  initial: 'e',
  lang: 'en',
  domain: null,                             // e.g. 'https://example.com' — adds the canonical link when set
  year: 2026,
  title: 'edthedsigner: independent web developer for businesses',
  description: 'Websites, web applications, online shops and automation for businesses, designed and built by one independent developer.',
};

// Only real details. Unset ones are not shown.
export const contact = {
  email: null,                              // TODO(owner): your email; until then the buttons use the stand-in below
  emailStandIn: 'hello@edthedsigner.example',
  whatsapp: null,                           // TODO(owner): digits only with country code, e.g. '244900000000'
  linkedin: null,                           // TODO(owner): full profile URL
  github: 'https://github.com/edthedsigner',
};

// The build log: the site's signature panel. Newest entry first.
// `available` drives the status dot and wording. Entries come from real commits.
export const status = {
  available: true,                          // TODO(owner): confirm you are taking new projects
  updated: '2026-11-14',
  building: { client: 'Angola Life Simulator, a multiplayer life game set in Luanda', dev: 'Angola Life Simulator: Godot 4 client, Python WebSocket server' },
  focus: { client: 'Games and apps that work well on a phone', dev: 'Real-time multiplayer and mobile web exports' },
  latest: { client: 'A two-player noughts and crosses game inside the life sim', dev: 'Jogo do Galo: 1v1 minigame, turns validated on the server' },
  log: [
    { date: '2026-11-13', ref: '703cd81', client: 'Added a two-player minigame with invites and rematches', dev: 'Minigame: server-validated turns, invites, rematch' },
    { date: '2026-11-13', ref: '06d27fc', client: 'Players now get updates without clearing their browser', dev: 'Deploy: versioned game file names to bust the cache' },
    { date: '2026-11-13', ref: '8cee6a1', client: 'Redesigned the game screen with lighter floating panels', dev: 'UI: translucent floating panels across the HUD' },
    { date: '2026-11-13', ref: 'e47ba8b', client: 'Fixed phone pop-ups that opened off the screen', dev: 'Phone: sheets and alerts clamped to the viewport' },
    { date: '2026-11-12', ref: '33829a6', client: 'Redesigned the in-game phone to feel like a real one', dev: 'Phone UI: simpler navigation, iPhone-style sheets' },
    { date: '2026-11-11', ref: '24d1a22', client: 'Fixed players following each other by mistake', dev: 'Physics: separate collision layer for players' },
  ],
};

export const projects = [
  {
    id: 'angola-life-sim',
    public: true,
    name: 'Angola Life Simulator',
    category: 'Multiplayer game',
    summary: 'A life game set in Luanda that runs in the browser, on a phone too. Players rent rooms, find work, cook, call and message each other.',
    contribution: 'Design, client, server and deployment',
    tech: ['Godot 4', 'GDScript', 'Python', 'WebSockets', 'PostgreSQL', 'WebRTC', 'GitHub Actions', 'Render'],
    url: 'https://angola-life-sim.onrender.com',
    repo: 'https://github.com/edthedsigner/Angola-life-sim',
    images: [
      { src: 'img/ui_01_hud', w: 1280, h: 720, alt: 'Two players on an isometric street in the game, with the player card and the clock and money panel' },
      { src: 'img/galo_01_win_desktop', w: 1280, h: 720, alt: 'A finished game of noughts and crosses between two players, with a rematch button' },
      { src: 'img/social_07_dm_thread', w: 1280, h: 720, alt: 'The in-game phone open on a private message thread between two players' },
    ],
    dev: {
      problem: 'A persistent world many people share from a browser, including on iPhone Safari, where nobody can cheat by editing the client.',
      architecture: 'The Python server owns every rule: needs, money, jobs and minigame turns. The Godot client draws the world and sends intents over WebSockets. Accounts and progress live in PostgreSQL.',
      decisions: [
        'World geometry, buildings and furniture are data in one shared JSON file, read by both client and server.',
        'A web export without threads, so the game runs on iPhone Safari.',
        'Voice calls run peer to peer over WebRTC; the server only passes the signalling.',
      ],
      challenges: [
        'Keeping one true scale for walls, doors, furniture and people across every interior.',
        'Shipping updates to players without asking them to clear the cache.',
      ],
    },
  },
  {
    id: 'tudomix',
    public: true,                           // TODO(owner): confirm each project may be shown
    name: 'TudoMix',
    category: 'E-commerce and delivery',
    summary: 'An online shop with delivery.',
    contribution: null,                     // TODO(owner): your part, e.g. 'Design and full build'
    tech: [],
    url: null,
    repo: null,
    images: [],                             // TODO(owner): screenshots, e.g. { src: 'img/tudomix-home', w: 1280, h: 800, alt: '...' }
  },
  {
    id: 'imobgest',
    public: true,
    name: 'ImobGest',
    category: 'Real estate software',
    summary: 'Software for managing properties.',
    contribution: null,
    tech: [],
    url: null,
    repo: null,
    images: [],
  },
  {
    id: 'b-studio',
    public: true,
    name: 'B Studio',
    category: 'Web development studio',
    summary: 'Websites and digital work for clients.',
    contribution: null,
    tech: [],
    url: null,
    repo: null,
    images: [],
  },
  {
    id: 'cluck-dash',
    public: true,
    name: 'Cluck Dash',
    category: 'Game experiment',
    summary: 'An independent game made to learn game development.',
    contribution: null,
    tech: [],
    url: null,
    repo: null,
    images: [],
  },
];

export const services = [
  { name: 'Websites', line: 'A site that says what you do and works on every phone, built to load fast.' },
  { name: 'Web applications', line: 'Tools your team or your customers use in the browser: accounts, data, dashboards.' },
  { name: 'Online shops', line: 'Products, a cart, payments and delivery, set up so you can run it yourself.' },
  { name: 'Business automation', line: 'Repeated office work, such as copying orders or sending reminders, done by software.' },
  { name: 'Custom software', line: 'Something that does not fit the boxes above, planned with you before any code.' },
];

// Only technologies with public evidence. TODO(owner): add what else you have really used.
export const skills = [
  { group: 'Frontend', items: [['HTML', 'html-5'], ['CSS', 'css-3'], ['JavaScript', 'javascript']] },
  { group: 'Backend', items: [['Python', 'python'], ['WebSockets', 'websocket']] },
  { group: 'Databases', items: [['PostgreSQL', 'postgresql'], ['Neon', 'neon-icon'], ['SQLite', 'sqlite']] },
  { group: 'Tools and infrastructure', items: [['Git', 'git-icon'], ['GitHub Actions', 'github-actions'], ['Render', null]] },
  { group: 'Mobile', items: [['Touch controls and phone layouts for web games', null]] },
  { group: 'Other', items: [['Godot 4 and GDScript', 'godot-icon'], ['WebRTC', 'webrtc']] },
];

// TODO(owner): add roles with dates. Only what is true.
export const experience = [
  { role: 'Independent web developer', where: 'Self-employed', when: null, line: 'Websites, web applications and digital work for businesses.' },
  { role: 'Author and maintainer', where: 'Angola Life Simulator', when: '2026', line: 'Game design, the Godot client, the Python server, the database and the cloud build.' },
];

// TODO(owner): replace with what you are learning now.
export const exploring = [
  'Server-authoritative multiplayer',
  'Shipping games to iPhone Safari',
  'Peer-to-peer voice with WebRTC',
];

export const about = {
  label: 'About',
  // one statement of 12 to 40 words; the words inside ** ** turn to the accent
  statement: 'I build the whole thing: the screens people see, the server behind them and the setup that keeps it online. I would rather ship **one thing that works** than ten that almost do.',
};
