---
description: Run the planning protocol for a vague or multi-task request. Decomposes the request into a structured plan, waits for approval, then creates child task files.
---

# Plan

Run the full planning protocol for a request. Produces a structured plan between markers, waits
for approval, then creates child task files. Single-task requests may skip planning entirely when
the project policy allows it.

Follow these steps exactly. Do not skip ahead.

## Step 1 -- Determine project name and policy

Derive the project name from the current repo root (the last path segment, e.g. `MyRepo`).
If unclear, ask the user.

Check `~/.agent-context/{project}/harness.md` for a `planningRequired` field:

| Value | Meaning |
|-------|---------|
| `always` | Always plan, even for single tasks |
| `multi-task` | Plan only when the request involves multiple tasks; skip for single tasks |
| `auto` (default) | Plan when the request is vague or involves multiple tasks |
| `never` | Skip planning for single, well-defined tasks |

If the file does not exist or the field is absent, treat it as `auto`.

**Skip condition:** if `planningRequired` is `never`; or `auto` and the request is clearly a
single, self-contained task with no ambiguity; or `multi-task` and the request is a single
task -- stop here and execute the task directly without planning. Otherwise continue.

## Step 2 -- Locate or create the planning task file

Determine the task storage root:

1. If `~/.stanley/tasks/{project}/` exists, use it.
2. Otherwise use `~/.agent-context/tasks/{project}/`.

Call this `{tasksDir}`.

If the user invoked `/plan` from within an already-filed planning task, read that file to extract
`parentId` and the original request description, then skip to Step 3.

**Duplicate detection:** before creating a new file, scan all `.md` files in `{tasksDir}/`
(excluding `receipts/`). If any file's one-sentence description or title closely overlaps the
current request (same feature area, same keywords), surface the match to the user:

> Found existing task `<id>` that may cover the same work: "<description>". Continue with a
> new planning task, or resume the existing one?

If the user says to resume, read the existing task and skip to Step 3. If the user says to
continue, proceed with a new task file (choose a non-conflicting `parentId`).

Otherwise, create the planning task file now:

- Generate a `parentId` in kebab-case from the request (e.g. `add-export-pipeline`).
- Write `{tasksDir}/{parentId}.md`:

```markdown
## <Title derived from request>
> id: <parentId>
> type: planning
> priority: medium
> status: in-progress

<One-sentence description of the request.>
```

After writing, verify the file exists with `ls`. If it is missing, use the Python fallback in
CLAUDE.local.md to write it, then verify again before continuing.

## Step 3 -- Enter read-only decomposition phase

Emit on its own line:

```
[STANLEY:PLANNING_START]
```

From this point until `[STANLEY:PLAN_APPROVED]`, operate in **read-only mode**. Permitted:
reading files, searching code, fetching docs. Forbidden: writing files, creating commits,
installing packages, or modifying any state.

Research the request. Understand the affected areas of the codebase, the likely subtasks, and
dependencies between them.

## Step 4 -- Emit the structured plan

Output the plan immediately after research:

```
[PLAN_START]
## Plan: <title>

### Summary
One paragraph describing the overall approach.

### Tasks
| ID | Description | Complexity |
|----|-------------|------------|
| <child-id-1> | <one-line description> | low \| medium \| high |
| <child-id-2> | <one-line description> | low \| medium \| high |

### Dependencies
- <child-id-2> depends on <child-id-1>
(omit this section entirely if there are no dependencies)

### Workflow Mode
`session` | `worktree` -- one-line rationale
[PLAN_END]
```

Rules for task IDs: kebab-case, unique within this plan, descriptive. They become child task
filenames.

**Assigning complexity:** assess each task during research based on scope:
- `low` -- config-only changes, single file, no logic added.
- `medium` -- cross-file refactor, new feature in an existing module, or moderate test work.
- `high` -- new subsystem, protocol/schema change, cross-project dependency, or significant
  uncertainty about the approach.

When uncertain between two tiers, choose the higher one. Complexity is informational -- it does
not affect scheduling or task file fields -- but it lets the user spot risky tasks at review
time and helps the orchestrator prioritize easier tasks first in worktree mode.

