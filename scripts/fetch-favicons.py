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
import io
import json
import pathlib
import subprocess
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


def to_png(data):
    """Normalize favicon bytes to a real PNG. Google's s2 returns PNG, but the
    DuckDuckGo fallback can return ICO or SVG — write those as .png unchanged
    and they'd be malformed. Rasterizes SVG via rsvg-convert and converts ICO
    (and other raster formats) via Pillow, picking the largest ICO frame.
    Returns PNG bytes, or None if the format can't be handled."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return data
    if b"<svg" in data[:600].lower() or data.lstrip()[:5] == b"<?xml":
        try:
            out = subprocess.run(["rsvg-convert", "-w", "128", "-h", "128"],
                                 input=data, capture_output=True, check=True).stdout
            return out or None
        except Exception:
            return None
    try:
        from PIL import Image
        im = Image.open(io.BytesIO(data))
        if im.format == "ICO" and im.ico.sizes():
            im = im.ico.getimage(max(im.ico.sizes()))
        buf = io.BytesIO()
        im.convert("RGBA").save(buf, "PNG")
        return buf.getvalue()
    except Exception:
        return None


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
        # Google's s2 service 404s for a fair number of domains that do have
        # favicons; fall back to DuckDuckGo's icon service before giving up.
        candidates = [
            f"https://www.google.com/s2/favicons?domain={urllib.parse.quote(dom)}&sz=128",
            f"https://icons.duckduckgo.com/ip3/{urllib.parse.quote(dom)}.ico",
        ]
        data = fav = err = None
        for candidate in candidates:
            try:
                png = to_png(get(candidate))
                if png is None:
                    raise ValueError("unrecognized image format")
                data = png
                fav = candidate
                break
            except Exception as e:
                err = e
        if data is not None:
            (OUT / f"{b}.png").write_bytes(data)
            hashes[b] = hashlib.sha1(data).hexdigest()
            manifest[b] = {"source": "favicon", "domain": dom, "faviconUrl": fav}
            got += 1
            print(f"  [{i}/{len(misses)}] {b} ✓ ({dom})")
        else:
            manifest[b] = {"source": "favicon-fail", "domain": dom, "error": str(err)}
            print(f"  [{i}/{len(misses)}] {b} fail ({dom}): {err}")
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
