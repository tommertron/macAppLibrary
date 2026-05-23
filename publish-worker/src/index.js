// macAppLibrary "Publish" worker.
//
// POST /publish  — turn a user's library (structured JSON) into a real Hugo page
//                  at SITE_BASE/shared/<slug>/, committed to the site repo.
// GET  /delete   — confirmation page for a signed takedown link.
// POST /delete   — perform the takedown.
//
// Design notes live in scripts/publishing-workflow-spec.md. The load-bearing
// rule: the client sends data only — no HTML, no images, no icon URLs.

import { json, noContent, randomSlug, sign, verify, textToBase64, notifyDiscord } from "./util.js";
import { validatePayload, buildIndexMarkdown } from "./validate.js";
import { listIconStore, commitFiles, deleteSharedPage, GitError } from "./github.js";
import { resolveIcons } from "./icons.js";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return noContent(204);

    if (url.pathname === "/publish" && request.method === "POST") return handlePublish(request, env);
    if (url.pathname === "/delete") return handleDelete(request, env, url);

    return json({ error: "Not found" }, 404);
  },
};

async function handlePublish(request, env) {
  // 1. Captcha (skipped only if no secret configured — staged rollout).
  if (env.TURNSTILE_SECRET) {
    const ok = await verifyTurnstile(request, env);
    if (!ok) return json({ error: "Captcha failed" }, 403);
  }

  // 2. Rate limit: N publishes / IP / day.
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const limited = await rateLimited(env, ip);
  if (limited) return json({ error: "Rate limit reached — try again tomorrow." }, 429);

  // 3. Parse + validate.
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const { ok, errors, clean } = validatePayload(body, env);
  if (!ok) return json({ error: "Validation failed", details: errors }, 400);

  // 4. Resolve icons for bundle IDs not already in the shared store.
  const present = await listIconStore(env);
  const missing = clean.apps.filter((a) => !present.has(a.bundleID));
  // de-dupe missing bundle IDs (a library can list an app twice)
  const seen = new Set();
  const toResolve = missing.filter((a) => (seen.has(a.bundleID) ? false : seen.add(a.bundleID)));
  const resolved = await resolveIcons(toResolve, Number(env.MAX_ICON_FETCHES || 30));

  // iconSet = every bundleID that will have an icon on disk after this commit.
  const iconSet = new Set(present);
  for (const id of resolved.keys()) iconSet.add(id);

  // 5. Build the commit: index.md + any newly-resolved icons.
  const slug = randomSlug();
  const files = [
    { path: `content/shared/${slug}/index.md`, contentBase64: textToBase64(buildIndexMarkdown(clean, iconSet)) },
  ];
  for (const [bundleID, b64] of resolved) {
    files.push({ path: `static/app-icons/${bundleID}.png`, contentBase64: b64 });
  }

  try {
    await commitFiles(env, files, `Publish shared library ${slug} (${clean.apps.length} apps)`);
  } catch (e) {
    if (e instanceof GitError) return json({ error: "Publish failed", step: e.message }, 502);
    throw e;
  }

  const pageURL = `${env.SITE_BASE}/shared/${slug}/`;
  const deleteURL = await buildDeleteURL(request, env, slug);

  // 6. Alert the owner with a one-click takedown link.
  await notifyDiscord(
    env.DISCORD_WEBHOOK,
    `📚 New shared library: **${clean.displayName}** (${clean.apps.length} apps)\n${pageURL}\n🗑️ Takedown: ${deleteURL}`
  );

  // The page is live only after the push→build deploy finishes (not instant).
  return json({ url: pageURL, slug, building: true });
}

async function handleDelete(request, env, url) {
  const slug = url.searchParams.get("slug") || "";
  const sig = url.searchParams.get("sig") || "";
  if (!/^[a-z2-9]+$/.test(slug) || !sig) return htmlPage("Invalid link", 400);
  if (!env.DELETE_SIGNING_KEY) return htmlPage("Delete is not configured.", 500);

  const valid = await verify(env.DELETE_SIGNING_KEY, slug, sig);
  if (!valid) return htmlPage("This delete link is invalid or has expired.", 403);

  // GET → confirmation page (avoids accidental deletion from link prefetch).
  if (request.method === "GET") {
    return htmlPage(
      `<h1>Remove this shared library?</h1>
       <p><code>/shared/${slug}/</code></p>
       <form method="POST">
         <input type="hidden" name="slug" value="${slug}">
         <input type="hidden" name="sig" value="${sig}">
         <button type="submit">Delete it</button>
       </form>`,
      200
    );
  }

  // POST → perform the takedown.
  try {
    const existed = await deleteSharedPage(env, slug, `Takedown shared library ${slug}`);
    await notifyDiscord(env.DISCORD_WEBHOOK, `🗑️ Took down /shared/${slug}/ (existed: ${existed})`);
    return htmlPage(existed ? `Removed <code>/shared/${slug}/</code>.` : "Already gone.", 200);
  } catch (e) {
    return htmlPage("Delete failed — check the worker logs.", 502);
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

async function verifyTurnstile(request, env) {
  // Token can ride in the JSON body or an X-Turnstile-Token header; peek without
  // consuming the body stream the handler still needs.
  let token = request.headers.get("X-Turnstile-Token") || "";
  if (!token) {
    try {
      const clone = request.clone();
      token = (await clone.json())?.turnstileToken || "";
    } catch {
      /* fall through */
    }
  }
  if (!token) return false;
  const form = new FormData();
  form.append("secret", env.TURNSTILE_SECRET);
  form.append("response", token);
  form.append("remoteip", request.headers.get("CF-Connecting-IP") || "");
  const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    body: form,
  });
  const data = await res.json().catch(() => ({}));
  return data.success === true;
}

async function rateLimited(env, ip) {
  if (!env.RL) return false; // KV not bound (e.g. local dev) → don't block
  const day = new Date().toISOString().slice(0, 10);
  const key = `rl:${ip}:${day}`;
  const count = Number((await env.RL.get(key)) || 0);
  if (count >= 5) return true;
  await env.RL.put(key, String(count + 1), { expirationTtl: 86400 });
  return false;
}

async function buildDeleteURL(request, env, slug) {
  const origin = new URL(request.url).origin;
  if (!env.DELETE_SIGNING_KEY) return `${origin}/delete?slug=${slug}&sig=UNCONFIGURED`;
  const sig = await sign(env.DELETE_SIGNING_KEY, slug);
  return `${origin}/delete?slug=${slug}&sig=${sig}`;
}

function htmlPage(inner, status) {
  return new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
     <title>macAppLibrary</title>
     <body style="font-family:system-ui;max-width:32rem;margin:4rem auto;padding:0 1rem;line-height:1.5">${inner}</body>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}
