#!/usr/bin/env python3
"""Create a git worktree for a new feature branch.

Usage:
    start-worktree [--repo PATH] "feature description"

Creates a worktree at <drive>:\\.worktrees\\<project>\\<slug>, where
<drive> is the drive of %repos% (falling back to the repo's own drive)
and <project> is derived by matching the repo path against entries in
~/.stanley/shared/ (first hit wins, scanning deepest segment first), with
the repo's basename as fallback. The branch is user/<alias>/<slug> based
on latest origin/main.
"""

import argparse
import os
import re
import subprocess
import sys

FILLER_WORDS = {"a", "an", "the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "is", "it"}
MAX_SLUG_LEN = 50


def get_alias():
    username = os.environ.get("USERNAME") or os.environ.get("USER") or ""
    # Strip domain prefix (e.g. DOMAIN+username -> username)
    if "+" in username:
        username = username.split("+", 1)[1]
    if "\\" in username:
        username = username.rsplit("\\", 1)[1]
    return username.lower()


def slugify(description):
    words = re.sub(r"[^a-z0-9\s-]", "", description.lower()).split()
    words = [w for w in words if w not in FILLER_WORDS]
    slug = "-".join(words)
    if len(slug) > MAX_SLUG_LEN:
        slug = slug[:MAX_SLUG_LEN].rstrip("-")
    return slug


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


def get_repo_root(path):
    raw = git("rev-parse", "--show-toplevel", cwd=path)
    return os.path.normpath(raw)


def resolve_project_name(repo_root):
    """Return the project name used for ~/.stanley/shared/{project} layout.

    Scan the repo path from the deepest segment outward and return the first
    segment that matches an existing ~/.stanley/shared/<entry> (case-insensitive).
    Falls back to the repo's basename for greenfield repos.
    """
    from pathlib import Path

    shared_base = Path.home() / ".stanley" / "shared"
    if shared_base.is_dir():
        shared_names = {e.name.lower(): e.name for e in shared_base.iterdir()}
        for part in reversed(Path(repo_root).parts):
            match = shared_names.get(part.lower())
            if match:
                return match
    return os.path.basename(repo_root)


def main():
    parser = argparse.ArgumentParser(description="Create a git worktree for a new feature.")
    parser.add_argument("feature", help="Feature name or description")
    parser.add_argument("--repo", default=".", help="Path to the git repository (default: current directory)")
    parser.add_argument("--base", default="main", help="Base branch to create from (default: main)")
    args = parser.parse_args()

    repo_root = get_repo_root(os.path.abspath(args.repo))
    project = resolve_project_name(repo_root)

    repos_env = os.environ.get("REPOS")
    anchor = os.path.abspath(repos_env) if repos_env else repo_root
    drive = os.path.splitdrive(anchor)[0]
    worktrees_root = os.path.join(drive + os.sep, ".worktrees", project)

    alias = get_alias()
    if not alias:
        print("Error: could not determine system alias", file=sys.stderr)
        sys.exit(1)

    slug = slugify(args.feature)
    if not slug:
        print("Error: feature name produced an empty slug", file=sys.stderr)
        sys.exit(1)

    branch = f"user/{alias}/{slug}"
    worktree_path = os.path.join(worktrees_root, slug)

    if os.path.exists(worktree_path):
        print(f"Error: worktree path already exists: {worktree_path}", file=sys.stderr)
        sys.exit(1)

    print(f"Repository:  {repo_root}")
    print(f"Branch:      {branch}")
    print(f"Worktree:    {worktree_path}")
    print()

    # Fetch latest from origin
    print(f"Fetching origin/{args.base}...")
    git("fetch", "origin", args.base, cwd=repo_root)

    # Create worktree with new branch based on origin/main
    print("Creating worktree...")
    os.makedirs(worktrees_root, exist_ok=True)
    git("worktree", "add", "-b", branch, worktree_path, f"origin/{args.base}", cwd=repo_root)

    print()
    print(f"Ready! To start working:")
    print(f"  cd {worktree_path}")


if __name__ == "__main__":
    main()