**Picking workflow mode:** Analyze the dependency graph you just produced. If it is fully linear
(no fan-out -- every task depends on the previous one and tasks must ship together in a single
PR), recommend `session`. If the graph has independent branches that can run in parallel and each
branch ships standalone value, recommend `worktree`. Default to `session` when uncertain. State
the rationale in one line. The user may override before approving.

Immediately after `[PLAN_END]`, check `validate-before-ready.md`: if the project's `harness.md`
defines `validationCommands`, run `/validate` and fix any failures before continuing. Then emit
on its own line:

```
[STANLEY:READY_FOR_REVIEW]
```

Then **stop and wait**. Do not proceed until the user responds.

## Step 5 -- Handle user feedback

The user will either:

- **Approve:** Stanley emits `[STANLEY:PLAN_APPROVED]`. Proceed to Step 6.
- **Request changes:** Revise the plan (still read-only). Re-emit `[PLAN_START]`...`[PLAN_END]`
  followed by another `[STANLEY:READY_FOR_REVIEW]`. Wait again.
- **Reject / abort:** Update the planning task file status to `aborted` and stop.

Do not proceed to Step 6 until `[STANLEY:PLAN_APPROVED]` has been emitted.

## Step 6 -- Create child task files (worktree mode only)

Read-only mode ends.

**If `workflowMode: session`:** skip this step entirely. No child task files are written.
Proceed directly to Step 7.

**If `workflowMode: worktree`:** create the `{tasksDir}/{parentId}/` folder if it does not exist.

Before creating any files, check for existing child tasks (replanning scenario):

- Tasks with `status: in-progress` or `status: ready`: surface the conflict to the user and wait
  for their decision before overwriting.
- Tasks with `status: planned` or `status: draft`: delete and replace.

Write one file per task in the approved plan at `{tasksDir}/{parentId}/{childId}.md`:

```markdown
## <Task Title>
> id: <childId>
> type: regular
> priority: medium
> status: ready
> parentId: <parentId>
> workflowMode: worktree

<One-sentence description matching the plan entry.>
```

Add `> dependsOn: <id>` for any dependency listed in the plan.

**Cycle detection:** before writing any files, validate the dependency graph. For each task,
follow its `dependsOn` chain recursively. If any task is reachable from itself, a cycle exists.

If a cycle is detected:
1. Stop -- do not write any child task files.
2. Describe the cycle clearly to the user (e.g., "task A depends on B which depends on A").
3. Revise the plan to remove the cycle (still in read-only mode -- the plan revision happens
   in the `[PLAN_START]`...`[PLAN_END]` block, not in the file system).
4. Re-emit the revised plan and `[STANLEY:READY_FOR_REVIEW]`. Wait for approval again.

After writing each file, verify it exists with `ls`. Use the Python fallback from CLAUDE.local.md
for any file that does not appear after writing.

## Step 7 -- Write receipt and delete planning task

Complete the write sequence in order:

**1. Write the receipt** at `{tasksDir}/receipts/{parentId}.md`:

```markdown
## Receipt: <planning task title>
> planningTaskId: <parentId>
> completedAt: <ISO 8601 datetime>
> workflowMode: session | worktree

### Original Request

<Verbatim one-sentence description from the planning task file.>

### Tasks Created

| ID | Description |
|----|-------------|
| <childId> | <one-line description> |

### PR Links

- <childId>: pending

### Notes

(optional)
```

Verify the receipt file exists after writing.

**2. Delete the planning task file** at `{tasksDir}/{parentId}.md`.

**3. Execute based on workflow mode:**

- **`session`:** Do not stop here. Immediately begin working through child tasks in the current
  session. Use TodoWrite to track each child task. Work through them in dependency order,
  committing after each logical unit on the same branch. After all child tasks complete, emit
  `[STANLEY:READY_FOR_REVIEW]` for the combined PR.

- **`worktree`:** Stop and report to the user: how many child task files were created, where they
  live, and that each starts with `status: ready` -- the orchestrator will begin scheduling them
  immediately, respecting `dependsOn` order.
