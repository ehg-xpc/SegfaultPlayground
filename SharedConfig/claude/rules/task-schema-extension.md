# Task Schema Extension: Planning Fields

This file documents fields that extend the base task schema for planning workflows.
The base schema (`id`, `type`, `priority`, `status`, `parentId`, `targetBranch`, `dependsOn`) is
defined in `CLAUDE.md` and `planning-protocol.md`.

---

## workflowMode

Optional field on child task files. Only present on worktree-mode tasks; session-mode tasks
produce no child task files. Controls how the harness executes the child tasks in the workflow.

| Value | Meaning |
|-------|---------|
| `session` | Child tasks execute sequentially as TodoWrite items in the current session. One branch, one PR covers the full workflow. |
| `worktree` | Each child task is scheduled by the harness as an independent worktree session, on its own branch, with its own PR. |

Default if absent: `session`.

### Heuristic

The `/plan` skill analyzes the dependency graph produced in Step 4 and recommends a mode:

- **Linear graph (no fan-out):** tasks form a single chain A -> B -> C with no independent
  branches. Tasks ship together in one PR and deliver no standalone value individually.
  Recommend `session`.
- **Fan-out graph:** the graph has independent branches (e.g., A -> B and A -> C where B and C
  are independent). Each branch can ship standalone value and run in parallel.
  Recommend `worktree`.

The user may override the recommendation before approving the plan.

### Session-mode execution

When `workflowMode: session`, no child task files are written. The agent immediately executes
all tasks in the current session after writing the receipt:

1. Use TodoWrite to track child tasks as a checklist
2. Work through them in dependency order, respecting `dependsOn`
3. Commit after each logical unit, all on the same branch
4. After all child tasks complete, emit `[STANLEY:READY_FOR_REVIEW]`

One PR covers the entire workflow. The harness does not schedule session-mode tasks as separate
worktrees -- they run as part of the planning session itself.

### Worktree-mode execution

When `workflowMode: worktree`, the agent creates child tasks with `status: ready` and stops.
The orchestrator picks them up immediately for scheduling. `dependsOn` governs execution order --
the orchestrator will not start a task until all tasks it depends on have completed.
