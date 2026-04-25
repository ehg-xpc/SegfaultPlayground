# Create PR from Staged Changes (Split Workflow)

Extracts staged changes into their own branch and PR, then returns to the original branch.
The staged changes are committed on the original branch first, then cherry-picked onto a clean split branch for the PR.
The unstaged remainder stays as-is to continue working on.

Follow these steps exactly. Do not skip ahead.

## Step 1 — Analyze

Run `git diff --cached --stat` to understand what is staged.
If nothing is staged, stop and tell the user — there is nothing to split off.

Resolve the user's alias by running `git config user.email` and taking the part before the `@`.

Identify the PR base branch by running `git remote show origin` or checking the repo's default branch (usually `master` or `main`).

## Step 2 — Propose and wait for approval

Use the `AskUserQuestion` tool to present:
- **Commit title** — one line, imperative mood, no project-name prefixes
- **Branch name** — format `user/<alias>/<short-feature-name>`, lowercase, hyphenated
- **PR base branch** — confirm the target branch (e.g. `master`)

and ask for approval before proceeding. Do not create any branch, do not commit, do not push, do not open any PR until the user approves. If the user requests changes, revise and ask again with `AskUserQuestion`.

## Step 3 — Execute (only after approval)

Once the user approves:

1. Note the current branch name — you will return here at the end.
2. `git commit -m "<title>\n\n<body>"` — commits only the staged changes on the current branch; body summarizes the why in 2-3 sentences.
3. Note the commit hash: `git rev-parse HEAD`.
4. `git checkout -b <branch> <base-branch>` — creates the split branch from the PR base (e.g. `master`), not from the current branch.
5. `git cherry-pick <commit-hash>` — applies the commit onto the clean split branch.
6. `git push -u origin <branch>`
7. Parse org, project, and repository from `git remote get-url origin`. ADO URL format: `https://dev.azure.com/{org}/{project}/_git/{repo}` (may also have a `{org}@` prefix before `dev.azure.com` — strip it). Create the PR:

```bash
az repos pr create \
  --title "<PR title>" \
  --description "$(cat <<'EOF'
## Why is this change being made?
<explain the motivation>

## What changed?
<summarize what was modified>

## Related Killswitch or Ramp IDs
| **Type** | **Name** | **ID** |
|----------|----------|--------|
| (fill in or remove table if not applicable) | | |
EOF
)" \
  --source-branch <branch> \
  --target-branch <base-branch> \
  --auto-complete \
  --delete-source-branch \
  --squash \
  --org https://dev.azure.com/<org> \
  --project <project> \
  --repository <repo>
```

8. `git checkout <original-branch>` — return to the original branch, which already has the commit and the unstaged remainder.

Report the PR URL/ID when done.
