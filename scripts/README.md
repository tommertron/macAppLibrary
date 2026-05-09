# scripts

## `merge-community-prs.py`

Drains the open `[Community] Add …` PRs in one shot.

### Why

The in-app **Submit to Community** flow used to append entries to the monolithic
`community-data.json` at the repo root. The flow was later switched to write
per-bundle files at `community-data/<bundleID>.json`, and a CI job
(`.github/workflows/regenerate-community-data.yml`) regenerates
`community-data.json` from that directory on every push to `main`.

Older PRs created against the legacy file are still arriving (and some users
are running older builds). Merging them as-is is worse than useless — the
regenerate job overwrites whatever they added. This script extracts each
submission's new entry, writes it to the per-bundle directory, pushes, and
closes the PRs.

### Usage

```sh
scripts/merge-community-prs.py --dry-run   # preview
scripts/merge-community-prs.py             # do it
```

Requires `gh` (authenticated) and `git` on PATH. Run from anywhere — the
script anchors to the repo root.

### What it does

1. Lists every open PR whose title starts with `[Community] `.
2. For each PR, fetches the head and diffs `community-data.json` against
   `origin/main` to find the single new bundle key. PRs that don't yield
   exactly one new key are still closed (they're stale duplicates).
3. Picks the highest-numbered PR per bundle key — that entry wins.
4. Writes `community-data/<key>.json` for each unique key. **Skips keys
   whose per-bundle file already exists** (assumes the existing file is
   authoritative).
5. Commits + pushes to `main`. If the push is rejected because CI advanced
   `origin/main` (the regenerate job runs after every push), it
   `git pull --rebase`s and retries once.
6. Closes every open community PR with a comment explaining the new flow.

### When NOT to use it

- If a PR contains edits beyond a single new bundle entry (e.g. someone
  hand-fixed an existing app), the script will silently ignore the edit and
  close the PR. Spot-check `gh pr diff <num>` before running if you suspect
  anything non-routine.
- If you've staged unrelated work on `main` locally, commit or stash it
  first — the script does its commits straight onto the current branch.
