# Commit Changes

Follow these steps exactly. Do not skip ahead.

## Step 1 — Analyze

Run `git diff --cached --stat` and `git diff --stat` to see what is staged and what is unstaged.
If there is nothing staged and nothing unstaged, stop and tell the user — there is nothing to commit.

## Step 2 — Propose and wait for approval

Compose two title candidates from the staged changes:
- **Full title**: one line, imperative mood, no project-name prefix — describes what changed and why
- **Short title**: 3–5 word condensed version of the full title

Use the `AskUserQuestion` tool with the full title as the label of option 1, the short title as the label of option 2, and "Type your own" as option 3. The user must be able to read both proposed titles directly from the option labels — do not use generic placeholders like "Use full title".

If there are also unstaged changes, add a second question asking whether to commit staged only or stage+commit everything.

Do not commit anything until the user approves. If the user requests changes, revise and ask again with `AskUserQuestion`.

## Step 3 — Execute (only after approval)

Once the user approves:

1. If committing unstaged changes too: `git add` the relevant files before committing.
2. `git commit -m "<title>"` — single-line message is enough for a quick commit.
