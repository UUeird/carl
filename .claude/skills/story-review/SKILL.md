---
name: story-review
description: "Re-assess Stories on the carl board: is each one still relevant, valuable, coherent, distinct and ready to pick up? Sweeps Idea + Planned by default, or a named Story or lane (`/story-review carl-12`, `/story-review idea`). Reports one verdict per Story (keep, rewrite, split, merge, demote, delete) and writes to the board only what's approved."
---

A standing review of the *board*, not the code. [`/tada`](../tada/SKILL.md)
picks up the next Story; this asks whether each Story still deserves its place.
A board only works as a source of truth if what sits in Idea and Planned is
still true.

It is a **report-then-fix** loop: the verdicts come first, and nothing is
written to the board until the user approves it.

## Scope

| Invocation | Reviews |
| --- | --- |
| `/story-review` (default) | every Story in Idea and Planned |
| `/story-review idea` (or `planned`, `in-progress`) | that lane only |
| `/story-review carl-12` (or a title; several are fine) | just those Stories |

Say at the start of the run which scope it is.

**Out of scope by default:** Done (shipped work is the Changelog's business),
and any In Progress Story tagged `awaiting-release` ⏳. An In Progress Story is
reviewed only when named or when the lane is asked for, and then gently:
someone is mid-flight on it.

Reordering Stories within a lane is not part of this skill. Don't `move_story`
for priority here.

## Step 1 — Read the board

Use the `tada` MCP tools.

1. `view_board` scoped by `status` to the lanes in scope. Don't call it bare —
   the unscoped board is large.
2. `get_story` for each Story in scope: the note, Tasks, tags and links are
   what the rubric reads, and `view_board` prints only a preview.
3. For the overlap check, also read the *titles* of the lanes not in scope
   (`view_board` with their `status`), including In Progress. A Planned Story
   can duplicate one already being built.

On a large sweep, read in batches and keep only the facts the rubric needs.
Don't paste Story bodies back into chat.

## Step 2 — Assess each Story

Five questions. Answer each from evidence, not from the Story's own account of
itself.

- **Relevance: does the premise still hold?** A Story describes the game as it
  was when filed. Check the code it names: grep `scripts/`, `scenes/`, `test/`
  for the function, type, scene or behavior, and read enough to tell whether
  the problem still exists, was fixed in passing, or was made moot. Check
  [CHANGELOG.md](../../../CHANGELOG.md) and `view_changelog` too: it may have
  already shipped. Never skip this or answer it from memory.
- **Value: who notices if it ships?** Name the person (a player, someone
  changing carl) and what changes for them. No nameable beneficiary → candidate
  for demote or delete.
- **Coherence: is it one outcome?** Title, note and Tasks should describe the
  same thing. Signs it isn't: Tasks that would ship in unrelated PRs, a title
  that names one of several goals, a type (`feature` / `bug` / `chore` /
  `infrastructure`) that doesn't match the work, a bug titled by its fix
  instead of the observed problem.
- **Overlap: is it distinct?** Look for another Story with the same outcome, a
  Story this one is a subset of, or two that must ship together. A Story that
  **blocks** or is blocked by something already Done is stale in a fixable way.
- **Readiness: could an agent pick it up cold?** Only asked of Planned and In
  Progress (Idea may be vague). A ready Story says what done looks like and
  carries its units of work as Tasks, not as prose or a checklist in the note.

Before calling a Story stale, read `story_activity_log` when its state looks
odd (half-edited note, Tasks out of step with status). A recent human edit
means it's being worked on, not abandoned.

## Step 3 — Give each Story one verdict

Exactly one, the strongest that applies:

| Verdict | When | The write it implies |
| --- | --- | --- |
| **keep** | Passes all five. | none |
| **rewrite** | Sound, but title, note, type or Tasks misdescribe it or leave it unready. | `update_story`, `add_subtask` / `edit_subtask` / `delete_subtask` |
| **split** | More than one outcome. | `add_story` for each new Story, trim the original, `link_story` them |
| **merge** | Same outcome as another Story. Name the **primary**. | `merge_stories` |
| **demote** | Real but not ready or not worth doing soon. | `set_status … idea` |
| **delete** | The premise no longer holds, or it already shipped. | `delete_story` |

A Story that should be *linked* but is otherwise fine is a **keep** with a link
noted. A Story that turns out to be already built is a **delete** whose reason
cites the code or the Story that shipped it.

When unsure between two, pick the less destructive one and say what would tip
it. An Idea Story that is merely vague is a **keep**.

## Step 4 — Report

Lead with the counts (`12 reviewed: 7 keep, 2 rewrite, 1 merge, 2 delete`),
then one table, non-keeps first:

| Story | Verdict | Why | Proposed change |
| --- | --- | --- | --- |
| `carl-2` (Path tiles) | rewrite | work lives on another machine; no curved-tile code in `scripts/` | retitle + add "recover or recreate" Task |

- **Why** is one line and cites evidence: a `file:line`, a Story id, or what
  the grep did not find.
- **Proposed change** is concrete enough to approve as written.
- Keeps go in a single line of ids at the end.

Then stop and ask which changes to apply. Offer the non-destructive ones as a
group; list each **delete** and **merge** separately, since neither can be
undone from the board.

## Step 5 — Apply what's approved

- Apply only approved rows, one Story at a time, through the MCP tools.
- A **delete** or **merge** needs an explicit yes for that Story in this run.
  A blanket "apply them all" covers rewrites, splits and demotes only.
- A `StaleWriteError` means the Story changed since you read it. Re-read and
  re-check the verdict before retrying; don't force the write.
- A rewrite keeps what the Story already knows. Edit the note (`note_old` /
  `note_new` or `note_append`), don't replace it.
- A split's new Stories take the type and lane of the original unless the
  rubric says otherwise, and each carries its own Tasks.

Finish with what was written (ids and the change), and what was proposed but
left alone.

## What this skill doesn't do

- **No code changes.** If the relevance check finds a real bug with no Story,
  say so and offer to file it.
- **No status moves forward.** It never promotes a Story to Planned or In
  Progress; what to build next is the user's call and `/tada`'s job.
