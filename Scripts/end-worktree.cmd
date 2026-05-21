@echo off
REM end-worktree.cmd
REM Purpose: Convenience wrapper to run the `Worktree\end-worktree.py` Python script using `uv`.
REM Summary: Removes a git worktree and optionally deletes its branch. The
REM          underlying Python script validates the path is a managed worktree,
REM          calls `git worktree remove`, and offers an option to delete the
REM          associated branch from the repository.
REM Behavior: Forwards all command-line arguments to the Python script.
REM Usage: end-worktree.cmd [args]

REM %~dp0 expands to the directory containing this batch file so the script runs relative to the repo.
uv run "%~dp0Worktree\end-worktree.py" %*
