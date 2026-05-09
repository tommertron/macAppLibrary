#!/usr/bin/env node
// Minimal stdio <-> HTTP bridge between Claude Desktop and a running
// macAppLibrary instance. Reads newline-delimited JSON-RPC messages on
// stdin, forwards each to http://127.0.0.1:$PORT/mcp with a Bearer token,
// and writes the JSON-RPC response back on stdout. Stderr is reserved for
// logging (Claude Desktop tails it into mcp-server-macAppLibrary.log).

const PORT = process.env.MACAPPLIBRARY_PORT;
const TOKEN = process.env.MACAPPLIBRARY_TOKEN;

if (!PORT || !TOKEN) {
  console.error("macAppLibrary proxy: missing MACAPPLIBRARY_PORT or MACAPPLIBRARY_TOKEN env var");
  process.exit(1);
}

const ENDPOINT = `http://127.0.0.1:${PORT}/mcp`;

let buffer = "";
process.stdin.setEncoding("utf8");

process.stdin.on("data", (chunk) => {
  buffer += chunk;
  let nl;
  while ((nl = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, nl).trim();
    buffer = buffer.slice(nl + 1);
    if (line) handle(line);
  }
});

process.stdin.on("end", () => process.exit(0));

async function handle(line) {
  let req;
  try {
    req = JSON.parse(line);
  } catch (e) {
    console.error("macAppLibrary proxy: invalid JSON on stdin:", e.message);
    return;
  }

  try {
    const resp = await fetch(ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${TOKEN}`,
      },
      body: line,
    });

    // Notifications: server returns 202 with empty body, no stdout reply.
    if (resp.status === 202) return;

    const text = await resp.text();
    if (text) process.stdout.write(text + "\n");
  } catch (e) {
    // Surface a JSON-RPC error so Claude can show something useful instead
    // of silently failing. Notifications (no id) get logged only.
    if (req && req.id !== undefined && req.id !== null) {
      const err = {
        jsonrpc: "2.0",
        id: req.id,
        error: {
          code: -32603,
          message: `macAppLibrary not reachable at ${ENDPOINT}. Is the app running with the MCP server enabled? (${e.message})`,
        },
      };
      process.stdout.write(JSON.stringify(err) + "\n");
    } else {
      console.error("macAppLibrary proxy: forward failed:", e.message);
    }
  }
}
