# carl — Roadmap

A lightweight kanban board for tracking work on the game. Data lives in
`roadmap.json`; the UI is a single-file app served by a tiny Python server.

## Running the server

```
python3 roadmap/server.py
```

Then open http://localhost:8770/ — edits save directly back to `roadmap.json`.

Without the server, opening `index.html` as a static file works read-only.

## Data model

`roadmap.json` has three top-level keys:

- **`meta`** — title, version, blurb, updated date.
- **`types`** — the classification buckets: `story`, `bug`, `ideas`.
- **`items`** — the actual cards. Each item has:
  - `title` (required)
  - `type` — one of the type ids above
  - `status` — `todo`, `wip`, `done`, or `idea`
  - `note` (optional) — one-line context
  - `children` (optional) — array of sub-item strings
  - `starred` (optional) — boolean, highlights the card

## Kanban columns

| Column | Status value |
|---|---|
| Idea | `idea` |
| Planned | `todo` |
| In Progress | `wip` |
| Done | `done` |

## Editing

Cards can be dragged between columns (changes `status`) or reordered within a
column. Use the ✎ button on a card to edit all fields. Changes auto-save to
`roadmap.json` via the server.
