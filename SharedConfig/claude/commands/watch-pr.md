# Watch PR

Monitor an ADO pull request's build/test legs and alert when any leg fails.

Usage: `/watch-pr <PR-ID>`

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

## Step 1 — Show current leg status

Run a one-shot snapshot so the user can see where things stand before polling begins:

```bash
"$WATCHPR" list <PR-ID>
```

Print the output to the user.

---

## Step 2 — Poll until a leg fails or all succeed

Start polling. This blocks until the first terminal outcome:

```bash
"$WATCHPR" poll <PR-ID> --until any --json
```

The command streams one JSON object per line per poll cycle. Read each line as it arrives. When the command exits, inspect the exit code:

- **Exit 0** — all watched legs succeeded. Report success to the user and stop.
- **Exit 1** — at least one leg failed or was canceled. Proceed to Step 3.
- **Exit 2** — timed out (unexpected here since no `--timeout` was passed). Report this to the user and stop.
- **Exit 3** — no builds found after 5 consecutive polls. Report this to the user and stop.
- **Exit 4** — API or auth error. Report the error to the user and stop.

---

## Step 3 — Report failure and ask what to do

Parse the final JSON line emitted before exit to identify which legs failed. Report clearly:

- Which leg(s) failed (name, result, URL)
- The current status of all other legs

Then use `AskUserQuestion` to ask the user what to do next. Present these options:

1. **fix** — investigate the failure, identify the root cause, and apply a fix if one is found without needing to escalate to you
2. **investigate** — fetch and analyze the build logs, identify the root cause, and report findings; no code changes, no commits
3. **retry** — re-queue the failed leg(s) and resume polling
4. **[anything else]** — the user may type a free-form instruction; carry it out as described

Wait for the user's answer before taking any action.

---

### If the user says "fix"

Fetch the build logs for each failed leg:

```bash
az pipelines build logs list --build-id <buildId> --org https://dev.azure.com/<org> --project <project>
```

Read the log content for each failed task. Focus on the first error — later errors are often cascading.

Investigate the root cause: read the relevant source files, use `Grep` and `Glob` to locate the failing code.

If the root cause is clear and a fix can be applied without escalating:
- Apply the minimal fix
- Never revert or weaken test assertions; fix the production code or test setup
- Commit and push, then return to Step 2 to resume polling

If the root cause is unclear or the fix would be risky, use `AskUserQuestion` to report your findings and ask for guidance before touching anything.

---

### If the user says "investigate"

Fetch the build logs for each failed leg:

```bash
az pipelines build logs list --build-id <buildId> --org https://dev.azure.com/<org> --project <project>
```

Read the log content for each failed task. Focus on the first error — later errors are often cascading.

Read the relevant source files. Use `Grep` and `Glob` to locate the failing code.

Report your findings to the user:
- The exact error(s) from the logs
- The likely root cause and the file(s) involved
- Your assessment of how complex the fix would be

Do not make any code changes. Do not commit anything. Stop after delivering the report.

---

### If the user says "retry"

Re-queue the failed legs:

```bash
"$WATCHPR" queue <PR-ID> --failed
```

Then return to Step 2 to resume polling.

---

### If the user provides a free-form instruction

Carry it out as described. Use your judgment. If the instruction is ambiguous, use `AskUserQuestion` to clarify before acting.
