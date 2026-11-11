---
name: tada
description: "The core build loop. Look at the carl board, pick up the next story marked In Progress, and start work on it — prioritizing any In Progress tasks within it."
---

The hosted board at `https://app.tada-ai.app/b/carl` is the source of truth
for priorities (CLAUDE.md, "Orient yourself first"). Always read the live
board.

1. **Read the live board.** Use the `tada` MCP `view_board` tool scoped to the
   columns this loop needs: `status: ["in-progress", "planned"]`. That keeps the
   output small (Idea/Done are the bulk) while still showing In Progress and the
   Planned fallback. Do **not** pass a `type` filter — In Progress items can be
   any type. If you later need the whole board, call `view_board` again with no
   `status`. The MCP tools are the read path; if they fail, check the setup
   steps in CLAUDE.md rather than reaching for a raw API.

2. **Find the In Progress story.**
   - If the In Progress column is **empty**, say so. Don't invent work — report
     what's in Planned and ask whether to pull one forward.
   - If there's exactly one, that's the story.
   - If there's more than one, pick the one at the top of the list.
   - **Skip any Story tagged `awaiting-release` ⏳** — its PR is open and it's
     waiting on a merge, not on work. If every In Progress Story carries the
     tag, say so and fall back to Planned as for an empty column.

3. **Pick what to work on within the story.**
   - If the story has any **tasks (subtasks) marked `in-progress`**, work those
     first.
   - Otherwise take the story as a whole (work its `todo`/`planned` subtasks in
     order). If the story has no subtasks, work the story itself. If a subtask
     looks too big for one session, ask for guidance before starting.
   - Use `get_story` for the full note — `view_board` only prints a preview.

4. **Mark it In Progress, then start.** Say which story (and subtask, if any)
   you're picking up. **Before beginning work**, move it into In Progress so the
   board reflects live state:
   - Working a **subtask**? `set_subtask_status … in-progress` for that subtask.
   - Working a **whole Story** that isn't already In Progress?
     `set_status … in-progress`.

   Then follow the repo workflow in CLAUDE.md and walk
   [`/change-feature`](../change-feature/SKILL.md) (plus
   [`/change-ui`](../change-ui/SKILL.md) for anything visible) before calling
   it done.

   **Verify:** `./run_tests.sh` must pass, and any visual/input/feel change
   needs a headed run + screenshot — headless can't prove it looks right.

5. **Move the ticket when done.** `set_subtask_status … done` for a subtask as
   soon as its work is finished; `set_status … done` for the whole Story when it
   ships, and update its note with what actually landed. If you leave something
   half-done or find a problem, add a `bug` or `chore` story.

Commit/push only when asked (CLAUDE.md) — see [`/git-flow`](../git-flow/SKILL.md)
for the branch lifecycle, and land it with [`/release`](../release/SKILL.md).
