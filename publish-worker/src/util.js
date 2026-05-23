// Small shared helpers: responses, slugs, signing, YAML, alerts.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

export function noContent(status = 204) {
  return new Response(null, { status, headers: CORS });
}

// Unambiguous slug alphabet (no 0/o/1/l/i) → /shared/<slug>/, never derived from the name.
const SLUG_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
export function randomSlug(len = 8) {
  const bytes = crypto.getRandomValues(new Uint8Array(len));
  let s = "";
  for (const b of bytes) s += SLUG_ALPHABET[b % SLUG_ALPHABET.length];
  return s;
}

// HMAC-SHA256 hex, used to sign one-click delete links.
async function hmacKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
}
export async function sign(secret, message) {
  const key = await hmacKey(secret);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
export async function verify(secret, message, expected) {
  const actual = await sign(secret, message);
  // constant-time-ish compare
  if (actual.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < actual.length; i++) diff |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

// Minimal YAML double-quoted scalar — escapes backslash and quote.
export function yaml(s) {
  return `"${String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

export function bytesToBase64(buf) {
  const bytes = new Uint8Array(buf);
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

export function textToBase64(str) {
  return btoa(unescape(encodeURIComponent(str)));
}

// Fire-and-forget Discord alert; never blocks or fails the request.
export async function notifyDiscord(webhook, content) {
  if (!webhook) return;
  try {
    await fetch(webhook, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content }),
    });
  } catch {
    /* alerts are best-effort */
  }
}
