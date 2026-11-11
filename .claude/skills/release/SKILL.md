---
name: release
description: "Ship open carl work end to end: commit, PR, run the GUT suite (and headed visual checks) locally on the branch with main merged in, optionally cut a CalVer version, merge, clean up the branch, and update the carl board. With no args it releases every open PR in turn, one at a time. Pass a branch or PR number to release just that one. Use when the user says 'release', 'ship it', 'land this', or wants open branches merged and cleaned up."
---

Take open work from branch to merged and cleaned up. carl has **no CI and no
deploy**: the checks run here, locally, before the merge, and "released" means
merged to `main`, branch deleted, board updated. Invoking `/release` is the
user's go-ahead to commit and push (CLAUDE.md: commit/push only when asked).

**Hard rules**
- **Never merge red.** `./run_tests.sh` must end in `✅ all tests passed` on a
  tree that holds `main`'s current tip. Quote that line in the report; never
  infer a pass from the absence of a failure. A flaky-looking failure is red
  until a re-run passes.
- **Never merge a visual change unlooked-at.** If the diff changes anything a
  player sees or feels, the headed checks in step 4 must have run.
- **One PR at a time.** Each merge must see the previous one on `main`.
- **Never force-push, never `git branch -D`, never `--admin`.** If git refuses
  something, stop and ask.

## 1. Work out the scope

- `/release <branch>` or `/release <PR#>` → just that one.
- No args → every open PR (`gh pr list --json number,headRefName,baseRefName,title`),
  oldest first, except a **stacked** PR (base isn't `main`) goes right after the
  PR it's stacked on. Skip bot PRs unless the user names them.
- Check the current branch too (`git status`, `git log main..HEAD`). Commit
  uncommitted work you understand (ask if you don't — the tree can hold the
  user's own edits; stage by path per [`/git-flow`](../git-flow/SKILL.md)), and
  open a PR for a branch with commits but no PR. It's then in scope.
- **Version.** carl uses CalVer (`YYYY.MM.DD`, `.N` for a second cut that day;
  see the top of [CHANGELOG.md](../../../CHANGELOG.md)). Changes accumulate
  under `## Unreleased` across PRs, and a version is cut only sometimes. Ask once
  per run, in the same message as the order: "cut a version on the last PR, or
  leave it under Unreleased?" Default to leaving it if the user doesn't care.

Tell the user the PR order in one line before starting.

## 2. Sync and bring in `main`

1. `git switch main && git pull --ff-only`, then switch to the PR branch and
   `git pull --ff-only`.
2. Retarget a stacked PR whose base has just merged: `gh pr edit <n> --base main`.
3. `git merge --no-edit main`. On conflict, resolve it if the fix is obvious
   (keep both sides' intent), otherwise stop and ask. `.tscn`/`.import`
   conflicts are rarely obvious — ask.

## 3. Changelog (and version, if cutting one)

- The PR's user-visible changes should have an entry under `## Unreleased` in
  CHANGELOG.md (Added / Changed / Fixed). If missing, add it on the branch.
- **Cutting a version** (only on the PR the user picked, normally the last):
  rename `## Unreleased` to `## <today's CalVer>` (add `.2`, `.3`… if that date
  already has a heading), add a fresh empty `## Unreleased` above it, and set
  `config/version="<same>"` in [project.godot](../../../project.godot) — that is
  what the HUD's version label reads. Do this **before** the merge so the
  version ships in the commit that carries the change.
- Commit these on the branch.

## 4. Local checks on that tree

1. If the diff adds or regenerates a `.glb` or texture, import first or the
   tests/screenshots see stale assets:
   ```bash
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
   ```
2. The gate:
   ```bash
   ./run_tests.sh
   ```
3. **Visual changes** (anything under `scenes/`, `assets/`, HUD/VFX/mesh code,
   or a new `test/VISUAL_CHECKLIST.md` entry): run the matching checklist items
   headed — e.g. `Godot --path . --script test/shot_test_map.gd -- <scratchpad>/shot.png`
   — and read the PNG. Record pass/fail per item in the PR body.
4. **Red?** Fix it on the PR branch, re-run, commit, and restart this step. If
   the fix isn't clearly in scope for this PR, stop and ask.

Push, then refresh the PR body (`gh pr edit`) so it describes everything on the
branch, quotes the test verdict line, and lists the visual checks run.

## 5. Merge

Merge commits are the repo's convention. If another open PR is stacked on this
branch, retarget it first (`gh pr edit <stacked> --base main`) — deleting a
PR's base branch **closes** that PR. Then:

```bash
gh pr ready <n>            # if it's still a draft
gh pr merge <n> --merge --delete-branch
git switch main && git pull --ff-only && git branch -d <branch>
```

`-d`, not `-D`: if git refuses, the branch has commits that aren't on `main`.
Stop and report `git log main..<branch> --oneline`.

## 6. Board

Use the `tada` MCP tools. Find the story this PR advances (PR body, branch
name, or the closest match; ask if unclear). `get_story` first, then:

- Mark the subtasks this PR ships `done` (`set_subtask_status`).
- Move the Story to Done (`set_status … done`) **only if every subtask is
  done**, and update its note with what actually landed. Otherwise leave it In
  Progress and `note_append` a short line saying what landed.
- Drop an `awaiting-release` tag when the Story goes to Done (`update_story`
  with its tags minus that one).
- If something was left half-done or a problem turned up, add a `bug` or
  `chore` story.

## 7. Report

One line per PR: number, title, test verdict (quoted), visual checks run (or
"none — no visual change"), merged, branch deleted, board change. Then the
version cut (or "left under Unreleased"), and anything skipped or left behind
and why.
