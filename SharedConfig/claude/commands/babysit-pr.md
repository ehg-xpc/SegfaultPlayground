---
description: Shepherd an ADO pull request through its build gates, investigating and fixing failures autonomously. Gates and retry limits are read from the project's harness.md; falls back to watching all gates in any order.
---

# Babysit PR

Shepherd an ADO pull request through its configured build gates, investigating and fixing
failures autonomously until all required checks are green or the retry limit is reached.

Usage: `/babysit-pr <PR-ID>`

The PR-ID is passed in `$ARGUMENTS`.

---

## Step 0 -- Validate input and resolve watch-pr.cmd

Extract the PR ID from `$ARGUMENTS`. If missing or not a number, use `AskUserQuestion` to
ask for it.

Resolve the path to `watch-pr.cmd`:

1. `where watch-pr.cmd` -- if found, use it.
2. If `$env:DEV_REPO` is set and `$env:DEV_REPO\Scripts\watch-pr.cmd` exists, use that.
3. Otherwise stop and tell the user `watch-pr.cmd` could not be found.

Store the resolved path as `WATCHPR`.

---

## Step 1 -- Load gate configuration

Check for `harness.md` in the current working directory (or repo root via
`git rev-parse --show-toplevel`).

If `harness.md` exists and contains a `buildGates` section, parse it:

```markdown
## buildGates

- name: Exact Pipeline Name 1
- name: Exact Pipeline Name 2
- name: Exact Pipeline Name 3
```

Gates are evaluated **in listed order**: gate N only starts after gate N-1 succeeds.

Also read:
- `maxAutoFixAttempts` (default: `3`) -- consecutive failures per gate before escalating.
- `taskTimeout` (default: none) -- wall-clock minutes before giving up entirely.

If no `buildGates` section exists, operate in **unordered mode**: watch all build legs
and fix any that fail, with no ordering constraint.

---

## Step 2 -- Show current status

```bash
"$WATCHPR" list <PR-ID> --json
```

Print a summary of current gate statuses for the user before polling begins.

---

## Step 3 -- Poll loop

Track:
- `consecutiveFailures[gateName]` counter for each gate, initialized to 0.
- `startedAt` timestamp if `taskTimeout` is configured.

Poll cycle:

```bash
"$WATCHPR" list <PR-ID> --json
```

Evaluate exit codes:
- **0 (all succeeded):** Report success and exit.
- **4 (API/auth error):** Report the error, use `AskUserQuestion` to ask retry or abort.
- **3 (no builds):** Wait 60 s, re-poll. If still empty after 5 retries, escalate.
- **1 or 2 (failure/timeout):** Proceed to evaluate gates.

If `taskTimeout` is set and `(now - startedAt) > taskTimeout`, escalate via
`AskUserQuestion` with a summary of what was attempted and exit.

For each gate (in configured order, or in any order if unordered mode):

| State | Action |
|-------|--------|
| `notFound` / `notStarted` / `inProgress` | Wait 60 s, re-poll. Do not skip ahead to later gates in ordered mode. |
| `succeeded` | Move to next gate (ordered mode) or mark done. |
| `failed` / `canceled` / `partiallySucceeded` | Enter fix loop (Step 4). |

---

## Step 4 -- Fix loop

When a gate fails, increment `consecutiveFailures[gateName]`. If it exceeds
`maxAutoFixAttempts`, escalate via `AskUserQuestion` with a summary of all attempted
fixes and stop.

### 4a -- Fetch build logs

```bash
az pipelines build logs list --build-id <buildId> --org https://dev.azure.com/<org> --project <project>
```

Read the log content for each failed task. Focus on the first error -- later errors are
usually cascading.

### 4b -- Investigate root cause

Read the relevant source files. Use `Grep` and `Glob` to locate the failing code.
Understand the error before touching anything.

Do not start fixing if the root cause is unclear. Use `AskUserQuestion` to report
findings and ask for guidance.

### 4c -- Fix the code

Apply the minimal fix:
- Fix compilation errors in production code -- no `#ifdef` workarounds, no disabling
  checks.
- **Never revert or weaken test assertions.** Fix the production code or test setup.
- Do not add workarounds that hide the underlying issue.

For test-only gates (e.g. unit/component tests): build and run the failing test(s)
locally before pushing to confirm the fix works.

### 4d -- Commit and push

```bash
git add <changed files>
git commit -m "<imperative-mood summary>"
git push
```

Use separate Bash calls -- never `cd && git ...`.

### 4e -- Wait for new runs

After pushing, wait **90 seconds** before polling to allow ADO to queue new builds.
Discard results from builds queued before the push timestamp.

### 4f -- Requeue if needed

If no new run appears after 3 poll cycles, requeue:

```bash
"$WATCHPR" queue <PR-ID> --leg "<exact pipeline name>"
```

Or to requeue all failed gates:

```bash
"$WATCHPR" queue <PR-ID> --failed
```

Then reset the poll cycle.

---

## Step 5 -- Report completion

When all gates succeed, report:
- PR ID
- Each gate name and final build ID
- Any fixes made (files changed, commit hashes)

Do not merge, complete, or abandon the PR. Your job ends when all required builds
are green.

---

## Constraints

- Poll interval: **60 seconds** between cycles.
- Never use `--no-verify` on commits.
- Never `cd && <command>` -- always use separate Bash calls.
- Never revert test assertions or disable checks to force green.
- Always verify the *new* build results, not stale pre-push results.
