#!/usr/bin/env python3
"""Tier-2 icon fallback: fetch favicons for bundle IDs that missed the App
Store lookup (scripts/fetch-icons.py). Uses the community `url` field and
Google's favicon service at 128px.

Updates the shared manifest.json: source becomes "favicon" on success, or
"miss-nourl" / "favicon-fail" otherwise. Saves to icon-cache/<bundle>.png.
Detects Google's generic globe fallback by hashing results and flagging the
most common hash as "favicon-generic" so we know the true tier-2 coverage.
"""
import collections
import hashlib
import json
import pathlib
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMUNITY = ROOT / "community-data"
OUT = ROOT / "scripts" / "icon-cache"
MANIFEST = OUT / "manifest.json"
UA = "macAppLibrary-icon-fetch/1.0"


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read()


def domain_for(bundle_id):
    f = COMMUNITY / f"{bundle_id}.json"
    if not f.exists():
        return None
    data = json.loads(f.read_text())
    url = (data.get("url") or "").strip()
    if not url:
        return None
    if "://" not in url:
        url = "https://" + url
    return urllib.parse.urlparse(url).netloc or None


def main():
    manifest = json.loads(MANIFEST.read_text())
    misses = [b for b, v in manifest.items() if v.get("source") == "miss"]
    print(f"{len(misses)} App Store misses to try via favicon")

    hashes = {}  # bundle -> sha1 of favicon bytes
    got = 0
    for i, b in enumerate(misses, 1):
        dom = domain_for(b)
        if not dom:
            manifest[b] = {"source": "miss-nourl"}
            print(f"  [{i}/{len(misses)}] {b} — no url")
            continue
        fav = f"https://www.google.com/s2/favicons?domain={urllib.parse.quote(dom)}&sz=128"
        try:
            data = get(fav)
            (OUT / f"{b}.png").write_bytes(data)
            hashes[b] = hashlib.sha1(data).hexdigest()
            manifest[b] = {"source": "favicon", "domain": dom, "faviconUrl": fav}
            got += 1
            print(f"  [{i}/{len(misses)}] {b} ✓ ({dom})")
        except Exception as e:
            manifest[b] = {"source": "favicon-fail", "domain": dom, "error": str(e)}
            print(f"  [{i}/{len(misses)}] {b} fail ({dom}): {e}")
        time.sleep(0.2)

    # Flag the generic globe: the most common identical favicon is almost
    # certainly Google's "unknown domain" placeholder.
    if hashes:
        counts = collections.Counter(hashes.values())
        common_hash, n = counts.most_common(1)[0]
        if n >= 3:  # only treat as generic if it recurs
            for b, h in hashes.items():
                if h == common_hash:
                    manifest[b]["source"] = "favicon-generic"
            got -= n
            print(f"\nFlagged {n} as generic globe (hash {common_hash[:8]})")

    MANIFEST.write_text(json.dumps(manifest, indent=2, sort_keys=True))

    total = len(manifest)
    appstore = sum(1 for v in manifest.values() if v["source"] == "appstore")
    favicon = sum(1 for v in manifest.values() if v["source"] == "favicon")
    print(f"\n— Coverage —")
    print(f"  App Store: {appstore} ({100*appstore//total}%)")
    print(f"  Favicon:   {favicon} ({100*favicon//total}%)")
    print(f"  Combined:  {appstore+favicon} ({100*(appstore+favicon)//total}%)")
    print(f"  Remaining (tile fallback): {total-appstore-favicon}")


if __name__ == "__main__":
    main()
