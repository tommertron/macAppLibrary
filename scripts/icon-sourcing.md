# Icon sourcing for the Share Your Apps publish workflow

Research notes + measured results for how the (future) publish worker should
get app icons **without ever accepting an uploaded image**.

> Context: the local "Share Your Apps" feature renders an infographic from the
> user's library. Locally, icons come from `NSWorkspace.shared.icon(forFile:)`
> — which only works because the apps are installed on that Mac. For a hosted
> publish flow, the server has only `{bundleID, name}` and must source icons
> itself. `AppEntry` does **not** collect icon images, so they have to be
> resolved server-side.

## The constraint that drives everything

**Never accept image bytes (or even an icon URL) from the client.** If users
can supply images, you inherit an image-moderation problem (porn/spam). So the
client sends only structured data — `{displayName, websiteURL, apps: [{bundleID, name}]}`
— and the worker decides every icon from the `bundleID`, which it can verify
independently. The moderation surface collapses to **two text fields** (display
name + website) plus a denylist regex.

## Resolution waterfall

| Tier | Source | Hosting | Notes |
| ---- | ------ | ------- | ----- |
| 1 | **iTunes Lookup API** by bundleID → `artworkUrl512` | Apple CDN | Mac App Store apps only. 512px. Zero moderation — Apple hosts it. |
| 2 | **Website favicon** (Google `s2/favicons?sz=128`) from the community `url` | Google/origin | Non-App-Store apps that have a URL. 128px. Externally hosted. |
| 3 | **Generated letter/category tile** | self | Always works. Initial letter on a color hashed from the name. No content → no moderation. |

At no tier does a user upload bytes or name a URL — so there is no image
pipeline to abuse.

```
https://itunes.apple.com/lookup?bundleId=<id>&entity=macSoftware   → results[0].artworkUrl512
https://www.google.com/s2/favicons?domain=<domain>&sz=128          → favicon png
```

## Measured coverage (291 community bundle IDs, 2026-05-20)

Run via `scripts/fetch-icons.py` (tier 1) then `scripts/fetch-favicons.py` (tier 2).

| Tier | Source | Count | Coverage |
| ---- | ------ | ----: | -------: |
| 1 | App Store (512px) | 124 | 42% |
| 2 | Favicon (128px) | 101 | 34% |
| **—** | **Combined** | **225** | **77%** |
| 3 | Tile fallback needed | 66 | 23% |

Cached output: `scripts/icon-cache/<bundleID>.png` (~225 PNGs, ~16 MB) plus
`scripts/icon-cache/manifest.json` mapping each bundleID → `{source, …}`. Both
scripts are resumable (skip anything already in the manifest).

### The 66 remainder is mostly a data gap, not a hard ceiling

- **44 are "no url"** — and they're famous: Firefox, VLC, Signal, Zoom,
  Transmission, ImageOptim, Pages/Numbers/Keynote, Hazel, Zed, ForkLift,
  NetNewsWire, Mimestream, SwiftBar… They simply lack a `url` field in
  `community-data/`. Backfilling those URLs (trivial — household names) pushes
  most into tier 2. **Realistic ceiling is ~90%+.**
- **12** resolved to Google's generic globe (no favicon found).
- **10** favicon fetches 404'd.

source breakdown from the manifest:
`{appstore: 124, favicon: 101, favicon-generic: 12, miss-nourl: 44, favicon-fail: 10}`

## Quality caveats

1. **Mixed resolution.** Tier 1 is 512px, tier 2 is 128px. Fine in a grid but
   they won't match weight exactly — upscale tier 2, or accept the mix.
2. **Favicons aren't always the app's brand.** Some resolve to the *code host*,
   not the app: Brewlet → GitHub octocat, chiaking → SourceHut. Tier 2 is
   "good-enough recognition," not a guaranteed real icon.

## Cost / scale notes

- iTunes Lookup rate-limits (~20/min). A publish may reference 200 apps, so
  **cache `bundleID → resolvedIcon` in KV** — popular apps recur across users,
  so the cache warms fast and only the long tail ever hits iTunes.
- Pre-warm the cache by seeding it with this run's `manifest.json` (the ~291
  bundleIDs already known to the community DB).

## Recommendations / follow-ups

1. **Backfill `url` for the 44 no-url apps.** Cheapest single lever on icon
   coverage *and* it improves the main app's community data. Highest ROI.
2. **Decide tier-2 quality bar.** Skip favicons that come back as the generic
   globe or a known code-host logo, and let those fall through to tier 3 tiles
   rather than showing a misleading mark.
3. **Make tier-3 tiles look intentional.** Color from a hash of the name (or
   from the app's category), centered initial — Notion/Gmail-avatar style. A
   grid of these should read as deliberate, not broken.
4. **Store the publish payload (JSON), not just rendered HTML**, keyed by slug —
   so icons can be re-resolved later as coverage improves.

## Files

- `scripts/fetch-icons.py` — tier 1 (App Store) resolver + downloader
- `scripts/fetch-favicons.py` — tier 2 (favicon) fallback for tier-1 misses
- `scripts/icon-cache/` — downloaded PNGs + `manifest.json` (currently untracked)
