@echo off
REM start-worktree.cmd
REM Purpose: Convenience wrapper to run the `Worktree\start-worktree.py` Python script using `uv`.
REM Summary: Creates a git feature worktree in a centralized `.worktrees` location.
REM          The Python script generates a slug, creates a branch from `origin/main`
REM          (convention: `user/<alias>/<slug>`), and runs `git worktree add -b`
REM          to create and register the new worktree.
REM Behavior: Forwards all command-line arguments to the Python script.
REM Usage: start-worktree.cmd [args]

REM Use the script directory as base so the call is repository-relative.
uv run "%~dp0Worktree\start-worktree.py" %*
