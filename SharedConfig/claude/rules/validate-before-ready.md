# Validate Before Ready

Before emitting `[STANLEY:READY_FOR_REVIEW]`, run `/validate` if the project has a
`harness.md` file that defines `validationCommands`.

## When This Rule Applies

1. Locate `harness.md` in the repository root (or the worktree root for worktree-based tasks).
2. If `harness.md` exists **and** contains a `validationCommands` section, run `/validate`
   before emitting the marker.
3. If `harness.md` is absent, or present but has no `validationCommands`, this rule is a
   no-op. Emit `[STANLEY:READY_FOR_REVIEW]` normally.

## Behavior on Failure

If validation fails:

- Fix the underlying issue (do not suppress or skip the failing check).
- Re-run `/validate`.
- Repeat until all checks pass.
- Only then emit `[STANLEY:READY_FOR_REVIEW]`.

Do not emit the marker while any validation check is failing.

## Backwards Compatibility

Projects that have no `harness.md` are unaffected. This rule adds a pre-condition only when
the project explicitly opts in by providing `validationCommands` in `harness.md`.
