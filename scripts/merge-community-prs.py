#!/usr/bin/env python3
"""
Drain open community-submission PRs in one shot.

Handles every format the submission flow has produced:

  * Legacy ("monolithic") — PR edits community-data.json at repo root.
    Extracted into a per-bundle file at community-data/<bundle>.json,
    committed + pushed to main, and the PR is closed (CI would have
    overwritten the legacy edit on next regenerate anyway).

  * New Add — PR adds community-data/<bundle>.json. Merged via gh
    (squash + delete-branch) with rebase-retry on race rejection.

  * New Update — PR modifies an existing community-data/<bundle>.json.
    Skipped by default since these change live data; pass --include-updates
    to merge them too. Skipped Updates are listed with their diffs so you
    can run the script again with the flag (or merge them by hand).

Usage:
  scripts/merge-community-prs.py                    # legacy + Adds
  scripts/merge-community-prs.py --include-updates  # everything
  scripts/merge-community-prs.py --dry-run          # preview
"""

import argparse
import json
import pathlib
import subprocess
import sys
import time


REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMUNITY_DIR = REPO_ROOT / "community-data"
LEGACY_FILE = "community-data.json"
TITLE_PREFIX = "[Community] "
LEGACY_CLOSE_COMMENT = (
    "Superseded — entry merged directly via per-bundle file at "
    "`community-data/<bundle>.json`. The submission flow now writes per-bundle "
    "files which CI merges into `community-data.json` on every push to `main`. "
    "This PR targeted the legacy monolithic file and would have been overwritten "
    "by the regeneration job. Thanks for the submission!"
)
MERGE_MAX_ATTEMPTS = 6
MERGE_RETRY_SLEEP = 6  # seconds


def sh(*args, capture=True, check=True):
    r = subprocess.run(args, capture_output=capture, text=True, check=check, cwd=REPO_ROOT)
    return r.stdout if capture else None


def list_prs():
    out = sh("gh", "pr", "list", "--state", "open", "--limit", "200",
            "--json", "number,title,files,headRefName")
    return [p for p in json.loads(out) if p["title"].startswith(TITLE_PREFIX)]


def categorize(pr):
    """Return one of: 'legacy', 'add', 'update', 'unknown'."""
    files = pr["files"]
    if len(files) != 1:
        return "unknown"
    f = files[0]
    path, change = f["path"], f["changeType"]
    if path == LEGACY_FILE:
        return "legacy"
    if (path.startswith("community-data/") and path.endswith(".json")
            and "/" not in path[len("community-data/"):-len(".json")]):
        if change == "ADDED":
            return "add"
        if change == "MODIFIED":
            return "update"
    return "unknown"


def main_keys():
    sh("git", "fetch", "origin", "main", "--quiet")
    return set(json.loads(sh("git", "show", f"origin/main:{LEGACY_FILE}")).keys())


def extract_new_entry(pr_num, base_keys):
    sh("git", "fetch", "origin", f"pull/{pr_num}/head:pr-{pr_num}",
       "--quiet", "--force")
    try:
        data = json.loads(sh("git", "show", f"pr-{pr_num}:{LEGACY_FILE}"))
    except subprocess.CalledProcessError:
        return None, None
    new = set(data.keys()) - base_keys
    if len(new) != 1:
        return None, None
    k = next(iter(new))
    return k, data[k]


def push_with_rebase_retry():
    """Push HEAD to origin/main; rebase + retry once if rejected."""
    try:
        sh("git", "push", "origin", "main", capture=False)
    except subprocess.CalledProcessError:
        print("Push rejected — pulling --rebase and retrying.")
        sh("git", "pull", "--rebase", "origin", "main", capture=False)
        sh("git", "push", "origin", "main", capture=False)


def merge_pr(num):
    """gh pr merge --squash --delete-branch with retry for the 'base branch
    was modified' race that happens during bulk merges."""
    for attempt in range(1, MERGE_MAX_ATTEMPTS + 1):
        r = subprocess.run(
            ["gh", "pr", "merge", str(num), "--squash", "--delete-branch"],
            capture_output=True, text=True, cwd=REPO_ROOT,
        )
        if r.returncode == 0:
            return True, ""
        err = (r.stderr or "") + (r.stdout or "")
        if "Base branch was modified" in err and attempt < MERGE_MAX_ATTEMPTS:
            time.sleep(MERGE_RETRY_SLEEP)
            continue
        return False, err.strip()
    return False, "exhausted retries"


