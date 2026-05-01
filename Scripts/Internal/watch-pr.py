#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "requests",
# ]
# ///
"""CLI for monitoring and managing ADO PR build/test legs.

Commands:
    list   <PR-ID>   Enumerate build/test legs and their current status
    queue  <PR-ID>   Queue non-started or failed legs
    poll   <PR-ID>   Poll until legs reach a target status

Exit codes (list, poll):
    0  all tracked gates succeeded
    1  at least one gate failed or was canceled
    2  pending / timed out
    3  no builds found
    4  API or auth error
"""

import argparse
import ctypes
import json
import subprocess
import sys
import time
from datetime import datetime, timezone

import requests

# ---------------------------------------------------------------------------
# ADO defaults (set per fork)
# ---------------------------------------------------------------------------
ADO_ORG        = "<your-org>"
ADO_PROJECT    = "<your-project>"
ADO_REPO_ID    = "<your-repo-id>"
ADO_PROJECT_ID = "<your-project-id>"
ADO_RESOURCE   = "499b84ac-1321-427f-aa17-267ca6975798"


TERMINAL_RESULTS = {"succeeded", "failed", "canceled", "partiallySucceeded"}
FAILURE_RESULTS  = {"failed", "canceled", "partiallySucceeded"}

# ---------------------------------------------------------------------------
# ANSI colors (disabled when not a TTY)
# ---------------------------------------------------------------------------
_IS_TTY = sys.stdout.isatty()

if _IS_TTY and sys.platform == "win32":
    # Enable VT processing on Windows console
    try:
        kernel32 = ctypes.windll.kernel32
        kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
    except Exception:
        _IS_TTY = False

def _c(code: str, text: str) -> str:
    return f"\x1b[{code}m{text}\x1b[0m" if _IS_TTY else text

def green(t):  return _c("32", t)
def red(t):    return _c("31", t)
def yellow(t): return _c("33", t)
def cyan(t):   return _c("36", t)
def dim(t):    return _c("2", t)
def bold(t):   return _c("1", t)

# ---------------------------------------------------------------------------
# ADO auth (with simple 401-retry refresh)
# ---------------------------------------------------------------------------
_token: str | None = None


def get_token() -> str:
    global _token
    result = subprocess.run(
        ["az", "account", "get-access-token",
         "--resource", ADO_RESOURCE,
         "--query", "accessToken", "-o", "tsv"],
        capture_output=True, text=True,
        shell=(sys.platform == "win32"),
    )
    if result.returncode != 0 or not result.stdout.strip():
        print(f"error: failed to acquire ADO token: {result.stderr.strip()}", file=sys.stderr)
        sys.exit(4)
    _token = result.stdout.strip()
    return _token


def token() -> str:
    global _token
    if _token is None:
        get_token()
    return _token  # type: ignore[return-value]


def _headers() -> dict:
    return {"Authorization": f"Bearer {token()}"}


def _req(method: str, url: str, **kwargs) -> requests.Response:
    """Make an ADO request, refreshing the token once on 401."""
    resp = getattr(requests, method)(url, headers=_headers(), timeout=30, **kwargs)
    if resp.status_code == 401:
        get_token()
        resp = getattr(requests, method)(url, headers=_headers(), timeout=30, **kwargs)
    resp.raise_for_status()
    return resp


def ado_get(url: str) -> dict:
    return _req("get", url).json()


def ado_patch(url: str, body: dict | None = None) -> dict:
    return _req("patch", url, json=body or {}).json()


def ado_post(url: str, body: dict) -> dict:
    return _req("post", url, json=body).json()


# ---------------------------------------------------------------------------
# Build + policy data fetching
# ---------------------------------------------------------------------------
def fetch_builds(pr_id: int, org: str, project: str, repo_id: str) -> list[dict]:
    branch = f"refs/pull/{pr_id}/merge"
    url = (
        f"https://dev.azure.com/{org}/{project}/_apis/build/builds"
        f"?reasonFilter=pullRequest"
        f"&repositoryId={repo_id}"
        f"&repositoryType=TFSGit"
        f"&branchName={requests.utils.quote(branch, safe='')}"
        f"&api-version=7.1"
        f"&$top=50"
        f"&queryOrder=queueTimeDescending"
    )
    return ado_get(url).get("value", [])


