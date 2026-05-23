# Share Your Apps — Publishing Workflow Spec

How a user-generated app-library infographic gets from the Mac app to a public
URL on `shared.coefficiencies.com`, without opening a content-moderation hole.

**Status:** design / not yet built. The local generate + preview + Save-HTML
flow already shipped (`InfographicRenderer.swift`, `InfographicPreviewWindow.swift`
— Save HTML is the hook point for Publish).

Related: [`icon-sourcing.md`](./icon-sourcing.md) for the measured icon
resolution research.

---

## Goal

A "Publish" button in the preview window that uploads the user's library to a
Cloudflare Worker, which renders a hosted page at a shareable URL. Friction-free
for legit users (no login), safe against pranksters putting porn/spam on the
owner's domain. Review happens *after* publish, with one-click takedown.

## The decision that drives the whole design

**Never accept image bytes — or even an icon URL — from the client.**

The client sends only structured data. The worker derives every icon from the
`bundleID` (which it can verify independently against the App Store). This
collapses the moderation surface from "arbitrary images + URLs" down to **two
text fields**: display name and website.

### Publish payload (client → worker)

```json
{
  "displayName": "Tom",
  "websiteURL": "coefficiencies.com",
  "apps": [
    { "bundleID": "com.apple.dt.Xcode", "name": "Xcode" },
    { "bundleID": "org.videolan.vlc",   "name": "VLC" }
  ]
}
```

No HTML, no images, no icon URLs. ≤500 apps.

## Architecture

```
macAppLibrary (Publish button)
        │  POST JSON + Turnstile token
        ▼
Cloudflare Worker  /publish
        │  validate → store payload + meta → return slug
        ▼
   KV / R2:  shared/<slug> = payload
             meta/<slug>   = { createdAt, ipHash, deleted:false }
             icon/<bundleID> = resolved icon (cache)
        │
        ▼
Worker  /shared/<slug>  → render HTML on request (icons via waterfall)
```

### Storage

- `shared/<slug>` → the JSON payload (tiny — a 500-app library is ~30 KB).
- `meta/<slug>` → `{ createdAt, ipHash, deleted, reviewed }`.
- `icon/<bundleID>` → resolved icon bytes/URL (cache; see icon sourcing).

> **Store the payload, not just rendered HTML.** Keeping the structured data
> lets us re-render with new templates later, run aggregate queries
> ("most-shared apps this week"), and honor delete requests cleanly. If we only
> stored HTML we'd have thrown the data away.

## Icon sourcing (server-side waterfall)

Measured combined coverage: **77%** today, **~90%+** after URL backfill. Full
detail in [`icon-sourcing.md`](./icon-sourcing.md).

| Tier | Source | Hosting |
| ---- | ------ | ------- |
| 1 | iTunes Lookup by bundleID → `artworkUrl512` | Apple CDN |
| 2 | Website favicon (`s2/favicons?sz=128`) from community `url` | Google/origin |
| 3 | Generated letter/category tile | self |

Cache `bundleID → icon` in KV; pre-warm from `scripts/icon-cache/manifest.json`.
Skip favicons that resolve to the generic globe or a code-host logo — let those
fall to tier 3 rather than show a misleading mark.

## Abuse controls (small, additive)

| Layer | What | Why |
| ----- | ---- | --- |
| Cloudflare Turnstile | captcha on `/publish` (free) | kills drive-by scripts |
| Rate limit | KV: 5 publishes / IP / day | one person can't flood |
| Field caps | `displayName ≤ 50`, `websiteURL` must `URL.canParse`, ≤ 500 apps | bounds the payload |
| Random slug | `/shared/ab3f9k2`, never `/shared/<name>` | no name-squatting, no SEO juice for spam |
| Denylist regex | on displayName + website | catches the obvious |
| Webhook on publish | Discord/Slack DM: title + slug + signed delete link | owner sees it in minutes, one-click takedown |
| `noindex` until reviewed | `<meta name="robots" content="noindex">` on fresh pages | nothing hits Google before a human has seen it |

The **signed delete link** is the keystone: review-after-publish, but worst-case
time-to-removal is minutes.

## Hosting

Serve from **`shared.coefficiencies.com`**, not `coefficiencies.com/shared/` —
clearly signals user-generated content and keeps it from diluting the main
site's brand/SEO. Needs a lightweight ToS + takedown page.

## Client UX

Add a **Publish** toolbar item to `InfographicPreviewWindow`, next to Save HTML.
On success: copy the URL to clipboard and open it in the browser. No login —
Turnstile + rate limit are the gate.

## What breaks if it goes viral

1. **Moderation regex stops scaling** → add a review queue + an LLM classifier
   (Workers AI is cheap) flagging the suspicious ~1% for a human. Discord alerts
   become noise; switch to a dashboard.
2. **Community PR queue explodes** — every new install surfaces long-tail apps
   with no community data. The AI-description pipeline becomes the bottleneck
   (API cost, rate limits). Need batch + dedupe before auto-merge.
3. **Legal** — hosting real names + websites at scale needs a ToS and a clean
   takedown / delete-request flow (GDPR-ish).

## The upside

Every shared infographic is a free landing page carrying coefficiencies
branding. A **newsletter signup at the bottom of every shared page** is the
prize — even 2% conversion compounds with each viral library. And the aggregate
data ("most-shared apps this week", "trending among devs") is recurring blog
content and potentially sponsorable.

---

## Work breakdown

Tracked in Todoist under the project, label **`publish-workflow`**:

1. Worker — `/publish` endpoint: validate, store payload + meta, return slug.
2. Worker — server-side HTML rendering at `/shared/<slug>` (port `InfographicRenderer`).
3. Icon resolution service — tier 1/2/3 waterfall + KV cache, seeded from the manifest.
4. Abuse controls — Turnstile, rate limit, denylist, random slug, signed delete link, webhook.
5. Client — Publish button in `InfographicPreviewWindow`, send payload, handle response.
6. Data — backfill `url` for the 44 no-url apps (cheapest lever on icon coverage).
7. Infra — `shared.coefficiencies.com` subdomain, ToS + takedown page, `noindex` default.
8. (Later) Aggregate data — "most-shared apps" report + newsletter signup on shared pages.
