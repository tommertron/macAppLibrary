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

    // One file per app — bundle ID becomes the filename.
    const filePath = `community-data/${bundleID}.json`;

    // Build the entry that will be written.
    const entry = { name, description, categories: categories ?? [] };
    if (developer) entry.developer = developer;
    if (url) entry.url = url;

    const updatedContent = btoa(unescape(encodeURIComponent(JSON.stringify(entry, null, 2) + "\n")));

    // Check whether this file already exists on main (update vs add).
    let existingSha = null;
    let isNew = true;
    const existingRes = await fetch(
      `https://api.github.com/repos/${repo}/contents/${encodeURIComponent(filePath)}?ref=${BRANCH_BASE}`,
      { headers }
    );
    if (existingRes.ok) {
      const existingData = await existingRes.json();
      existingSha = existingData.sha;
      isNew = false;
    } else if (existingRes.status !== 404) {
      return corsResponse(JSON.stringify({ error: "Failed to check existing file" }), 502);
    }

    // Branch off the latest main.
    const refRes = await fetch(`https://api.github.com/repos/${repo}/git/ref/heads/${BRANCH_BASE}`, { headers });
    if (!refRes.ok) {
      return corsResponse(JSON.stringify({ error: "Failed to fetch base ref" }), 502);
    }
    const refData = await refRes.json();
    const baseSha = refData.object.sha;

    const branchName = `submit/${bundleID.replace(/[^a-zA-Z0-9]/g, "-")}-${Date.now()}`;
    const createBranchRes = await fetch(`https://api.github.com/repos/${repo}/git/refs`, {
      method: "POST",
      headers,
      body: JSON.stringify({ ref: `refs/heads/${branchName}`, sha: baseSha }),
    });
    if (!createBranchRes.ok) {
      return corsResponse(JSON.stringify({ error: "Failed to create branch" }), 502);
    }

    // Write the per-bundle file on the new branch.
    const commitBody = {
      message: `Add community data for ${name} (${bundleID})`,
      content: updatedContent,
      branch: branchName,
    };
    if (existingSha) commitBody.sha = existingSha;

    const commitRes = await fetch(`https://api.github.com/repos/${repo}/contents/${encodeURIComponent(filePath)}`, {
      method: "PUT",
      headers,
      body: JSON.stringify(commitBody),
    });
    if (!commitRes.ok) {
      const err = await commitRes.text();
      return corsResponse(JSON.stringify({ error: "Failed to commit file", detail: err }), 502);
    }

    // Open the PR.
    const action = isNew ? "Add" : "Update";
    const prRes = await fetch(`https://api.github.com/repos/${repo}/pulls`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        title: `[Community] ${action} ${name}`,
        body: `Community submission from macAppLibrary app.\n\n**Bundle ID:** \`${bundleID}\`\n**Name:** ${name}\n**Developer:** ${developer ?? "—"}\n**URL:** ${url ?? "—"}\n\n> Please review the description and category before merging. After merge, \`community-data.json\` is regenerated automatically.`,
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
