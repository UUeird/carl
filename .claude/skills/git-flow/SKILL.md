---
name: git-flow
description: "The branch lifecycle git workflow: branch before touching files, commit and PR proactively, push at feature boundaries, and clean up after a merge. Use whenever you start work, are ready to commit/push, open or update a PR, or a PR has merged."
---

A generic, repo-agnostic git workflow organized by the stages a branch moves
through. Not a single action — jump to the stage that matches where you are. A
repo that wants this flow copies this folder verbatim; that repo's `CLAUDE.md`
adds its own specifics (CI behavior, release process, versioning) and **wins for
the parts it names**.

## Starting work

- **Branch first — before any edit.** On the default branch, create a branch
  *before* the first Edit/Write/copy, not after `git status` reveals the problem.
  Never commit or push to the default branch directly.
- Name the branch for the change, not the ticket number alone.

## During work

- **Commit each coherent step. Push at feature boundaries**, not per commit.
- **Stage by path by default.** The working tree can hold someone else's
  uncommitted edits (the user's, or another session's), and `git commit -a`,
  `git add -A` or `git add .` commits them under your message. So `git add` the
  files you changed, and check `git diff --cached --stat` before you commit or
  amend. A sweep is fine when you're told to use one, or when you've checked
  that every change in the tree is yours.
- **Never push known-red.** If your change broke a test, fix it (or update the
  assertion) in the *same* commit.

## Opening and updating a PR

- **Commit and PR proactively** once a coherent change is complete and verified —
  don't wait to be asked.
- **Open as draft** (`gh pr create --draft`); `gh pr ready <number>` when it wants
  eyes. Draft lets you keep pushing without pulling a reviewer in.
- **Keep the PR body current** (`gh pr edit`) as work lands — don't let it keep
  describing only the first commit.
- **A PR may bundle related work.** Don't split purely for tidiness if the
  changes ship together, unless the repo's rules say one-concern-per-PR.

## After merge

Once the PR is merged and any deploy it triggered has succeeded:

```sh
git checkout main && git pull --ff-only
git branch -d <branch>
git push origin --delete <branch>
```

**Squash-merge caveat:** `git branch -d` may warn "not yet merged to HEAD" and
delete anyway — expected and safe, because the squashed commit isn't your
branch's commit. If it instead *refuses*, stop and find out why rather than
reaching for `-D`; that usually means commits exist that never landed.
