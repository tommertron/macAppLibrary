// Server-side icon resolution waterfall — never trusts client image bytes/URLs.
//   1. iTunes Lookup by bundleID → artworkUrl512  (App Store, sharp)
//   2. Website favicon (Google s2) from the app's url
//   3. (no match) → omitted; the Hugo lib-card partial renders a letter tile
// See scripts/icon-sourcing.md for the measured ~77% coverage behind this.

import { bytesToBase64 } from "./util.js";

const MAX_ICON_BYTES = 512 * 1024; // skip anything implausibly large for an icon

async function fetchImage(url) {
  const res = await fetch(url, { headers: { "User-Agent": "macapplibrary-publish-worker" } });
  if (!res.ok) return null;
  const type = res.headers.get("content-type") || "";
  if (!type.startsWith("image/")) return null;
  const buf = await res.arrayBuffer();
  if (buf.byteLength === 0 || buf.byteLength > MAX_ICON_BYTES) return null;
  return bytesToBase64(buf);
}

async function fromITunes(bundleID) {
  const res = await fetch(
    `https://itunes.apple.com/lookup?bundleId=${encodeURIComponent(bundleID)}&entity=macSoftware`,
    { headers: { "User-Agent": "macapplibrary-publish-worker" } }
  );
  if (!res.ok) return null;
  const data = await res.json().catch(() => null);
  const art = data?.results?.[0]?.artworkUrl512;
  return art ? fetchImage(art) : null;
}

async function fromFavicon(appURL) {
  if (!appURL) return null;
  let host;
  try {
    host = new URL(appURL).hostname;
  } catch {
    return null;
  }
  return fetchImage(`https://www.google.com/s2/favicons?domain=${encodeURIComponent(host)}&sz=128`);
}

// Resolve icons for the given apps, capped at `budget` network attempts so a
// large first-time library can't blow the worker's subrequest limit.
// Returns Map<bundleID, base64png>. Note: App Store artwork is sometimes JPEG
// bytes; we still store it under .png — browsers sniff it, Hugo serves it fine.
export async function resolveIcons(apps, budget) {
  const out = new Map();
  let used = 0;
  for (const a of apps) {
    if (used >= budget) break;
    used++;
    let b64 = await fromITunes(a.bundleID);
    if (!b64) b64 = await fromFavicon(a.url);
    if (b64) out.set(a.bundleID, b64);
  }
  return out;
}