def latest_per_pipeline(builds: list[dict]) -> dict[str, dict]:
    latest: dict[str, dict] = {}
    for b in builds:
        name = b["definition"]["name"]
        if name not in latest or b["id"] > latest[name]["id"]:
            latest[name] = b
    return latest


def fetch_policy_evals(pr_id: int, org: str, project: str, project_id: str) -> list[dict]:
    artifact = f"vstfs:///CodeReview/CodeReviewId/{project_id}/{pr_id}"
    url = (
        f"https://dev.azure.com/{org}/{project}/_apis/policy/evaluations"
        f"?artifactId={requests.utils.quote(artifact, safe='')}"
        f"&api-version=7.0-preview.1"
    )
    return ado_get(url).get("value", [])


# ---------------------------------------------------------------------------
# Leg construction helpers
# ---------------------------------------------------------------------------
def build_to_leg(b: dict) -> dict:
    return {
        "name":       b["definition"]["name"],
        "buildId":    b["id"],
        "status":     b.get("status", "unknown"),
        "result":     b.get("result"),
        "url":        b.get("_links", {}).get("web", {}).get("href"),
        "queueTime":  b.get("queueTime"),
        "startTime":  b.get("startTime"),
        "finishTime": b.get("finishTime"),
    }


def not_found_leg(name: str) -> dict:
    return {
        "name": name, "buildId": None, "status": "notFound", "result": None,
        "url": None, "queueTime": None, "startTime": None, "finishTime": None,
    }


def get_snapshot(pr_id: int, org: str, project: str, repo_id: str, project_id: str, filter_legs: list[str] | None = None) -> dict:
    builds  = fetch_builds(pr_id, org, project, repo_id)
    by_def_id: dict[int, dict] = {}
    for b in builds:
        def_id = b["definition"]["id"]
        if def_id not in by_def_id or b["id"] > by_def_id[def_id]["id"]:
            by_def_id[def_id] = b

    evals = fetch_policy_evals(pr_id, org, project, project_id)
    legs: list[dict] = []
    matched_build_ids: set[int] = set()
    seen_display: set[str] = set()

    for ev in evals:
        cfg      = ev.get("configuration", {})
        display  = cfg.get("settings", {}).get("displayName") or cfg.get("displayName") or ""
        def_id   = cfg.get("settings", {}).get("buildDefinitionId") or cfg.get("buildDefinitionId")
        if not display or display in seen_display:
            continue
        seen_display.add(display)
        build = by_def_id.get(def_id) if def_id else None
        if build:
            leg = build_to_leg(build)
            leg["displayName"] = display
            matched_build_ids.add(build["id"])
        else:
            leg = not_found_leg(display)
        legs.append(leg)

    # Include any builds not matched by a policy eval
    for b in by_def_id.values():
        if b["id"] not in matched_build_ids:
            legs.append(build_to_leg(b))

    if filter_legs:
        filter_set = set(filter_legs)
        legs = [l for l in legs if l["name"] in filter_set or l.get("displayName") in filter_set]

    return {
        "pullRequestId": pr_id,
        "polledAt":      datetime.now(timezone.utc).isoformat(),
        "gates":         [],
        "others":        legs,
    }


def compute_summary(legs: list[dict]) -> str:
    if not legs:
        return "noBuilds"
    if any(l.get("result") in FAILURE_RESULTS for l in legs):
        return "failed"
    active = [l for l in legs if l["status"] != "notFound"]
    if active and all(l.get("result") == "succeeded" for l in active):
        return "succeeded"
    return "pending"


# ---------------------------------------------------------------------------
# Table rendering (ANSI-safe padding)
# ---------------------------------------------------------------------------
def format_duration(start: str | None, finish: str | None) -> str:
    if not start:
        return "-"
    try:
        t0 = datetime.fromisoformat(start.replace("Z", "+00:00"))
        t1 = datetime.fromisoformat(finish.replace("Z", "+00:00")) if finish else datetime.now(timezone.utc)
        secs = int((t1 - t0).total_seconds())
        if secs < 60:
            return f"{secs}s"
        m, s = divmod(secs, 60)
        if m < 60:
            return f"{m}m {s:02d}s"
        h, m = divmod(m, 60)
        return f"{h}h {m:02d}m"
    except Exception:
        return "-"


