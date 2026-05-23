# macAppLibrary Publish Worker

Turns a user's app library into a real Hugo page at
`coefficiencies.com/shared/<slug>/`. The Mac app POSTs structured JSON; the
worker validates it, resolves icons from each `bundleID`, and commits a Hugo
content file (plus any new icons) to the site repo in **one commit**. The
existing push→build deploy renders the page.

**The rule that keeps this safe:** the client sends *data only* — never HTML,
never images, never icon URLs. The whole moderation surface is two text fields
(display name + website). Full design: [`../scripts/publishing-workflow-spec.md`](../scripts/publishing-workflow-spec.md).

## Endpoints

| Method | Path       | Purpose |
| ------ | ---------- | ------- |
| `POST` | `/publish` | Validate → resolve icons → commit `content/shared/<slug>/index.md`. Returns `{ url, slug, building: true }`. |
| `GET`  | `/delete`  | Confirmation page for a signed takedown link. |
| `POST` | `/delete`  | Performs the takedown (deletes the content file; shared icons stay). |

### `/publish` request body

```json
{
  "displayName": "Tom",
  "websiteURL": "coefficiencies.com",
  "turnstileToken": "<from the Turnstile widget; omit if Turnstile not yet configured>",
  "apps": [
    { "bundleID": "org.videolan.vlc", "name": "VLC", "url": "https://videolan.org",
      "categories": ["Video"], "sizeBytes": 180000000, "favorite": false }
  ]
}
```

## One-time setup

You need a Cloudflare account and a GitHub token. ~10 minutes.

### 1. Install + log in

```sh
cd publish-worker
npm install
npx wrangler login
```

### 2. Create the rate-limit KV namespace

```sh
npx wrangler kv namespace create RL
```

Copy the printed `id` into `wrangler.toml` (replace `REPLACE_WITH_KV_NAMESPACE_ID`).

### 3. Point it at the Hugo repo

In `wrangler.toml`, set `GITHUB_REPO` to the site repo (e.g. `tomrobertson/coefficiencies`)
and confirm `GITHUB_BRANCH` / `SITE_BASE`.

### 4. Add secrets

```sh
# Fine-grained PAT — repo = the Hugo site, Permissions → Contents: Read and write. Nothing else.
npx wrangler secret put GITHUB_TOKEN

# Any long random string (e.g. `openssl rand -hex 32`). Signs delete links.
npx wrangler secret put DELETE_SIGNING_KEY

# Optional but recommended — Discord webhook for "new library" + takedown alerts.
npx wrangler secret put DISCORD_WEBHOOK

# Optional — add when you wire up the Turnstile widget in the app. Until then,
# leave it unset and the captcha check is skipped (rate-limit still applies).
npx wrangler secret put TURNSTILE_SECRET
```

### 5. Deploy

```sh
npx wrangler deploy
```

Wrangler prints the worker URL (e.g. `https://macapplibrary-publish.<you>.workers.dev`).
That URL is what the app's Publish button will POST to.

## Test it

```sh
curl -X POST https://<your-worker-url>/publish \
  -H 'Content-Type: application/json' \
  -d '{"displayName":"Test","websiteURL":"example.com","apps":[
        {"bundleID":"org.videolan.vlc","name":"VLC","url":"https://videolan.org",
         "categories":["Video"],"sizeBytes":180000000,"favorite":true}]}'
# → {"url":"https://coefficiencies.com/shared/abcd2345/","slug":"abcd2345","building":true}
```

Then watch the site repo for the new commit, and the deploy to build the page.
Run `npx wrangler tail` in another terminal to stream logs.

## Notes / gotchas

- **Not instant.** `/publish` returns as soon as the commit lands; the page is
  live only after the push→build deploy runs. The response says `building: true`.
- **Icon budget.** First-time large libraries resolve at most `MAX_ICON_FETCHES`
  (default 30) new icons per publish to stay under the Workers subrequest limit
  (50 on the free plan). Unresolved apps fall back to a CSS letter tile in the
  theme. The shared icon store is bundleID-keyed, so it fills in over time and
  later publishes resolve fewer. Raise the cap on a paid plan.
- **Hugo version.** The site/deploy must run **Hugo ≤ 0.145** until the Congo
  theme is upgraded (see the Todoist inbox task) — unrelated to this worker, but
  it's what renders the committed page.
- **Seed the icon store first.** Commit the 225 already-downloaded icons
  (`scripts/icon-cache/`) into the site repo's `static/app-icons/` so early
  publishes have high coverage. The prototype branch already did this.
