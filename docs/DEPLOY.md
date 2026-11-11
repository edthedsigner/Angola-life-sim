# Deploying: GitHub + Render (+ Neon for the database)

Result: one public link (`https://angola-life-sim.onrender.com`) that works on iPhone Safari and desktop browsers,
with everyone in the same server-authoritative world, and accounts and progress kept in PostgreSQL.

```
GitHub repo ──push──▶ GitHub Actions ──(tests + official Godot export)──▶ branch web-build ──▶ Render static site (client)
                                                                                     browser ──wss──▶ Render web service (server) ──▶ Neon PostgreSQL
```
Everything below is on free plans. Nothing here needs a payment method as far as the providers' docs say (Render
asks for one only to pay overages; check during sign-up).

## What is already in the repository
| File | What it does |
|---|---|
| `.github/workflows/build.yml` | **Server tests** with the real `websockets` package against files, SQLite **and a real PostgreSQL**. **Web export** with the official Godot 4.4.1 binaries and templates (downloaded inside GitHub's runner). A **browser smoke test** of the exported game: all scripts compile, and two clients (desktop plus an emulated iPhone) connect to a server at the same time. Then it **publishes** the build to the `web-build` branch |
| `.github/workflows/deploy-check.yml` | Run by hand after deploying. From the internet it checks the client files, `/healthz`, two simultaneous `wss` connections, and (optionally) two test players entering the same world and seeing each other move |
| `render.yaml` | Render Blueprint: the server (free web service, Frankfurt, health check `/healthz`) and the client (free static site serving `web-build`) |
| `export_presets.cfg` | Web preset **without threads** (works on iPhone Safari without special COOP/COEP headers), virtual keyboard on, GL Compatibility renderer |
| `server_python/storage.py` | Storage backends: `DATABASE_URL` → PostgreSQL; local files/SQLite for development |

### Server behaviour in production
* Listens on `$PORT` (set by Render). Render terminates TLS, so players connect with **`wss://`**.
* `GET /healthz` returns `ok`, and plain HTTP requests get a short text page instead of an error.
* **Refuses to start without `DATABASE_URL`** on Render (or whenever `ANGOLA_REQUIRE_DATABASE=1`), because Render's disk is wiped
  on every deploy, restart and spin-down. It won't pretend to persist data.
* Only changed documents are written, by one background writer, so a slow database never stalls the game. On SIGTERM
  (every Render deploy/restart) it finishes writing before exiting. If the database can't be read at startup the server exits
  instead of starting empty and overwriting your data.
* Optional env vars: `ANGOLA_ALLOWED_ORIGINS` (comma-separated, e.g. the client URL: other websites can't embed the game against
  your server), `ANGOLA_ICE_SERVERS` (TURN for voice calls, see `docs/SOCIAL.md`).

### Client: which server it connects to
`config/server.json` is written **at build time** from the GitHub variable `ANGOLA_SERVER_URL`. A page served over https always
uses `wss://`. Production builds ignore `?server=` links, so nobody can send players a link to a fake server that would
collect their passwords. Development builds without that file accept `?server=` and `--server=`.

## Steps (all doable from an iPhone)

### 1. GitHub
1. claude.ai → Settings → Connectors → **GitHub** → connect, and allow access to the repository below.
2. In the GitHub app or github.com: **+ → New repository** → name `angola-life-sim`, **private** is fine, no README.
3. Tell Claude `your-user/angola-life-sim`. Claude pushes the code, and the **Build** workflow runs its tests and the export
   (it doesn't publish yet, because the server address isn't known).

### 2. Database (Neon, free)
1. neon.com → sign up → **Create project** → region **AWS Europe Central (Frankfurt)** (same region as the server).
2. **Connect** → copy the connection string (`postgresql://…neon.tech/neondb?sslmode=require`). Use the **direct** one (not "pooled").
   Keep it private: it's the database password.
   (Free plan per Neon's docs: 1 GB storage and 100 compute-hours per month per project; compute pauses after 5 minutes idle
   and wakes on the next query. Limits pause the database, they don't delete data. Check neon.com/pricing.)

### 3. Render
1. render.com → **Sign in with GitHub** → allow Render to access the `angola-life-sim` repository.
2. **New → Blueprint** → choose the repository → paste the Neon string into `DATABASE_URL` → **Apply**.
3. The **server** deploys (2–3 min). The **static site fails the first time** because `web-build` doesn't exist yet. That's expected.
4. Open `https://angola-life-sim-server.onrender.com/healthz` → it must show `ok`. (If Render added a suffix to the name, use
   the URL shown on the service page.)

### 4. Connect client and server
1. GitHub repo → **Settings → Secrets and variables → Actions → Variables → New repository variable**:
   * `ANGOLA_SERVER_URL` = `wss://angola-life-sim-server.onrender.com`
   * `ANGOLA_CLIENT_URL` = `https://angola-life-sim.onrender.com`
2. **Actions → Build → Run workflow**. When it's green, the `web-build` branch exists and Render deploys the static site
   (or use **Manual Deploy** on the static site).
3. Optional hardening: Render → server → **Environment** → `ANGOLA_ALLOWED_ORIGINS` = `https://angola-life-sim.onrender.com`.
4. **Actions → Deploy check → Run workflow**. This is the real public verification. It leaves two accounts named `smoke_…`.
5. Open `https://angola-life-sim.onrender.com` on the iPhone (Safari). Share the same link with other players.
   Tip: Share → **Add to Home Screen** gives a full-screen icon.

Claude can do steps 1.3 and 4.1–4.4 once GitHub is connected with push access. Render can also be driven by Claude through
the Render connector if it's enabled in the chat.

## Free-plan behaviour to expect
* **Cold start:** the free server sleeps after 15 minutes without traffic and takes about a minute to wake. The game keeps retrying and
  connects by itself. Open WebSocket connections count as traffic, so it stays awake while people play.
* 750 free instance hours per month per Render workspace, enough for one server running all month.
* Upgrading later (no code changes): Render paid instance (no sleep), or any host that runs `python server_python/server.py`
  with `DATABASE_URL`.

## Moving existing local data
```bash
python server_python/storage.py copy file:server_python/data "postgresql://…"     # copies accounts, characters, social…
python server_python/storage.py info "postgresql://…"
```

## Not verified until the first real deployment
These were tested locally (see below) but can only be confirmed by the first run of the workflows on GitHub and a real phone:
* the official Godot 4.4.1 headless export of this project (the local tests used the same Godot 4.4.1 **no-threads** web
  runtime, with resources packed by `tools/web_test/build_pck.py`, not the official exporter);
* the server against the real `websockets` package and real PostgreSQL through `psycopg` (locally: a test stand-in for
  `websockets`, SQLite, and the PostgreSQL SQL statements run directly on a local PostgreSQL);
* Safari/WebKit on a real iPhone: the CI uses Chromium with the iPhone profile (screen, touch, user agent). The on-screen
  keyboard for login fields uses Godot's experimental virtual keyboard option, so check typing on the phone first.

Local verification done: 144 integration checks with file and SQLite storage, the production-start refusal, the SIGTERM flush,
URL rules (8 cases in the web runtime), and the browser smoke test (scripts compile, desktop plus emulated iPhone connected to the
same server at once). `tools/deploy_check.py --players` passed against a local server.