def _leg_status_plain(leg: dict) -> str:
    r = leg.get("result")
    s = leg.get("status", "")
    if r:
        return r
    if s == "notFound":
        return "notFound"
    return s or "-"


def _leg_status_colored(leg: dict) -> str:
    r = leg.get("result")
    s = leg.get("status", "")
    if r == "succeeded":
        return green("succeeded")
    if r in ("failed", "canceled"):
        return red(r)
    if r == "partiallySucceeded":
        return yellow("partial")
    if s == "inProgress":
        return cyan("inProgress")
    if s == "notFound":
        return dim("notFound")
    return r or s or "-"


def print_legs_table(legs: list[dict], indent: str = ""):
    if not legs:
        print("(none)")
        return

    print(f"{indent}| # | Pipeline/Gate | Status | Duration |")
    print(f"{indent}|---|---|---|---|")
    for i, leg in enumerate(legs, 1):
        label  = leg.get("displayName") or leg["name"]
        status = _leg_status_colored(leg)
        dur    = format_duration(leg.get("startTime"), leg.get("finishTime"))
        print(f"{indent}| {i} | {label} | {status} | {dur} |")


# ---------------------------------------------------------------------------
# Effective config helpers
# ---------------------------------------------------------------------------

def effective_config(args):
    org        = getattr(args, "org", ADO_ORG)
    project    = getattr(args, "project", ADO_PROJECT)
    repo_id    = getattr(args, "repo_id", ADO_REPO_ID)
    project_id = getattr(args, "project_id", ADO_PROJECT_ID)
    return org, project, repo_id, project_id


# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------
def cmd_list(args) -> int:
    org, project, repo_id, project_id = effective_config(args)

    try:
        snap = get_snapshot(args.pr_id, org, project, repo_id, project_id)
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 4

    all_legs = snap["gates"] + snap["others"]
    summary  = compute_summary(all_legs)

    if args.json:
        print(json.dumps({
            "pullRequestId": snap["pullRequestId"],
            "polledAt":      snap["polledAt"],
            "summary":       summary,
            "builds":        all_legs,
        }, indent=2, default=str))
        return {"succeeded": 0, "failed": 1, "pending": 2, "noBuilds": 3}.get(summary, 2)

    if not all_legs:
        print("(no builds found)")
        return 3

    print_legs_table(all_legs)
    print()
    return {"succeeded": 0, "failed": 1, "pending": 2, "noBuilds": 3}.get(summary, 2)


