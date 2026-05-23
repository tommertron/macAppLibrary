// Input validation + the cheap denylist. The whole moderation surface is two
// free-text fields (displayName, websiteURL); everything else is structured.

import { yaml } from "./util.js";

// Obvious-junk filter on the two free-text fields. Deliberately small — the real
// safety net is noindex + the signed delete link, not a perfect regex.
const DENY = /\b(porn|xxx|nsfw|escort|viagra|cialis|casino|nigg|fuck|cunt)\b/i;

export function validatePayload(body, env) {
  const maxApps = Number(env.MAX_APPS || 500);
  const errors = [];

  const displayName = String(body?.displayName ?? "").trim();
  if (!displayName) errors.push("displayName is required");
  if (displayName.length > 50) errors.push("displayName must be ≤ 50 chars");

  let websiteURL = body?.websiteURL ? String(body.websiteURL).trim() : "";
  if (websiteURL) {
    const probe = websiteURL.includes("://") ? websiteURL : `https://${websiteURL}`;
    if (!URL.canParse(probe)) errors.push("websiteURL is not a valid URL");
  }

  if (DENY.test(displayName) || DENY.test(websiteURL)) errors.push("content rejected");

  const rawApps = Array.isArray(body?.apps) ? body.apps : null;
  if (!rawApps) errors.push("apps must be an array");
  else if (rawApps.length === 0) errors.push("apps is empty");
  else if (rawApps.length > maxApps) errors.push(`apps exceeds limit of ${maxApps}`);

  const apps = [];
  if (rawApps) {
    for (const a of rawApps) {
      const bundleID = String(a?.bundleID ?? "").trim();
      const name = String(a?.name ?? "").trim();
      if (!bundleID || !name) continue; // skip malformed rows rather than fail the whole publish
      // bundle IDs become filenames + URLs; keep them to a safe charset.
      if (!/^[A-Za-z0-9.\-]+$/.test(bundleID)) continue;
      let url = a?.url ? String(a.url).trim() : "";
      if (url) {
        const probe = url.includes("://") ? url : `https://${url}`;
        url = URL.canParse(probe) ? probe : "";
      }
      apps.push({
        bundleID,
        name: name.slice(0, 120),
        url,
        categories: Array.isArray(a?.categories)
          ? a.categories.map((c) => String(c).slice(0, 60)).slice(0, 10)
          : [],
        sizeBytes: Number.isFinite(a?.sizeBytes) && a.sizeBytes > 0 ? Math.floor(a.sizeBytes) : 0,
        favorite: a?.favorite === true,
      });
    }
  }
  if (rawApps && apps.length === 0) errors.push("no valid apps after validation");

  return {
    ok: errors.length === 0,
    errors,
    clean: {
      displayName,
      websiteURL: websiteURL ? (websiteURL.includes("://") ? websiteURL : `https://${websiteURL}`) : "",
      apps,
    },
  };
}

// Render the leaf-bundle index.md the Hugo `shared` layout expects. Field shape
// must match layouts/shared/single.html + lib-card.html (icon/url omitted when absent).
export function buildIndexMarkdown(clean, iconSet) {
  const L = [];
  L.push("---");
  L.push(`title: ${yaml(`${clean.displayName}'s Mac App Library`)}`);
  L.push(`displayName: ${yaml(clean.displayName)}`);
  if (clean.websiteURL) L.push(`websiteURL: ${yaml(clean.websiteURL)}`);
  L.push("showDate: false");
  L.push("showReadingTime: false");
  L.push("showTableOfContents: false");
  L.push("robots: noindex"); // stays out of search until reviewed
  L.push(`publishedAt: ${yaml(new Date().toISOString())}`);
  L.push("apps:");
  for (const a of clean.apps) {
    L.push(`  - name: ${yaml(a.name)}`);
    L.push(`    bundleID: ${yaml(a.bundleID)}`);
    if (iconSet.has(a.bundleID)) L.push(`    icon: ${yaml(`/app-icons/${a.bundleID}.png`)}`);
    if (a.url) L.push(`    url: ${yaml(a.url)}`);
    const cats = a.categories.map((c) => yaml(c)).join(", ");
    L.push(`    categories: [${cats}]`);
    L.push(`    sizeBytes: ${a.sizeBytes}`);
    L.push(`    favorite: ${a.favorite ? "true" : "false"}`);
  }
  L.push("---");
  L.push("");
  return L.join("\n");
}
