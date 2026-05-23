# Share Your Apps — Publishing Workflow Spec

How a user-generated app-library infographic gets from the Mac app to a public
URL on coefficiencies.com, without opening a content-moderation hole.

**Status:** local flow shipped; hosted publish prototyped, not yet wired
end-to-end.

- Local generate + preview + Save-HTML shipped (`InfographicRenderer.swift`,
  `InfographicPreviewWindow.swift` — Save HTML is the hook point for Publish).
- Hosted rendering **prototyped** as real Hugo pages (coefficiencies branch
  `shared-library-prototype`) — see [Architecture](#architecture-hugo-native).

Related: [`icon-sourcing.md`](./icon-sourcing.md) — measured icon-resolution research.

---

## Goal

A "Publish" button in the preview window that uploads the user's library and
returns a shareable URL. Friction-free for legit users (no login), safe against
pranksters putting porn/spam on the owner's domain. Review happens *after*
publish, with one-click takedown.

## The decision that drives the whole design

**Never accept image bytes — or even an icon URL — from the client.**

The client sends only structured data. The server derives every icon from the
`bundleID` (verifiable independently against the App Store). This collapses the
moderation surface from "arbitrary images + URLs" down to **two text fields**:
display name and website.

### Publish payload (client → worker)

```json
{
  "displayName": "Tom",
  "websiteURL": "coefficiencies.com",
  "apps": [
    { "bundleID": "com.apple.dt.Xcode", "name": "Xcode", "url": "https://developer.apple.com/xcode/",
      "categories": ["Developer Tools"], "sizeBytes": 12000000000, "favorite": true },
    { "bundleID": "org.videolan.vlc", "name": "VLC", "url": "https://videolan.org",
      "categories": ["Video"], "sizeBytes": 180000000, "favorite": false }
  ]
}
```

No HTML, no images, no icon URLs. ≤ 500 apps.

## Architecture (Hugo-native)

> **Decision changed (validated this session).** Instead of a Worker rendering
> HTML, each published library is a **real Hugo page** on coefficiencies.com,
> rendered by the site's Congo theme. This reuses the actual site
> design/header/footer, the existing build-on-push deploy, and the existing
> subscribe + Buy-Me-a-Coffee block — no separate renderer to maintain.

```
macAppLibrary (Publish button)
        │  POST JSON + Turnstile token
        ▼
Cloudflare Worker  /publish
        │  validate · abuse controls · resolve icons (waterfall)
        │  top up shared icon store · commit data file via GitHub API
        ▼
coefficiencies repo (Hugo)
        │  content/shared/<slug>/index.md   (payload in YAML front-matter)
        │  static/app-icons/<bundleID>.png  (shared, deduped icon store)
        │
        │  push triggers existing deploy (GitHub Action → Tusky → `hugo`)
        ▼
   live page at  coefficiencies.com/shared/<slug>/
```

### Why store the payload, not HTML

The published artifact is the **front-matter payload**, and Hugo renders it.
Keeping structured data lets us re-render with new templates later, run
aggregate queries ("most-shared apps this week"), and honor delete requests
cleanly (just remove the content file + rebuild).

### What the worker writes to the repo

- `content/shared/<slug>/index.md` — title, displayName, websiteURL, `robots:
  noindex` (until reviewed), and the `apps` list in YAML front-matter.
- `static/app-icons/<bundleID>.png` — only for bundle IDs not already in the
  store (see icon sourcing).

The existing `macapplibrary-submissions` worker already opens GitHub PRs for
community data; the publish worker mirrors that pattern but **commits directly**
(no review gate) for no-friction publish.

## Rendering (prototyped)

On coefficiencies branch `shared-library-prototype`:

- `layouts/shared/single.html` — hero, **stats band** (apps · total size ·
  favorites · categories), **by-category bars**, **favorites** section,
  all-apps grid, and the site `support.html` partial (**subscribe + Buy Me a
  Coffee**).
- `layouts/partials/lib-card.html` — app card; links out when a `url` is known,
  falls back to a **CSS letter tile** when no icon. (Tag name is branched, not
  templated — Go's `html/template` forbids dynamic tag names.)
- `assets/css/custom.css` — `.lib-*` styles using the theme's
  `--color-primary/neutral` tokens (light + dark).
- `content/shared/sample/index.md` — sample built from real data via
  `scripts/gen-sample-shared.py`; renders at `/shared/sample/`.

Remaining to productionize: a `/shared/` list/index page, honoring the
`robots: noindex` front-matter, and slug/permalink confirmation.

## Icon sourcing (server-side waterfall)

Measured combined coverage: **77%** today, **~90%+** after URL backfill. Full
detail in [`icon-sourcing.md`](./icon-sourcing.md).

| Tier | Source | Hosting |
| ---- | ------ | ------- |
| 1 | iTunes Lookup by bundleID → `artworkUrl512` | Apple CDN → copied into store |
| 2 | Website favicon (`s2/favicons?sz=128`) from `url` | Google/origin → copied into store |
| 3 | Generated CSS letter tile (done, in `lib-card.html`) | self |

The store is the Hugo repo's **`static/app-icons/<bundleID>.png` — shared and
bundleID-keyed, so it dedupes across libraries** (grows with unique apps, not
publishes). The worker commits an icon only if that bundleID isn't already
present; seed it once from `scripts/icon-cache/manifest.json` (225 icons).

Skip favicons that resolve to the generic globe or a code-host logo — let those
fall to tier 3 rather than show a misleading mark. Note: some App Store artwork
is JPEG bytes saved with a `.png` name — preserve correct extension/content-type
when committing.

## Abuse controls (small, additive)

| Layer | What | Why |
| ----- | ---- | --- |
| Cloudflare Turnstile | captcha on `/publish` (free) | kills drive-by scripts |
| Rate limit | KV: 5 publishes / IP / day | one person can't flood |
| Field caps | `displayName ≤ 50`, `websiteURL` must `URL.canParse`, ≤ 500 apps | bounds the payload |
| Random slug | `/shared/ab3f9k2`, never `/shared/<name>` | no name-squatting, no SEO juice for spam |
| Denylist regex | on displayName + website | catches the obvious |
| Webhook on publish | Discord/Slack DM: title + slug + signed delete link | owner sees it in minutes, one-click takedown |
| `noindex` until reviewed | `robots: noindex` front-matter on fresh pages | nothing hits Google before a human has seen it |

The **signed delete link** is the keystone: review-after-publish, but worst-case
time-to-removal is minutes.

## Hosting

Pages live as real Hugo pages at **`coefficiencies.com/shared/<slug>/`**
(build-on-push to the Tusky server). Open decision: keep them on the main site
(simplest, reuses theme + deploy; `noindex` handles the SEO concern) vs. a
`shared.coefficiencies.com` subdomain (clearer UGC separation). Path is simpler.

> ⚠️ **Build constraint:** the Congo 2.9.0 theme only builds on **Hugo ≤ 0.145**.
> Hugo 0.146's template overhaul breaks it (the `figure.html` `_internal/`
> reference — patched on the prototype branch — plus `partial "partials/…"`
> prefix lookups). Nothing pins Hugo anywhere. Site/deploy must stay on
> Hugo ≤ 0.145 until Congo is upgraded. (Tracked separately in the Todoist inbox.)

## Client UX

Add a **Publish** toolbar item to `InfographicPreviewWindow`, next to Save HTML.
Build the payload from `store.apps` + `shareConfig` (send `{bundleID, name, url,
categories, sizeBytes, favorite}` per app — never the rendered HTML). POST to the
worker with a Turnstile token. On success: copy the returned URL to the
clipboard and open it in the browser. No login — Turnstile + rate limit are the
gate.

## What breaks if it goes viral

1. **Moderation regex stops scaling** → add a review queue + an LLM classifier
   (Workers AI) flagging the suspicious ~1% for a human. Discord alerts become
   noise; switch to a dashboard.
2. **Build-on-push is the cliff** — Hugo rebuilds the whole site per commit, and
   committing per publish gets ugly at high volume. Because the payload (not
   HTML) is stored, the escape hatch is clean: move only `/shared/*` rendering to
   a dynamic Worker and leave the rest of the site on Hugo.
3. **Community PR queue explodes** — every new install surfaces long-tail apps
   with no community data; the AI-description pipeline becomes the bottleneck.
   Need batch + dedupe before auto-merge.
4. **Legal** — hosting real names + websites at scale needs a ToS and a clean
   takedown / delete-request flow (GDPR-ish).

## The upside

Every shared infographic is a free landing page carrying coefficiencies
branding, **with the subscribe + Buy-Me-a-Coffee block already on it** — even 2%
newsletter conversion compounds with each viral library. And the aggregate data
("most-shared apps this week", "trending among devs") is recurring blog content
and potentially sponsorable.

---

## Work breakdown

Tracked in Todoist under the project, label **`publish-workflow`**. Go-live order:

1. **Worker `/publish`** — validate + abuse controls → resolve icons → top up
   `static/app-icons` → commit `content/shared/<slug>/index.md` via GitHub API
   (triggers the existing deploy). *(Cloudflare Worker.)*
2. **Client Publish button** in `InfographicPreviewWindow` — send payload, open
   the returned URL.
3. **Productionize Hugo** — `/shared/` list page, honor `robots: noindex`, merge
   the prototype branch. *(Rendering itself is done.)*
4. **Abuse controls** — Turnstile, rate limit, denylist, random slug, signed
   delete link, Discord webhook.
5. **Go-live infra** — ToS / takedown page; decide path vs subdomain. Site on
   Hugo ≤ 0.145 until Congo upgrade.
6. **Data (anytime)** — backfill `url` for the 44 no-url apps (cheapest lever on
   icon coverage).
7. **(Later)** — aggregate "most-shared apps" report; moderation dashboard at
   scale.

### Done this session (on branches)

- macAppLibrary `infographic-stats` — richer infographic stats in the Swift
  renderer; this spec, `icon-sourcing.md`, and the `fetch-*`/`gen-*` scripts.
- coefficiencies `shared-library-prototype` — the Hugo layout, card partial,
  CSS, support partial (subscribe + BMC), 225-icon shared store, sample page,
  and the `figure.html` build fix.
