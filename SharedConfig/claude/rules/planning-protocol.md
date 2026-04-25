# Planning Protocol

This is the canonical specification for the planning protocol used by the Stanley harness and
Claude Code skills. All other documents that reference planning behavior derive from this spec.

---

## Task Types

Every task has a `type` field. If absent, it defaults to `regular`.

| Type | Purpose |
|------|---------|
| `regular` | Standard implementation task. Proceeds directly to execution. |
| `planning` | Decomposition task. Produces a plan and child tasks; read-only during decomposition. |
| `validation` | Validation-only task. Runs configured commands and reports pass/fail; no code changes. |

---

## Status Lifecycles

### Regular and Validation Tasks

```
draft → ready → in-progress → (done: file deleted)
                             ↘ aborted
```

| Status | Meaning |
|--------|---------|
| `draft` | Exists but not schedulable |
| `ready` | Scheduler may pick it up |
| `in-progress` | Actively being worked |
| `aborted` | Cancelled |

Completed tasks have their file deleted. There is no terminal `done` status value.

### Planning Tasks

```
draft → ready → in-progress → planning → approved → (done: file deleted)
                                                    ↘ aborted
```

| Status | Meaning |
|--------|---------|
| `planning` | Agent has entered the read-only decomposition phase |
| `approved` | User approved the plan; child task files are being created |

The planning task file is deleted after all child tasks are written and the receipt is saved.

### Child Tasks (created by a planning task)

```
planned → ready → in-progress → (done: file deleted)
                              ↘ aborted
```

| Status | Meaning |
|--------|---------|
| `planned` | Created by the planning task; not yet schedulable |

Child tasks are not promoted to `ready` automatically. The user or harness must explicitly set
them to `ready`.

---

## Markers

Markers are emitted on their own line. They are machine-readable signals consumed by Stanley and
Claude Code skills.

### `[STANLEY:PLANNING_START]`

Emitted by the agent immediately upon entering the decomposition phase.

- The planning task's status transitions to `planning`
- Read-only phase begins (see Phase Constraints)

### `[PLAN_START]` and `[PLAN_END]`

Wrap the structured plan proposal. All plan content must appear between these markers.

```
[PLAN_START]
## Plan: <title>

### Summary
One paragraph describing the approach.

### Tasks
| ID | Description | Complexity |
|----|-------------|------------|
| <task-id> | <one-line description> | low \| medium \| high |

### Dependencies
- <task-id> depends on <task-id>
[PLAN_END]
```

The task IDs listed here become the filenames of the child tasks. The plan content is
human-readable; the agent may revise it before approval without changing the plan structure.

### `[STANLEY:READY_FOR_REVIEW]`

Emitted immediately after `[PLAN_END]`. Signals that the plan is complete and awaiting user
approval.

- Stanley pauses the session and notifies the user
- No further agent action until the user responds
- If the user requests changes, the agent revises the plan (still read-only) and re-emits
  `[PLAN_START]`...`[PLAN_END]` followed by another `[STANLEY:READY_FOR_REVIEW]`

Before emitting this marker, validation must pass if the project defines `validationCommands`
in `harness.md`. See `validate-before-ready.md` for the full rule.


### `[STANLEY:PLAN_APPROVED]`

Emitted by **Stanley** (not the agent) when the user approves the plan.

- Planning task status transitions to `approved`
- Agent creates child task files in `tasks/{project}/{parentId}/`
- Each child task is written with `status: planned` and `parentId: <planningTaskId>`
- After all child tasks are written: planning task file is deleted, receipt is written

---

## Workflow Modes

Planning tasks support two execution modes for their child tasks. The mode is determined by the
`/plan` skill after analyzing the dependency graph and is written into each child task file as
`workflowMode`. See `task-schema-extension.md` for the full field definition and heuristic.

### `session` (default)

All tasks execute sequentially within the same session that ran `/plan`. No child task files are
written. After the agent writes the receipt, it immediately works through the tasks as TodoWrite
items -- one branch, one PR, no separate harness scheduling.

Use when: the dependency graph is linear, tasks ship together in a single PR, and parallel
worktree isolation adds overhead without benefit.

Canonical example: `harness-improvements` -- six sequential config writes, one PR, no value
from running six separate worktrees.

### `worktree`

Each child task is scheduled by the harness as an independent session in its own worktree, on
its own branch, with its own PR. Child tasks are created with `status: ready` so the orchestrator
can begin scheduling immediately. `dependsOn` governs execution order.

Use when: the dependency graph has independent branches that can run in parallel and each branch
ships standalone value.

---

