# Push to origin/main

Squash-merge the current topic branch into main and push to origin. The current working directory must be inside a git worktree.

## Step 1 — Gather context

Run these in parallel:
- `git rev-parse --abbrev-ref HEAD` — current topic branch name
- `git worktree list --porcelain` — find the main worktree path
- `git log main..HEAD --oneline` (try `master` if `main` fails) — commits to be squashed
- `git diff main...HEAD --stat` (try `master` if `main` fails) — files changed
- `git status --short` — check for uncommitted changes

The main worktree is the first entry in `git worktree list --porcelain`. Use its path as `<main-repo-path>`.

Identify `<target-branch>`: whichever of `main` / `master` exists. Confirm by running `git -C <main-repo-path> symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` and stripping the `refs/remotes/origin/` prefix; fall back to checking `git -C <main-repo-path> rev-parse --verify main` then `master`.

If the working tree has uncommitted changes, warn the user — those will NOT be included.

## Step 2 — Propose and wait for approval

Use `AskUserQuestion` to present:
- Topic branch being merged
- Target branch
- Number of commits being squashed
- Proposed commit message (default: the description of the first commit, or the branch name slug humanized)

Ask the user to confirm or provide a different commit message. Do not proceed until approved.

## Step 3 — Execute (only after approval)

Run all git commands using the Bash tool, one per call (never `cd && git ...`).

**Important:** The sandbox may prevent `cd` to directories outside the current worktree (the shell resets the cwd). Use `git -C <main-repo-path>` for all commands instead of `cd`-ing first.

1. `git -C <main-repo-path> fetch origin <target-branch>` — ensure we have latest remote state
2. `git -C <main-repo-path> checkout <target-branch>` — switch main worktree to target
3. `git -C <main-repo-path> pull --ff-only origin <target-branch>` — fast-forward to latest
4. `git -C <main-repo-path> merge --squash <topic-branch>` — stage all changes as a single squash
5. `git -C <main-repo-path> commit -m "<approved-message>"` — create the squash commit
6. `git -C <main-repo-path> push origin <target-branch>` — push to remote

If any step fails (e.g. merge conflict, push rejection), stop immediately, report the error, and do NOT attempt cleanup. The user must resolve it manually.

## Step 4 — Report (only on success)

Do NOT remove the worktree directory or delete the topic branch — the session may still be running inside it.

Report the squash commit hash (`git -C <main-repo-path> rev-parse --short HEAD`) and confirm the merge has been pushed to `origin/<target-branch>`.
