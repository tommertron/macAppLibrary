#!/usr/bin/env python3
"""Resolve Mac App Store icons for community bundle IDs via the iTunes
Lookup API and download them. Bundle ID == community-data/<id>.json filename.

Writes icons to scripts/icon-cache/<bundleID>.png and a manifest mapping
bundleID -> {source, artworkUrl} (or miss) to scripts/icon-cache/manifest.json.
Resumable: skips bundle IDs already in the manifest.
"""
import json
import pathlib
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMUNITY = ROOT / "community-data"
OUT = ROOT / "scripts" / "icon-cache"
OUT.mkdir(parents=True, exist_ok=True)
MANIFEST = OUT / "manifest.json"

UA = "macAppLibrary-icon-fetch/1.0"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def lookup(bundle_id):
    q = urllib.parse.urlencode({"bundleId": bundle_id, "entity": "macSoftware"})
    data = json.loads(get(f"https://itunes.apple.com/lookup?{q}"))
    if data.get("resultCount"):
        res = data["results"][0]
        return res.get("artworkUrl512") or res.get("artworkUrl100")
    return None


def main():
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    bundles = sorted(p.stem for p in COMMUNITY.glob("*.json"))
    todo = [b for b in bundles if b not in manifest]
    print(f"{len(bundles)} bundles, {len(todo)} to resolve "
          f"({len(bundles) - len(todo)} cached)")

    hits = sum(1 for v in manifest.values() if v.get("artworkUrl"))
    for i, b in enumerate(todo, 1):
        try:
            art = lookup(b)
        except Exception as e:
            print(f"  [{i}/{len(todo)}] {b} ERROR {e}; backing off 30s")
            time.sleep(30)
            continue
        if art:
            try:
                (OUT / f"{b}.png").write_bytes(get(art))
                manifest[b] = {"source": "appstore", "artworkUrl": art}
                hits += 1
                print(f"  [{i}/{len(todo)}] {b} ✓")
            except Exception as e:
                manifest[b] = {"source": "appstore", "artworkUrl": art,
                               "downloadError": str(e)}
                print(f"  [{i}/{len(todo)}] {b} url ok, download failed: {e}")
        else:
            manifest[b] = {"source": "miss"}
            print(f"  [{i}/{len(todo)}] {b} —")
        if i % 25 == 0:
            MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True))
        time.sleep(0.4)

    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True))
    print(f"\nDone. {hits}/{len(bundles)} resolved "
          f"({100 * hits // len(bundles)}%). Icons in {OUT.relative_to(ROOT)}/")


if __name__ == "__main__":
    main()