# ---------------------------------------------------------------------------
# queue
# ---------------------------------------------------------------------------
def cmd_queue(args) -> int:
    org, project, repo_id, project_id = effective_config(args)

    try:
        snap = get_snapshot(args.pr_id, org, project, repo_id, project_id)
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 4

    all_legs = {l["name"]: l for l in snap["gates"] + snap["others"]}

    # Determine targets
    if args.leg:
        targets = args.leg
    elif args.not_started:
        targets = [n for n, l in all_legs.items() if l["status"] in ("notFound", "notStarted")]
    elif args.failed:
        targets = [n for n, l in all_legs.items() if l.get("result") in FAILURE_RESULTS]
    else:
        # Default: anything not started or failed
        targets = [
            n for n, l in all_legs.items()
            if l["status"] in ("notFound", "notStarted")
            or l.get("result") in FAILURE_RESULTS
        ]

    if not targets:
        print("Nothing to queue (no not-started or failed legs).")
        return 0

    if args.dry_run:
        print(f"Dry run -- would queue {len(targets)} leg(s):")
        for t in targets:
            print(f"  {t}")
        return 0

    # Try policy evaluations first, fall back to direct build queue
    try:
        evals = fetch_policy_evals(args.pr_id, org, project, project_id)
    except Exception as e:
        print(f"warning: could not fetch policy evaluations ({e}); will use build API fallback", file=sys.stderr)
        evals = []

    # Map display name -> evaluation
    eval_map: dict[str, dict] = {}
    for ev in evals:
        cfg  = ev.get("configuration", {})
        name = (
            cfg.get("settings", {}).get("displayName")
            or cfg.get("displayName")
            or ""
        )
        if name:
            eval_map[name] = ev
        # Also try case-insensitive fallback key
        eval_map.setdefault(name.lower(), ev)

    queued, errors = [], []

    for target in targets:
        ev = eval_map.get(target) or eval_map.get(target.lower())
        if ev:
            eval_id = ev["evaluationId"]
            url = (
                f"https://dev.azure.com/{org}/{project}/_apis/policy/evaluations"
                f"/{eval_id}?api-version=7.0-preview.1"
            )
            try:
                ado_patch(url)
                print(f"  re-queued (policy):  {target}")
                queued.append(target)
            except Exception as ex:
                print(f"  error (policy):      {target}: {ex}", file=sys.stderr)
                errors.append(target)
        else:
            # Fallback: find pipeline definition, queue build directly
            defs_url = (
                f"https://dev.azure.com/{org}/{project}/_apis/build/definitions"
                f"?name={requests.utils.quote(target, safe='')}&api-version=7.1"
            )
            try:
                defs = ado_get(defs_url).get("value", [])
                if not defs:
                    print(f"  skipped (definition not found): {target}")
                    errors.append(target)
                    continue
                body = {
                    "definition":   {"id": defs[0]["id"]},
                    "sourceBranch": f"refs/pull/{args.pr_id}/merge",
                    "reason":       1,
                }
                ado_post(
                    f"https://dev.azure.com/{org}/{project}/_apis/build/builds?api-version=7.1",
                    body,
                )
                print(f"  queued (build API):  {target}")
                queued.append(target)
            except Exception as ex:
                print(f"  error (build API):   {target}: {ex}", file=sys.stderr)
                errors.append(target)

    print(f"\n{len(queued)} queued, {len(errors)} failed.")
    return 1 if errors else 0


# ---------------------------------------------------------------------------
# poll
# ---------------------------------------------------------------------------
def _poll_stop(watched: list[dict], until: str, explicit: bool = False) -> str | None:
    """Returns 'succeeded' | 'failed' | None.

    Legs that are notFound or notStarted are ignored -- only legs that have
    actually started (inProgress or terminal) count toward stop conditions.
    If no watched legs have started and legs were not explicitly specified,
    returns 'succeeded' immediately (nothing to wait for). When legs are
    explicitly specified, keeps polling until they actually start.
    """
    active      = [l for l in watched if l["status"] not in ("notFound", "notStarted")]
    if not active:
        return None if explicit else "succeeded"
    any_failed  = any(l.get("result") in FAILURE_RESULTS for l in active)
    all_success = all(l.get("result") == "succeeded" for l in active)
    any_term    = any(l.get("result") in TERMINAL_RESULTS for l in active)
    all_term    = all(l.get("result") in TERMINAL_RESULTS for l in active)

    if until == "succeeded":
        if any_failed:   return "failed"
        if all_success:  return "succeeded"
    elif until == "failed":
        if any_failed:   return "failed"
        if all_success:  return "succeeded"
    elif until == "any":
        if any_failed:   return "failed"
        if any_term:     return "succeeded"
    elif until == "all":
        if any_failed:   return "failed"
        if all_term:     return "succeeded"
    return None


def cmd_poll(args) -> int:
    org, project, repo_id, project_id = effective_config(args)
    deadline      = time.monotonic() + args.timeout if args.timeout else None
    poll_n        = 0

    while True:
        try:
            snap = get_snapshot(args.pr_id, org, project, repo_id, project_id, args.legs or None)
        except Exception as e:
            print(f"error: {e}", file=sys.stderr)
            return 4

        watched = snap["others"]
        poll_n  += 1
        polled   = snap["polledAt"][:19].replace("T", " ")
        summary  = compute_summary(watched)

        if args.json:
            out = {
                "pullRequestId": args.pr_id,
                "polledAt":      snap["polledAt"],
                "pollCount":     poll_n,
                "summary":       summary,
                "gates":         snap["gates"],
                "others":        snap["others"],
                "watched":       watched,
            }
            print(json.dumps(out, default=str))
            sys.stdout.flush()
        else:
            print(f"\n--- Poll #{poll_n}  {polled} UTC ---")
            print_legs_table(watched)

        stop = _poll_stop(watched, args.until, explicit=bool(args.legs))
        if stop == "succeeded":
            if not args.json:
                print("\nAll watched legs succeeded.")
            return 0
        if stop == "failed":
            if not args.json:
                failed_names = [l["name"] for l in watched if l.get("result") in FAILURE_RESULTS]
                print(f"\nFailed: {', '.join(failed_names)}")
            return 1

        if deadline and time.monotonic() >= deadline:
            if not args.json:
                print(f"\nTimed out after {args.timeout}s (still pending).")
            return 2

        if not args.json:
            print(f"  next poll in {args.interval}s")
        time.sleep(args.interval)


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="watch-pr",
        description="Monitor and manage ADO PR build/test legs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