def handle_legacy(prs, dry_run):
    """Extract entries from legacy PRs, write per-bundle files, push, close."""
    if not prs:
        return [], []
    print(f"\n── Legacy ({len(prs)}) ──")
    base = main_keys()
    by_key = {}
    for pr in sorted(prs, key=lambda p: p["number"]):
        k, entry = extract_new_entry(pr["number"], base)
        if k is None:
            print(f"  #{pr['number']}: no unique new key — will still close")
            continue
        by_key[k] = (pr["number"], entry)  # later (higher #) wins
        print(f"  #{pr['number']}: {k}")

    written = []
    for k, (num, entry) in sorted(by_key.items()):
        p = COMMUNITY_DIR / f"{k}.json"
        if p.exists():
            print(f"  skip (exists): {p.relative_to(REPO_ROOT)}")
            continue
        if not dry_run:
            p.write_text(json.dumps(entry, indent=2, ensure_ascii=False) + "\n")
        written.append(k)

    closed = []
    if not dry_run:
        if written:
            sh("git", "add", "community-data/")
            sh("git", "commit", "-m",
               f"Add {len(written)} community app entries from legacy submission PRs")
            push_with_rebase_retry()
            print(f"  pushed {len(written)} per-bundle file(s)")
        for pr in prs:
            try:
                sh("gh", "pr", "close", str(pr["number"]),
                   "--comment", LEGACY_CLOSE_COMMENT)
                closed.append(pr["number"])
            except subprocess.CalledProcessError as e:
                print(f"  failed to close #{pr['number']}: {e}", file=sys.stderr)
    else:
        print(f"  [dry-run] would write {len(written)} file(s), close {len(prs)} PR(s)")

    return written, closed


def handle_merges(prs, label, dry_run):
    if not prs:
        return [], []
    print(f"\n── {label} ({len(prs)}) ──")
    merged, failed = [], []
    for pr in sorted(prs, key=lambda p: p["number"]):
        num = pr["number"]
        if dry_run:
            print(f"  [dry-run] would merge #{num}: {pr['title']}")
            merged.append(num)
            continue
        ok, err = merge_pr(num)
        if ok:
            print(f"  ✓ #{num}  {pr['title']}")
            merged.append(num)
        else:
            print(f"  ✗ #{num}  {pr['title']}\n      {err}", file=sys.stderr)
            failed.append(num)
    return merged, failed


def show_skipped_updates(prs):
    if not prs:
        return
    print(f"\n── Updates skipped ({len(prs)}) — review and re-run with --include-updates ──")
    for pr in sorted(prs, key=lambda p: p["number"]):
        print(f"\n#{pr['number']}  {pr['title']}")
        try:
            diff = sh("gh", "pr", "diff", str(pr["number"]))
            print(diff)
        except subprocess.CalledProcessError as e:
            print(f"  (could not fetch diff: {e})", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true",
                    help="show what would happen; make no changes")
    ap.add_argument("--include-updates", action="store_true",
                    help="also merge PRs that modify existing per-bundle files")
    args = ap.parse_args()

    prs = list_prs()
    if not prs:
        print("No open community PRs.")
        return 0

    buckets = {"legacy": [], "add": [], "update": [], "unknown": []}
    for p in prs:
        buckets[categorize(p)].append(p)

    print(f"Open community PRs: {len(prs)}")
    print(f"  legacy:  {len(buckets['legacy'])}")
    print(f"  add:     {len(buckets['add'])}")
    print(f"  update:  {len(buckets['update'])}  "
          f"({'will merge' if args.include_updates else 'will skip — pass --include-updates to merge'})")
    print(f"  unknown: {len(buckets['unknown'])}")
    for p in buckets["unknown"]:
        files = ", ".join(f"{f['path']} ({f['changeType']})" for f in p["files"])
        print(f"    #{p['number']}  {p['title']}  [{files}]")

    handle_legacy(buckets["legacy"], args.dry_run)
    add_merged, add_failed = handle_merges(buckets["add"], "Adds", args.dry_run)
    upd_merged, upd_failed = ([], [])
    if args.include_updates:
        upd_merged, upd_failed = handle_merges(buckets["update"], "Updates", args.dry_run)
    elif buckets["update"] and not args.dry_run:
        show_skipped_updates(buckets["update"])

    print("\n── Done ──")
    print(f"  Merged: {len(add_merged) + len(upd_merged)}")
    print(f"  Failed: {len(add_failed) + len(upd_failed)}")
    if buckets["unknown"]:
        print(f"  Skipped (unknown shape): {len(buckets['unknown'])}")
    if buckets["update"] and not args.include_updates:
        print(f"  Skipped (updates): {len(buckets['update'])} — re-run with --include-updates")

    return 0 if not (add_failed or upd_failed) else 1


if __name__ == "__main__":
    sys.exit(main())
