# Task Completion Receipt

When completing **any** task (regular, validation, or the session-mode leg of a planning
workflow), write a brief completion receipt before deleting the task file. This provides a
queryable record of what the agent did, even for tasks that never went through the planning
protocol.

## When This Rule Applies

Before deleting a task file on completion, write a receipt if **either**:
- The task file exists at `{tasksDir}/{taskId}.md` (regular/validation tasks), **or**
- The task is a session-mode child (tracked as a TodoWrite item, no file on disk).

For session-mode children, write one combined receipt for the whole session after all
tasks complete (see planning-protocol.md Step 7).

Planning tasks already write a receipt as part of their own protocol. This rule covers the
non-planning cases only.

## Receipt Location

```
{tasksDir}/receipts/{taskId}.md
```

If `{tasksDir}/receipts/` does not exist, create it before writing.

## Receipt Format

```markdown
## Receipt: <task title>
> taskId: <id>
> type: regular | validation
> completedAt: <ISO 8601 datetime>

### What Was Done

<One to three sentences summarizing what changed and why.>

### Files Changed

- `path/to/file.ext` -- one-line note on what changed
(omit if no files were changed)

### Commits

- `<short hash>` <commit message>
(omit if no commits were made)
```

Keep it short. The receipt is a reference record, not documentation. The goal is
answering "what did the agent do?" in a future conversation, not explaining the code.

## Write Sequence

1. Write the receipt at `{tasksDir}/receipts/{taskId}.md`.
2. Verify the file exists with `ls`.
3. Delete the task file at `{tasksDir}/{taskId}.md`.

If the receipt write fails, do not delete the task file. Report the error and stop.
