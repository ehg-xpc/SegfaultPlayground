#!/usr/bin/env python3
"""Sync the AgentContext repo: commit local changes, pull --rebase, push.

Usage:
    sync-context [--repo PATH]

Resolves the AgentContext repo via the ~/.stanley/shared/{project} symlink
(falls back to legacy .context symlink). Stages and commits any local changes,
rebases on origin/main, and pushes.

Exit codes:
    0  Success
    1  Shared context symlink not found or not set up
    2  Rebase conflict (rebase is aborted automatically)
    3  Push failed
"""

import argparse
import os
import subprocess
import sys


def git(*args, cwd=None):
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    return result


def git_ok(*args, cwd=None):
    result = git(*args, cwd=cwd)
    if result.returncode != 0:
        print(f"Error: git {' '.join(args)}\n{result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def find_repo_root(start_path):
    result = git("rev-parse", "--show-toplevel", cwd=start_path)
    if result.returncode != 0:
        print("Error: not inside a git repository.", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def _resolve_project_name(repo_root):
    """Infer the project name for ~/.stanley/shared/{project} lookup.

    Resolution order:
    1. Stanley worktree path: ~/.stanley/worktrees/{project}/{branch}/
    2. Repo directory name matched against existing ~/.stanley/shared/ entries
    """
    from pathlib import Path

    # Infer from Stanley worktree path: ~/.stanley/worktrees/{project}/{branch}
    worktrees_base = Path.home() / ".stanley" / "worktrees"
    try:
        rel = Path(repo_root).relative_to(worktrees_base)
        parts = rel.parts
        if len(parts) >= 2:
            return parts[0]
    except ValueError:
        pass

    # Match any segment of the repo path against ~/.stanley/shared/ entries
    shared_base = Path.home() / ".stanley" / "shared"
    if shared_base.is_dir():
        shared_names = {e.name.lower(): e.name for e in shared_base.iterdir()}
        for part in reversed(Path(repo_root).parts):
            match = shared_names.get(part.lower())
            if match:
                return match

    return None


def resolve_context_repo(repo_root):
    """Find the AgentContext repo root via ~/.stanley/shared/{project} or legacy .context."""
    from pathlib import Path

    # New path: ~/.stanley/shared/{project}
    project = _resolve_project_name(repo_root)
    if project:
        shared_link = Path.home() / ".stanley" / "shared" / project
        if shared_link.exists():
            resolved = os.path.realpath(shared_link)
            return os.path.dirname(resolved)

    # Legacy fallback: .context symlink in repo root
    context_link = os.path.join(repo_root, ".context")
    if os.path.islink(context_link) or os.path.isdir(context_link):
        resolved = os.path.realpath(context_link)
        return os.path.dirname(resolved)

    print("Error: shared context link not found.", file=sys.stderr)
    print("Neither ~/.stanley/shared/{project} nor .context symlink is set up.", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Sync the AgentContext repo.")
    parser.add_argument("--repo", default=".", help="Path to the project repo (default: cwd)")
    args = parser.parse_args()

    repo_root = find_repo_root(os.path.abspath(args.repo))
    ctx_repo = resolve_context_repo(repo_root)
    print(f"AgentContext repo: {ctx_repo}")

    # Step 1: Stage and commit local changes
    status = git_ok("status", "--short", cwd=ctx_repo)
    if status:
        print("\nLocal changes detected:")
        git_ok("add", "-A", cwd=ctx_repo)
        stat = git_ok("diff", "--cached", "--stat", cwd=ctx_repo)
        print(stat)
        git_ok("commit", "-m", "Sync agent context", cwd=ctx_repo)
        print("Committed local changes.")
    else:
        print("No local changes.")

    # Step 2: Pull and rebase
    print("\nPulling from origin/main...")
    pull = git("pull", "--rebase", "origin", "main", cwd=ctx_repo)
    if pull.returncode != 0:
        # Check for conflicts
        conflicts = git("diff", "--name-only", "--diff-filter=U", cwd=ctx_repo)
        if conflicts.stdout.strip():
            print("Rebase conflict detected. Aborting rebase.", file=sys.stderr)
            print(f"Conflicted files:\n{conflicts.stdout.strip()}", file=sys.stderr)
            git("rebase", "--abort", cwd=ctx_repo)
            sys.exit(2)
        else:
            print(f"Pull failed:\n{pull.stderr.strip()}", file=sys.stderr)
            sys.exit(2)
    print(pull.stdout.strip() if pull.stdout.strip() else "Already up to date.")

    # Step 3: Push
    print("\nPushing to origin/main...")
    push = git("push", "origin", "main", cwd=ctx_repo)
    if push.returncode != 0:
        print(f"Push failed:\n{push.stderr.strip()}", file=sys.stderr)
        sys.exit(3)
    output = push.stderr.strip() or push.stdout.strip() or "Everything up-to-date"
    print(output)
    print("\nSync complete.")


if __name__ == "__main__":
    main()
