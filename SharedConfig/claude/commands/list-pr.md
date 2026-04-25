# List PR Builds

Show the current build/test leg status for an ADO pull request.

Usage: `/list-pr <PR-ID>`

The PR-ID is passed in `$ARGUMENTS`.

---

## Step 0 — Validate input and resolve watch-pr.cmd

Extract the PR ID from `$ARGUMENTS`. If it is missing or not a number, use `AskUserQuestion` to ask for it before proceeding.

Resolve the path to `watch-pr.cmd` using this priority order:

1. Check if it is on PATH:
   ```
   where watch-pr.cmd
   ```
   If found, note the path.

2. If not on PATH, check whether `$env:DEV_REPO` is set and whether `$env:DEV_REPO\Scripts\watch-pr.cmd` exists. If so, use that full path.

3. If neither resolves, stop and tell the user that `watch-pr.cmd` could not be found on PATH or via `$env:DEV_REPO`.

Store the resolved invocation (either `watch-pr.cmd` or the full path) as `WATCHPR` and use it for all subsequent calls in place of bare `watch-pr.cmd`.

---

## Step 1 — List leg status

Run:

```bash
"$WATCHPR" list <PR-ID>
```

Print the output to the user as-is. Do not summarize or reformat it.

Handle exit codes:

- **Exit 0** — all tracked gates succeeded. Report this to the user.
- **Exit 1** — at least one gate failed or was canceled. Report which ones.
- **Exit 2** — pending (some legs still in progress or not yet started). This is normal.
- **Exit 3** — no builds found at all for this PR. Report this to the user.
- **Exit 4** — API or auth error. Report the error to the user.

Stop after printing the output. Do not poll.
