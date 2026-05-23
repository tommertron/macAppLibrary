#!/usr/bin/env python3
"""Generate a sample published-library page for the Hugo prototype, using real
community data + the resolved icon manifest. Writes a content/shared/<slug>/
index.md with the payload in YAML front-matter.

Sizes + favorites are synthesized (community data has neither) purely so the
stats band has something to show — the real Mac app supplies both.
"""
import json
import pathlib
import random

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMMUNITY = ROOT / "community-data"
MANIFEST = ROOT / "scripts" / "icon-cache" / "manifest.json"
HUGO = pathlib.Path.home() / "Obsidian" / "coefficiencies"
OUT = HUGO / "content" / "shared" / "sample" / "index.md"

random.seed(42)


def yaml_escape(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    manifest = json.loads(MANIFEST.read_text())
    # Real icons only: App Store artwork or a genuine (non-generic) favicon.
    usable = {b: v for b, v in manifest.items()
              if v.get("source") in ("appstore", "favicon")}

    icon_store = HUGO / "static" / "app-icons"

    def normalize_url(u):
        u = (u or "").strip()
        if not u:
            return None
        return u if "://" in u else f"https://{u}"

    apps = []
    for bundle, meta in usable.items():
        cf = COMMUNITY / f"{bundle}.json"
        if not cf.exists():
            continue
        data = json.loads(cf.read_text())
        # Self-hosted icon from the shared store, not the remote CDN/favicon URL.
        icon = f"/app-icons/{bundle}.png" if (icon_store / f"{bundle}.png").exists() else None
        apps.append({
            "name": data.get("name", bundle),
            "bundleID": bundle,
            "icon": icon,
            "url": normalize_url(data.get("url")),
            "categories": data.get("categories", []),
            "sizeBytes": random.randint(8, 2200) * 1_000_000,  # 8MB–2.2GB
            "favorite": False,
        })

    apps.sort(key=lambda a: a["name"].lower())
    # Take a varied slice and flag a handful of favorites.
    sample = apps[:48]
    for a in random.sample(sample, k=min(5, len(sample))):
        a["favorite"] = True

    lines = [
        "---",
        'title: "Tom\'s Mac App Library"',
        'displayName: "Tom"',
        'websiteURL: "coefficiencies.com"',
        "showDate: false",
        "showReadingTime: false",
        "showTableOfContents: false",
        "robots: noindex",
        "apps:",
    ]
    for a in sample:
        lines.append(f"  - name: {yaml_escape(a['name'])}")
        lines.append(f"    bundleID: {yaml_escape(a['bundleID'])}")
        if a["icon"]:
            lines.append(f"    icon: {yaml_escape(a['icon'])}")
        if a["url"]:
            lines.append(f"    url: {yaml_escape(a['url'])}")
        cats = ", ".join(yaml_escape(c) for c in a["categories"])
        lines.append(f"    categories: [{cats}]")
        lines.append(f"    sizeBytes: {a['sizeBytes']}")
        lines.append(f"    favorite: {str(a['favorite']).lower()}")
    lines.append("---")
    lines.append("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines))
    favs = sum(1 for a in sample if a["favorite"])
    print(f"Wrote {OUT}")
    print(f"  {len(sample)} apps, {favs} favorites")


if __name__ == "__main__":
    main()
