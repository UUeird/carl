# carl — Roadmap

📋 **The roadmap is now an interactive page.** The content moved out of this markdown file
into a small HTML app backed by JSON.

- **Data (source of truth):** [roadmap/roadmap.json](roadmap/roadmap.json) — edit this to change
  the roadmap (flip statuses, add items, revise decisions).
- **Viewer:** [roadmap/index.html](roadmap/index.html) — dashboard stats, search, status
  filters, collapsible sections, the starred idea highlighted.

### Viewing & editing it

Run the small editor server (stdlib Python, no installs) from the repo root:

```
python3 roadmap/server.py
```

then open <http://localhost:8770/>. Editing in the page — add / edit / reorder / delete items,
change status or section, star an item — **saves straight to `roadmap/roadmap.json`** (atomic
write), so the data stays git-trackable. A save indicator confirms each change.

You can deep-link a filter with a hash, e.g. `http://localhost:8770/#idea` or `#done`.
Opening `index.html` without the server still works as a **read-only** viewer (editing disabled).

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

1. Build it; in the roadmap editor (or `roadmap.json` directly) move the item(s) from the
   `next` section to `completed` (status → Done), grouping related work under one titled item.
2. When ready to record a version, add a CHANGELOG entry (CalVer `YYYY.MM.DD`, `.N` for a
   second cut the same day), bump `Version.STRING` in [scripts/version.gd](scripts/version.gd)
   so the in-app overlay matches, and update `meta.version` / `meta.updated` in `roadmap.json`.
3. Commit: use the completed item's title as the subject and its bullets as the body.
