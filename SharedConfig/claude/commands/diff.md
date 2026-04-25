Show the current git diff as a markdown-formatted code review.

Rules:
- Run `git diff` (or `git diff --staged` if there are staged changes) to get the raw diff
- Present each changed file as a separate section with a `### filename` header
- Use ```diff fenced code blocks with `+`/`-` prefixes for added/removed lines
- Include 2-3 lines of surrounding context for each change hunk
- For large unchanged sections between hunks, use `// ...` to skip
- If a file is deleted, just note "Deleted" under the header — don't show the full content unless it's short
- If a file is new, show the full content
- Keep it concise — collapse repetitive patterns (e.g. "same pattern at 5 catch sites")
- If $ARGUMENTS is provided, pass it to `git diff` (e.g. `/diff --staged`, `/diff HEAD~3`)
