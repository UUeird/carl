# carl — Roadmap

📋 **The roadmap is now an interactive page.** The content moved out of this markdown file
into a small HTML app backed by JSON.

- **Data (source of truth):** [roadmap/roadmap.json](roadmap/roadmap.json) — edit this to change
  the roadmap (flip statuses, add items, revise decisions).
- **Viewer:** [roadmap/index.html](roadmap/index.html) — dashboard stats, search, status
  filters, collapsible sections, the starred idea highlighted.

### Viewing it

The page loads `roadmap.json` via `fetch`, so it needs to be served (opening `index.html`
directly via `file://` is blocked by the browser). From the repo root:

```
cd roadmap && python3 -m http.server 8000
```

then open <http://localhost:8000/>. You can deep-link a filter with a hash, e.g.
`http://localhost:8000/#idea` or `#done`.

---

## How we work in this repo

- Controls + structure live in [README.md](README.md); the plan lives in
  [roadmap/roadmap.json](roadmap/roadmap.json); shipped changes are recorded in
  [CHANGELOG.md](CHANGELOG.md).
- One `.gd` per system in `scripts/`; reusable components (`health.gd`, `combat.gd`) are shared.
- Changes get verified before "done": headless for parse/logic, **headed screenshots** for
  anything visual or input-related (incl. browser screenshots for this roadmap page). Live
  mouse-feel still needs a human at the keyboard.

### Shipping a chunk of work

1. Build it; move the item(s) in `roadmap.json` from the `next` section to `completed`
   (set `"status": "done"`), grouping related work under one titled item.
2. When ready to record a version, add a CHANGELOG entry (CalVer `YYYY.MM.DD`, `.N` for a
   second cut the same day), bump `Version.STRING` in [scripts/version.gd](scripts/version.gd)
   so the in-app overlay matches, and update `meta.version` / `meta.updated` in `roadmap.json`.
3. Commit: use the completed item's title as the subject and its bullets as the body.
