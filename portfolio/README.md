# Portfolio

A static, dependency-free personal site with two views: **Client** (the default on every new visit) and **Developer**.
The choice is kept for the browser session; `?view=developer` links straight to the developer view.

## Edit the content

Everything the page says is in `content.mjs`: name, contact links, the build log, projects, services, skills,
experience. Then rebuild:

```bash
node build.mjs      # writes index.html
```

- A field set to `null` (or an empty list) is left off the page. Nothing is shown that is not filled in.
- A project appears only with `public: true`. Add screenshots under `img/` as `name-640.webp` and `name-1280.webp`
  and list them in the project's `images`; until then the project shows its name set in type.
- `status.available` switches the status dot and wording; add a line to `status.log` when you ship something.

## Files

- `content.mjs` the words and data · `build.mjs` the template · `site.css` page styles · `site.js` the view switch
  and the build-log button · `assets/` the design kit (tasteskill) · `img/` screenshots.

Deploy the folder as is to any static host.