## Phase Constraints

During the planning phase -- after `[STANLEY:PLANNING_START]`, before `[STANLEY:PLAN_APPROVED]`
-- the agent operates in **read-only mode**.

**Forbidden:**
- Writing or editing any file in the repository
- Creating or modifying task files
- Creating commits or branches
- Running commands that modify state (package installs, database changes, etc.)

**Permitted:**
- Reading files, searching code, fetching documentation
- Outputting the structured plan between `[PLAN_START]` / `[PLAN_END]`

Violation of these constraints is a harness error. Stanley may abort the planning task if a
write is detected during this phase.

---

## Workflow Folder Convention

```
tasks/{project}/
  {parentId}.md              ← planning task file
  {parentId}/
    {childId-1}.md           ← child tasks
    {childId-2}.md
    ...
  receipts/
    {parentId}.md            ← receipt (written when planning task completes)
```

The workflow folder `tasks/{project}/{parentId}/` is created by the agent immediately after
`[STANLEY:PLAN_APPROVED]`. If the folder already exists before that point, treat it as a
replanning situation (see Edge Cases).

---

## Receipt Format

A receipt is written when a planning task completes. It is a permanent, write-once record of
what the planning task produced.

**Location:** `tasks/{project}/receipts/{parentId}.md`

```markdown
## Receipt: <planning task title>
> planningTaskId: <id>
> completedAt: <ISO 8601 datetime>

### Original Request

<verbatim one-sentence description from the planning task file>

### Tasks Created

| ID | Description |
|----|-------------|
| <id> | <one-line description> |

### PR Links

- <task-id>: <PR URL or "pending">

### Notes

<optional free-form notes>
```

The receipt is written once and never updated. PR links may be `pending` at write time and are
not backfilled later.

**Write sequence (must complete in order):**

1. All child task files are written with `status: planned`
2. Receipt file is written at `tasks/{project}/receipts/{parentId}.md`
3. Planning task file is deleted

If interrupted mid-sequence, Stanley resumes from the last completed step on restart.

---

## Edge Cases

### Replanning (new plan under the same parent)

Triggered when a planning task targets a parent whose workflow folder already exists -- for
example, after the original plan was rejected or the planning task was aborted.

- List existing child tasks before creating new ones
- Child tasks with `status: in-progress` or `status: ready` must not be overwritten; surface the
  conflict to the user and wait for their decision
- Child tasks with `status: planned` or `status: draft` may be deleted and replaced
- A new receipt overwrites the old one if one already exists

### Aborted Dependency

If a child task that another child depends on is aborted:

- The dependent child task stays in its current status (`planned`, `ready`, etc.); it is NOT
  automatically aborted
- Stanley surfaces a warning noting the broken dependency
- The user decides whether to: (a) re-create the aborted task, (b) abort the dependent, or
  (c) remove the dependency and proceed
- No automatic cascading abort

### Session-Mode Partial Failure

When executing in `session` mode, if a child task fails mid-sequence after earlier tasks have
already been committed:

1. **Stop immediately.** Do not attempt later tasks in the sequence.
2. **Report clearly:** which task failed, what was committed so far (list commit hashes), and
   what remains unfinished.
3. **Open a draft PR** (or note the current branch state) so the partial work is visible and
   not lost.
4. **Emit `[STANLEY:READY_FOR_REVIEW]`** with a failure note rather than a success note, so
   Stanley/the user knows the session ended in a partial state.

Do not roll back earlier commits. The partial work is intentional and may be salvageable. The
user decides whether to continue, branch from here, or abandon the branch.

---

### Stale `in-progress` Tasks

A task with `status: in-progress` and no recent git activity on its branch is likely stale
(agent crashed or session was interrupted without cleanup).

When picking up a task that is already `in-progress`:

1. Check `git log` on the task's branch for commits in the last 24 hours.
2. If no recent commits exist, treat the task as resumable: read the branch state, check for
   any partial work, and continue from where it left off rather than starting over.
3. If the branch has unresolvable conflicts or the task file is corrupted, surface the
   situation to the user via `AskUserQuestion` before proceeding.

Stanley should surface a warning when a task has been `in-progress` for longer than
`taskTimeout` (if configured) or for more than 4 hours (default heuristic) with no commits.

---

### Validation Task Behavior

Validation tasks follow the regular task lifecycle (`draft` -> `ready` -> `in-progress` ->
deleted). They do not go through the planning phase and never emit `[STANLEY:PLANNING_START]`.
They may emit `[STANLEY:READY_FOR_REVIEW]` after running their commands, consistent with the
normal task workflow.
