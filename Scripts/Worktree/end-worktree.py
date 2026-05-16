#!/usr/bin/env python3
"""Remove a git worktree created by start-worktree.

Usage:
    end-worktree [worktree-path]

If no path is given, uses the current directory (must be inside a worktree).
Removes the worktree and optionally deletes the local branch.
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
    if result.returncode != 0:
        print(f"Error: git {' '.join(args)}\n{result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def git_check(*args, cwd=None):
    """Run a git command and return (success, stdout)."""
    result = subprocess.run(
        ["git", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    return result.returncode == 0, result.stdout.strip()


def get_worktree_info(path):
    """Return (worktree_path, branch, main_repo) for the given path."""
    path = os.path.normpath(os.path.abspath(path))

    # Check if we're in a worktree (not the main repo)
    common_dir = os.path.normpath(git("rev-parse", "--git-common-dir", cwd=path))
    git_dir = os.path.normpath(git("rev-parse", "--git-dir", cwd=path))

    if common_dir == git_dir:
        print("Error: not inside a worktree (this looks like the main repository)", file=sys.stderr)
        sys.exit(1)

    worktree_root = os.path.normpath(git("rev-parse", "--show-toplevel", cwd=path))
    branch = git("rev-parse", "--abbrev-ref", "HEAD", cwd=path)
    main_repo = os.path.normpath(os.path.dirname(common_dir)) if common_dir.endswith(".git") else os.path.normpath(common_dir)

    # common_dir points to the .git dir of the main repo
    # The main repo root is its parent
    if main_repo.endswith(".git"):
        main_repo = os.path.dirname(main_repo)

    return worktree_root, branch, main_repo


def main():
    parser = argparse.ArgumentParser(description="Remove a git worktree created by start-worktree.")
    parser.add_argument("path", nargs="?", default=".", help="Path to the worktree (default: current directory)")
    parser.add_argument("--delete-branch", action="store_true", help="Delete the local branch after removing the worktree")
    args = parser.parse_args()

    worktree_path, branch, main_repo = get_worktree_info(args.path)

    print(f"Worktree:    {worktree_path}")
    print(f"Branch:      {branch}")
    print(f"Repository:  {main_repo}")
    print()

    # Move out of the worktree so it can be deleted
    os.chdir(main_repo)

    # Check for uncommitted changes
    status = git("status", "--porcelain", cwd=worktree_path)
    if status:
        print("Warning: worktree has uncommitted changes:\n", file=sys.stderr)
        for line in status.splitlines():
            print(f"  {line}", file=sys.stderr)
        print(file=sys.stderr)
        confirm = input("Continue anyway? [y/N] ").strip().lower()
        if confirm != "y":
            print("Aborted.")
            sys.exit(0)

    # Remove the worktree
    print("Removing worktree...")
    git("worktree", "remove", worktree_path, cwd=main_repo)

    # Delete the branch if requested
    if args.delete_branch:
        print(f"Deleting branch {branch}...")
        ok, _ = git_check("branch", "-d", branch, cwd=main_repo)
        if not ok:
            print(f"Branch not fully merged. Force delete? [y/N] ", end="")
            confirm = input().strip().lower()
            if confirm == "y":
                git("branch", "-D", branch, cwd=main_repo)
            else:
                print(f"Branch {branch} kept.")
    else:
        print(f"Branch {branch} kept. Use --delete-branch to remove it.")

    print()
    print("Done!")


if __name__ == "__main__":
    main()
