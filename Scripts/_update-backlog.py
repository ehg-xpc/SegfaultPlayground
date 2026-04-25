"""Update the status of an agent task by task ID."""

import argparse
import os
import re
import subprocess
from pathlib import Path

VALID_STATUSES = {"draft", "ready", "in-progress", "aborted", "completed", "done"}


def _resolve_project_name() -> str | None:
    """Read the project name from .stanley-project in the repo root."""
    try:
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        root = "."
    marker = Path(root) / ".stanley-project"
    if marker.is_file():
        return marker.read_text(encoding="utf-8").strip()
    return None


def _find_tasks_dir() -> str:
    """Return the tasks directory path for the current project."""
    project = _resolve_project_name()
    if project:
        return str(Path.home() / "stanley" / project / "tasks")
    return ".context/Tasks"


def find_task_file(tasks_dir: Path, task_id: str) -> Path | None:
    for f in tasks_dir.rglob("*.md"):
        if any(part.startswith(".") for part in f.relative_to(tasks_dir).parts[:-1]):
            continue
        for line in f.read_text(encoding="utf-8").splitlines():
            if re.match(rf"^>\s*id:\s*{re.escape(task_id)}\s*$", line):
                return f
    return None


def update_status(filepath: Path, new_status: str) -> str | None:
    text = filepath.read_text(encoding="utf-8")
    pattern = r"(^>\s*status:\s*)\S+(.*$)"
    new_text, count = re.subn(pattern, rf"\g<1>{new_status}\2", text, count=1, flags=re.MULTILINE)
    if count == 0:
        return None
    old_match = re.search(r"^>\s*status:\s*(\S+)", text, re.MULTILINE)
    old_status = old_match.group(1) if old_match else "unknown"
    filepath.write_text(new_text, encoding="utf-8")
    return old_status


def main() -> None:
    parser = argparse.ArgumentParser(description="Update an agent task's status by task ID.")
    parser.add_argument("task_id", help="The task ID (kebab-case)")
    parser.add_argument("status", help=f"New status: {', '.join(sorted(VALID_STATUSES))}")
    parser.add_argument("--tasks-dir", default=None,
                        help="Path to the tasks directory (default: ~/stanley/{project}/tasks)")
    args = parser.parse_args()

    if args.status not in VALID_STATUSES:
        print(f"Invalid status '{args.status}'. Valid: {', '.join(sorted(VALID_STATUSES))}")
        raise SystemExit(1)

    tasks_dir = Path(args.tasks_dir if args.tasks_dir is not None else _find_tasks_dir())
    if not tasks_dir.is_dir():
        print(f"No tasks directory found at {tasks_dir}")
        raise SystemExit(1)

    filepath = find_task_file(tasks_dir, args.task_id)
    if not filepath:
        print(f"No task found with id '{args.task_id}'")
        raise SystemExit(1)

    old_status = update_status(filepath, args.status)
    if old_status is None:
        print(f"No status field found in {filepath}")
        raise SystemExit(1)

    print(f"{args.task_id}: {old_status} -> {args.status}")


if __name__ == "__main__":
    main()
