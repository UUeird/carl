# Roadmap — Agent instructions

When working in this repo, keep `roadmap.json` honest. These are the rules:

## When to update the roadmap

- **Finishing a roadmap item** → move its `status` to `"done"` and add a `note`
  describing what actually shipped (be specific — future agents read these).
- **Discovering a problem** → add a new item with `type: "bug"` and `status: "todo"`.
- **Starting work on something not yet tracked** → add it with `status: "wip"`.
- **Completing work that wasn't on the roadmap** → add it as `status: "done"`.

## What not to do

- Don't silently finish a roadmap item without updating its status.
- Don't add vague items. Every item needs a `title` that describes the outcome,
  not the activity ("Enemy health bars visible" not "Work on health bars").
- Don't change the `meta.version` or `meta.updated` fields — those are set by
  the human.

## Editing the file

After any edit, validate: `python3 -m json.tool roadmap/roadmap.json`

The schema is simple — see `README.md` for the full data model. The only
required fields on an item are `title`, `type`, and `status`.

## Types vs. status

- **Type** is the classification: `story` (feature work), `bug` (known issue).
- **Status** is the workflow state: `todo` (planned), `wip` (in progress),
  `done` (shipped), `idea` (under consideration).

These are independent. A `bug`-type item in active development has
`type: "bug", status: "wip"`. A shipped feature has `type: "story", status: "done"`.

## Live tracking: "roadmap feature upgrades"

The item titled **"roadmap feature upgrades"** (type: story, status: wip) tracks
work on the roadmap UI itself. As changes are made to `index.html`, `server.py`,
or the JSON schema, add a child bullet to that item describing what shipped.
Keep the children list in sync with what was actually done — not what was planned.
When all intended upgrades are complete, move the item to `status: "done"`.
