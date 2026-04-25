"""Show agent tasks from ~/stanley/{project}/tasks/ as a markdown table, sorted by priority."""

import argparse
import os
import re
import subprocess
from pathlib import Path

PRIORITY_ORDER = {"top": 0, "high": 1, "medium": 2, "low": 3}
COMPLETED_STATUSES = {"completed", "done"}


def parse_task(filepath: Path) -> dict | None:
    text = filepath.read_text(encoding="utf-8")
    lines = text.splitlines()

    title = id_ = priority = status = None
    for line in lines:
        if title is None and (m := re.match(r"^##\s+(.+)", line)):
            title = m.group(1).strip()
        elif m := re.match(r"^>\s*id:\s*(.+)", line):
            id_ = m.group(1).strip()
        elif m := re.match(r"^>\s*priority:\s*(.+)", line):
            priority = m.group(1).strip()
        elif m := re.match(r"^>\s*status:\s*(.+)", line):
            status = m.group(1).strip()

    if not title:
        return None

    return {
        "title": title,
        "id": id_ or "",
        "priority": priority or "medium",
        "status": status or "draft",
    }


def collect_tasks(tasks_dir: Path) -> list[dict]:
    tasks = []
    for f in sorted(tasks_dir.rglob("*.md")):
        # Skip files under dot-folders
        if any(part.startswith(".") for part in f.relative_to(tasks_dir).parts[:-1]):
            continue
        if task := parse_task(f):
            tasks.append(task)
    return tasks


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
    # Fallback: try legacy .context/Tasks
    try:
        root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
        return str(Path(root) / ".context" / "Tasks")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ".context/Tasks"


def main() -> None:
    parser = argparse.ArgumentParser(description="Show agent tasks as a markdown table.")
    parser.add_argument("tasks_dir", nargs="?", default=None,
                        help="Path to the tasks directory (default: ~/stanley/{project}/tasks)")
    parser.add_argument("--all", "-a", action="store_true",
                        help="Include completed tasks")
    args = parser.parse_args()

    tasks_dir = Path(args.tasks_dir if args.tasks_dir is not None else _find_tasks_dir())
    if not tasks_dir.is_dir():
        print(f"No tasks directory found at {tasks_dir}")
        raise SystemExit(1)

    tasks = collect_tasks(tasks_dir)

    if not args.all:
        tasks = [t for t in tasks if t["status"] not in COMPLETED_STATUSES]

    if not tasks:
        print("No agent tasks found.")
        raise SystemExit(0)

    tasks.sort(key=lambda t: PRIORITY_ORDER.get(t["priority"], 9))

    print("| Priority | Status | Title | ID |")
    print("|----------|--------|-------|----|")
    for t in tasks:
        print(f"| {t['priority']} | {t['status']} | {t['title']} | {t['id']} |")


if __name__ == "__main__":
    main()