examples:
  watch-pr list 2127242
  watch-pr list 2127242 --all
  watch-pr list 2127242 --json
  watch-pr queue 2127242
  watch-pr queue 2127242 --leg "<Your Pipeline Name>"
  watch-pr queue 2127242 --failed --dry-run
  watch-pr poll 2127242
  watch-pr poll 2127242 --until succeeded --interval 30 --timeout 3600
  watch-pr poll 2127242 --json
  watch-pr poll 2127242 --legs "<Your Pipeline Name>" --until any
""",
    )
    p.add_argument("--org",        default=ADO_ORG,        help=f"ADO org (default: {ADO_ORG})")
    p.add_argument("--project",    default=ADO_PROJECT,    help=f"ADO project (default: {ADO_PROJECT})")
    p.add_argument("--repo-id",    dest="repo_id",    default=ADO_REPO_ID,    metavar="GUID")
    p.add_argument("--project-id", dest="project_id", default=ADO_PROJECT_ID, metavar="GUID")
    p.add_argument("--gates", nargs="+", metavar="NAME",
                   help="Override tracked gate pipeline names (space-separated)")

    sub = p.add_subparsers(dest="command", required=True)

    # -- list --
    lp = sub.add_parser("list", help="List PR legs and their status")
    lp.add_argument("pr_id", type=int, metavar="PR-ID")
    lp.add_argument("--all",  action="store_true", help="Include non-gate pipelines")
    lp.add_argument("--json", action="store_true", help="Output raw JSON (agent-friendly)")

    # -- queue --
    qp = sub.add_parser("queue", help="Queue not-started or failed legs")
    qp.add_argument("pr_id", type=int, metavar="PR-ID")
    qp.add_argument("--leg", nargs="+", metavar="NAME",
                    help="Queue specific leg(s) by name")
    qp.add_argument("--not-started", dest="not_started", action="store_true",
                    help="Only queue legs that have not started yet")
    qp.add_argument("--failed", action="store_true",
                    help="Only queue failed/canceled legs")
    qp.add_argument("--dry-run", dest="dry_run", action="store_true",
                    help="Print what would be queued without queuing")

    # -- poll --
    pp = sub.add_parser("poll", help="Poll until legs reach a target status")
    pp.add_argument("pr_id", type=int, metavar="PR-ID")
    pp.add_argument("--legs", nargs="+", metavar="NAME",
                    help="Specific legs to watch (default: all legs on the PR)")
    pp.add_argument("--until",
                    choices=["succeeded", "failed", "any", "all"],
                    default="succeeded",
                    help=(
                        "Stop condition: succeeded=all green or any red (default), "
                        "failed=any red, any=first terminal, all=all terminal"
                    ))
    pp.add_argument("--interval", type=int, default=60, metavar="SECS",
                    help="Seconds between polls (default: 60)")
    pp.add_argument("--timeout", type=int, default=None, metavar="SECS",
                    help="Abort after N seconds -- omit for no timeout")
    pp.add_argument("--json", action="store_true",
                    help="Output one JSON object per poll cycle (agent use)")

    return p


def main():
    args = build_parser().parse_args()

    # Prime the token once upfront
    get_token()

    try:
        if args.command == "list":
            sys.exit(cmd_list(args))
        elif args.command == "queue":
            sys.exit(cmd_queue(args))
        elif args.command == "poll":
            sys.exit(cmd_poll(args))
    except requests.HTTPError as e:
        print(f"error: HTTP {e.response.status_code}: {e}", file=sys.stderr)
        sys.exit(4)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(2)
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()
