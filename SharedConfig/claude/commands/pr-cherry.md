# Create PR from Local Commits (Cherry-Pick Workflow)

Cherry-picks one or more existing local commits from the current branch onto a clean topic branch and opens a PR.
The original branch is untouched — it already has those commits and you return to it at the end.

Follow these steps exactly. Do not skip ahead.

## Step 1 — Analyze

Resolve the user's alias by running `git config user.email` and taking the part before the `@`.

Identify the PR base branch by running `git remote show origin` or checking the repo's default branch (usually `master` or `main`).

Run `git log --oneline <base-branch>..HEAD` to list all local commits on the current branch that are ahead of the base.
Present this list to the user clearly (hash + subject).

## Step 2 — Ask user to select commits

Use the `AskUserQuestion` tool to ask which commits to include in the PR.
The user may specify by hash, subject, or range. Clarify if ambiguous.

If the user selects multiple commits, note the order — they will be cherry-picked in chronological order (oldest first).

## Step 3 — Propose and wait for approval

Use the `AskUserQuestion` tool to present:
- **Selected commits** — list the hashes + titles that will be cherry-picked
- **Branch name** — format `user/<alias>/<short-feature-name>`, lowercase, hyphenated
- **PR title** — one line, imperative mood, no project-name prefixes; synthesize from the selected commits if more than one
- **PR base branch** — confirm the target branch (e.g. `master`)

Do not create any branch, do not push, do not open any PR until the user approves. If the user requests changes, revise and ask again with `AskUserQuestion`.

## Step 4 — Execute (only after approval)

Once the user approves:

1. Note the current branch name — you will return here at the end.
2. `git checkout -b <branch> <base-branch>` — creates the topic branch from the PR base, not from the current branch.
3. `git cherry-pick <hash1> [<hash2> ...]` — apply the selected commits in chronological order.
   - If a cherry-pick conflict occurs, stop immediately, report the conflict to the user, and ask how to proceed. Do not attempt to resolve it automatically.
4. `git push -u origin <branch>`
5. Parse org, project, and repository from `git remote get-url origin`. ADO URL format: `https://dev.azure.com/{org}/{project}/_git/{repo}` (may also have a `{org}@` prefix before `dev.azure.com` — strip it). Create the PR:

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

6. `git checkout <original-branch>` — return to the original branch, which is unchanged.

Report the PR URL/ID when done.
