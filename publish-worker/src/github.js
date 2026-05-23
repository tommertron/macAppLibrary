// GitHub commits via the Git Data API: one atomic commit carrying the new
// content file plus any newly-resolved icons. (The community-submissions worker
// PUTs one file per commit; here we batch so a publish is a single commit.)

const API = "https://api.github.com";

function headers(env) {
  return {
    Authorization: `Bearer ${env.GITHUB_TOKEN}`,
    Accept: "application/vnd.github+json",
    "User-Agent": "macapplibrary-publish-worker",
    "Content-Type": "application/json",
  };
}

async function gh(env, path, init = {}) {
  const res = await fetch(`${API}/repos/${env.GITHUB_REPO}${path}`, {
    ...init,
    headers: { ...headers(env), ...(init.headers || {}) },
  });
  return res;
}

// bundle IDs already present in static/app-icons/ (so we only commit new icons).
export async function listIconStore(env) {
  const set = new Set();
  const res = await gh(env, `/contents/static/app-icons?ref=${env.GITHUB_BRANCH}`);
  if (!res.ok) return set; // empty/missing dir → treat as no icons yet
  const items = await res.json();
  for (const it of items) {
    if (it.type === "file" && it.name.endsWith(".png")) set.add(it.name.slice(0, -4));
  }
  return set;
}

// files: [{ path, contentBase64, encoding: "base64"|"utf-8" }]
export async function commitFiles(env, files, message) {
  // Resolve current tip of the branch.
  const refRes = await gh(env, `/git/ref/heads/${env.GITHUB_BRANCH}`);
  if (!refRes.ok) throw new GitError("fetch base ref", await refRes.text());
  const baseCommitSha = (await refRes.json()).object.sha;

  const commitRes = await gh(env, `/git/commits/${baseCommitSha}`);
  if (!commitRes.ok) throw new GitError("fetch base commit", await commitRes.text());
  const baseTreeSha = (await commitRes.json()).tree.sha;

  // Create a blob per file.
  const treeEntries = [];
  for (const f of files) {
    const blobRes = await gh(env, "/git/blobs", {
      method: "POST",
      body: JSON.stringify({ content: f.contentBase64, encoding: "base64" }),
    });
    if (!blobRes.ok) throw new GitError(`create blob ${f.path}`, await blobRes.text());
    treeEntries.push({ path: f.path, mode: "100644", type: "blob", sha: (await blobRes.json()).sha });
  }

  const treeRes = await gh(env, "/git/trees", {
    method: "POST",
    body: JSON.stringify({ base_tree: baseTreeSha, tree: treeEntries }),
  });
  if (!treeRes.ok) throw new GitError("create tree", await treeRes.text());
  const newTreeSha = (await treeRes.json()).sha;

  const newCommitRes = await gh(env, "/git/commits", {
    method: "POST",
    body: JSON.stringify({ message, tree: newTreeSha, parents: [baseCommitSha] }),
  });
  if (!newCommitRes.ok) throw new GitError("create commit", await newCommitRes.text());
  const newCommitSha = (await newCommitRes.json()).sha;

  const updateRes = await gh(env, `/git/refs/heads/${env.GITHUB_BRANCH}`, {
    method: "PATCH",
    body: JSON.stringify({ sha: newCommitSha }),
  });
  if (!updateRes.ok) throw new GitError("update ref", await updateRes.text());

  return newCommitSha;
}

// Remove a published library: delete its content file (icons are shared, left in place).
export async function deleteSharedPage(env, slug, message) {
  const path = `content/shared/${slug}/index.md`;
  const getRes = await gh(env, `/contents/${path}?ref=${env.GITHUB_BRANCH}`);
  if (getRes.status === 404) return false;
  if (!getRes.ok) throw new GitError("locate page", await getRes.text());
  const sha = (await getRes.json()).sha;

  const delRes = await gh(env, `/contents/${path}`, {
    method: "DELETE",
    body: JSON.stringify({ message, sha, branch: env.GITHUB_BRANCH }),
  });
  if (!delRes.ok) throw new GitError("delete page", await delRes.text());
  return true;
}

export class GitError extends Error {
  constructor(step, detail) {
    super(`GitHub: ${step}`);
    this.detail = detail;
  }
}
