# Harness Schema

`harness.md` lives at `~/.agent-context/{project}/harness.md`. It configures project-level
policy for the Stanley harness and Claude Code skills.

Read by: `/plan` (Step 1), `/validate` (Steps 1-2), `/babysit-pr` (Step 1), `validate-before-ready.md`.

---

## Fields

### planningRequired

Controls when the `/plan` skill runs the full planning protocol.

| Value | Meaning |
|-------|---------|
| `always` | Always plan, even for clearly single-task requests |
| `multi-task` | Plan only when the request requires multiple tasks; skip for single tasks even if ambiguous |
| `auto` | Plan when the request is vague or involves multiple tasks (default) |
| `never` | Never plan; execute all tasks directly |

Default if absent: `auto`.

---

### validationCommands

Commands run by `/validate` before `[STANLEY:READY_FOR_REVIEW]` is emitted. Each entry is
a bullet in a `## validationCommands` section:

```markdown
## validationCommands

- Label: command to run
- Another label: command --timeout 120
- Label (warn): advisory command
```

Entry formats:
- `Label: command` -- blocking check; failure prevents `[STANLEY:READY_FOR_REVIEW]`.
- `Label (warn): command` -- advisory check; failure is reported but does not block.
- `command` (no colon) -- blocking; the command itself is shown as the label.
- Append `--timeout <seconds>` to set a per-command wall-clock limit (default: 300 s).

Commands run sequentially. All **blocking** checks must exit 0 for validation to pass.

Absent or empty: `/validate` is a no-op; `[STANLEY:READY_FOR_REVIEW]` emits without checks.

---

### reviewRequired

Whether human review is required before a task can be marked complete.

| Value | Meaning |
|-------|---------|
| `true` | Review required; harness waits for explicit approval before auto-completing |
| `false` | No review required |

Default if absent: `false`.

---

### taskDefaults

Default field values written into new task files when not explicitly specified. Overrides
built-in defaults but is overridden by values set in the task file itself.

```markdown
## taskDefaults

priority: high
type: regular
```

Supported keys: `priority` (`top`, `high`, `medium`, `low`), `type` (`regular`, `planning`, `validation`).

---

### maxAutoFixAttempts

Maximum consecutive fix attempts per build gate before `/babysit-pr` escalates to the user.

Default if absent: `3`.

```markdown
## maxAutoFixAttempts

5
```

---

### taskTimeout

Wall-clock time limit in minutes for a single task session. If the harness is still working
when this limit is reached, it escalates to the user with a summary of what was attempted.

Absent: no timeout (task runs until completion or manual abort).

```markdown
## taskTimeout

120
```

---

### contextPreload

Files the agent should always read at the start of a worktree task before beginning any
implementation work. Useful for architecture documents, coding style guides, or any file not
already surfaced by CLAUDE.md.

Paths are relative to the repo root. Glob patterns are supported.

```markdown
## contextPreload

- docs/architecture.md
- docs/coding-style.md
- src/*/README.md
```

---

### securityReviewRequired

Whether `/security-review` must pass as part of the validation pipeline before
`[STANLEY:READY_FOR_REVIEW]` is emitted.

| Value | Meaning |
|-------|---------|
| `true` | Run `/security-review`; block on any findings |
| `false` | Skip security review |

Default if absent: `false`.

---

### buildGates

Ordered list of ADO pipeline names that `/babysit-pr` must shepherd through in sequence.
Gate N is not started (or fixed) until gate N-1 has succeeded. If absent, `/babysit-pr`
operates in unordered mode and watches all build legs.

```markdown
## buildGates

- name: Exact Pipeline Name 1
- name: Exact Pipeline Name 2
- name: Exact Pipeline Name 3
```
