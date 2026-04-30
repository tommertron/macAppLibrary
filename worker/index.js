const COMMUNITY_FILE = "community-data.json";
const BRANCH_BASE = "main";

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return corsResponse(null, 204);
    }
    if (request.method !== "POST") {
      return corsResponse(JSON.stringify({ error: "Method not allowed" }), 405);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return corsResponse(JSON.stringify({ error: "Invalid JSON" }), 400);
    }

    const { bundleID, name, description, categories, developer, url } = body;
    if (!bundleID || !name || !description) {
      return corsResponse(JSON.stringify({ error: "bundleID, name, and description are required" }), 400);
    }

    const repo = env.GITHUB_REPO;
    const token = env.GITHUB_TOKEN;
    const headers = {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "macAppLibrary-worker",
      "Content-Type": "application/json",
    };

    // Fetch current file + sha
    const fileRes = await fetch(
      `https://api.github.com/repos/${repo}/contents/${COMMUNITY_FILE}?ref=${BRANCH_BASE}`,
      { headers }
    );
    if (!fileRes.ok) {
      return corsResponse(JSON.stringify({ error: "Failed to fetch community file" }), 502);
    }
    const fileData = await fileRes.json();
    const fileSha = fileData.sha;
    const rawBytes = Uint8Array.from(atob(fileData.content.replace(/\n/g, "")), c => c.charCodeAt(0));
    const existing = JSON.parse(new TextDecoder().decode(rawBytes));

    // Build the new entry
    const entry = { name, description, categories: categories ?? [] };
    if (developer) entry.developer = developer;
    if (url) entry.url = url;

    const isNew = !(bundleID in existing);
    existing[bundleID] = entry;

    const updatedContent = btoa(unescape(encodeURIComponent(JSON.stringify(existing, null, 2) + "\n")));

    // Create a branch
    const branchName = `submit/${bundleID.replace(/[^a-zA-Z0-9]/g, "-")}-${Date.now()}`;

    const refRes = await fetch(`https://api.github.com/repos/${repo}/git/ref/heads/${BRANCH_BASE}`, { headers });
    const refData = await refRes.json();
    const baseSha = refData.object.sha;

    const createBranchRes = await fetch(`https://api.github.com/repos/${repo}/git/refs`, {
      method: "POST",
      headers,
      body: JSON.stringify({ ref: `refs/heads/${branchName}`, sha: baseSha }),
    });
    if (!createBranchRes.ok) {
      return corsResponse(JSON.stringify({ error: "Failed to create branch" }), 502);
    }

    // Commit the updated file to the branch
    const commitRes = await fetch(`https://api.github.com/repos/${repo}/contents/${COMMUNITY_FILE}`, {
      method: "PUT",
      headers,
      body: JSON.stringify({
        message: `Add community data for ${name} (${bundleID})`,
        content: updatedContent,
        sha: fileSha,
        branch: branchName,
      }),
    });
    if (!commitRes.ok) {
      return corsResponse(JSON.stringify({ error: "Failed to commit file" }), 502);
    }

    // Open the PR
    const action = isNew ? "Add" : "Update";
    const prRes = await fetch(`https://api.github.com/repos/${repo}/pulls`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        title: `[Community] ${action} ${name}`,
        body: `Community submission from macAppLibrary app.\n\n**Bundle ID:** \`${bundleID}\`\n**Name:** ${name}\n**Developer:** ${developer ?? "—"}\n**URL:** ${url ?? "—"}\n\n> Please review the description and category before merging.`,
        head: branchName,
        base: BRANCH_BASE,
      }),
    });
    if (!prRes.ok) {
      const err = await prRes.text();
      return corsResponse(JSON.stringify({ error: "Failed to create PR", detail: err }), 502);
    }
    const pr = await prRes.json();

    return corsResponse(JSON.stringify({ prURL: pr.html_url, prNumber: pr.number }), 200);
  },
};

function corsResponse(body, status) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
