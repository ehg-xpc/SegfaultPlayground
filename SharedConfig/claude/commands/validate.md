# Validate

Run project-appropriate validation checks defined in the harness.

Follow these steps exactly. Do not skip ahead.

## Step 1 -- Find harness.md

Determine the project name:

1. Read `CLAUDE.local.md` in the current working directory and look for a project name (often appears in paths like `~/.agent-context/{project}/`).
2. If not found, check the `~/.stanley/shared/` directory and match a symlink target against the current git repo root (`git rev-parse --show-toplevel`).
3. If still not found, use the final path segment of the git remote URL (`git remote get-url origin`).

Then check for harness.md at `~/.agent-context/{project}/harness.md`.

## Step 2 -- Handle missing harness

If no harness.md exists, or if `validationCommands` is absent or empty, stop and report:

> No validation commands configured. Skipping. (Pass)

Do not run anything. Exit cleanly.

## Step 3 -- Parse validationCommands

The `validationCommands` section in harness.md supports three entry formats:

```markdown
## validationCommands

- Label: command to run
- Another label: command --timeout 60
- command with no label
- Label (warn): command that is advisory only
```

Parsing rules:

- `Label: command` -- display `Label` in the report, run `command`.
- `command` (no colon) -- display the command itself as the label.
- `Label (warn): command` -- run as a warning-tier check; failure does not block overall pass.
- Optional `--timeout <seconds>` appended to the command line sets a per-command wall-clock
  limit. Strip the flag before running the command and enforce the timeout separately.
  Default timeout if absent: **300 seconds** (5 minutes).

Parse the list. If parsing fails, report the error and stop.

## Step 4 -- Run each command

Run each command sequentially using Bash. For each:

- Enforce the per-command timeout. If the command exceeds it, kill the process and record
  the result as `[TIMEOUT]` (treated as a failure for blocking checks; treated as a warning
  for warn-tier checks).
- Capture exit code, stdout, and stderr.
- Exit code 0 is **pass**; non-zero is **fail**.
- Do not stop early on failure -- run all commands even if one fails.

## Step 5 -- Report results

Print a summary table:

```
Validation Results
==================
[PASS] Build          npm run build
[FAIL] Tests          npm test --timeout 120
[WARN] Lint           npm run lint (warn)
[TIMEOUT] Slow check  uv run python slow_check.py --timeout 30

Result: 1 blocking check failed. 1 warning. 1 timeout.
```

Status codes:
- `[PASS]` -- exited 0
- `[FAIL]` -- exited non-zero (blocking tier)
- `[WARN]` -- exited non-zero (warn tier; does not block overall pass)
- `[TIMEOUT]` -- exceeded timeout

For each `[FAIL]` or `[TIMEOUT]` blocking command, print the last 20 lines of its combined
output below the table under a `--- <Label> output ---` heading. Skip this for warn-tier
failures to keep the report readable; they are shown in the table row only.

Overall result: **pass** if all blocking checks exited 0 (warnings and warn-tier failures do
not affect the overall result). **fail** if any blocking check failed or timed out.

If the overall result is **fail**, exit with a non-zero status to signal failure to the caller.
