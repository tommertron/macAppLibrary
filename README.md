# macAppLibrary

<div align="center">
  <img src="macAppLibraryIcon.png" alt="macAppLibrary icon" width="120" />
  <br /><br />
  <a href="https://www.buymeacoffee.com/coefficiencies"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&emoji=&slug=coefficiencies&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff" alt="Buy Me A Coffee" height="40" /></a>
</div>

---

Do you ever feel like you have more apps on your Mac than you know what to do with? What was that app you downloaded last week that you forgot about? What was that image converter called again? If these questions resonate with you, **macAppLibrary** is the app for you.

macAppLibrary scans all of the Mac apps you have installed and presents them in a list or gallery with useful information like descriptions and developer names. From there, you can add your own descriptions, notes, and categories — or enter your Anthropic API key and let AI generate descriptions for you.

If your app is in the community database, you can pull information automatically. And if you've added info about an app yourself, you can contribute it back to the community right from macAppLibrary.

**macAppLibrary is free and open source.**

## Download

[⬇️ Download macAppLibrary (.dmg)](https://coefficiencies.com/apps/macapplibrary/)

[View Changelog](https://coefficiencies.com/apps/macapplibrary/changelog/)

## Screenshots

![Gallery View](https://coefficiencies.com/apps/macapplibrary/macAppLibrary-Gallery-View_compressed_hu_7bcf405e13cc3a04.png)
![List View](https://coefficiencies.com/apps/macapplibrary/macAppLibrary-List-View_compressed_hu_ce2e4adf06c15c15.png)

## Features

- Organizes apps into sidebar sections by category, developer, and more
- Shows your currently running applications — close them right from macAppLibrary
- Identifies unused apps, recently installed, and recently updated apps, with configurable time thresholds
- Full search across app names, descriptions, and categories
- AI-powered description generation via the Anthropic API
- Pull app info from the community database, per field or all at once
- Submit your app info to the community (all submissions are reviewed before acceptance)
- Reveal any app in Finder
- Open apps directly from the library

## Setup

Just install macAppLibrary and open it — it will immediately begin scanning your applications.

### AI Descriptions

To use AI-generated descriptions, you'll need an API key from [Anthropic](https://console.anthropic.com). Once you have one, open **Settings** and paste it in. Then click **Generate with AI** next to any app's description.

### Community App Information

App info can be pulled from the community database per-field or all at once.

- **Per-field:** A coloured icon appears next to each field (description, developer, categories, website). **Green** means community data is available and differs from yours — click to pull it. **Grey** means your data already matches. **Red** means no community data exists for that field.
- **Pull All:** Click the **Pull All** button in the Community section of any app to import all available community data for that app at once.
- **Import all apps:** Use **File → Import All Community Data** to refresh community data across your entire library.

To contribute back, click **Submit to Community** on any app page, or use **File → Submit All Changes to Community** to submit info for every app where your data differs from the community. Submissions create a pull request on [GitHub](https://github.com/tommertron/macAppLibrary/blob/main/community-data.json) and are reviewed before being merged.

## Community Data

Each app in the community database is its own file under [`community-data/`](community-data/), named by bundle ID — e.g. `community-data/com.example.AppName.json`:

```json
{
  "name": "App Name",
  "description": "What this app does.",
  "categories": ["Productivity"],
  "developer": "Developer Name",
  "url": "https://example.com"
}
```

The monolithic [`community-data.json`](community-data.json) at the repo root is regenerated automatically from the directory by CI on every merge to `main`, and is what the app actually fetches. This split keeps community submissions free of merge conflicts (each PR touches one file).

Contributions via the in-app submit flow are welcome and appreciated.

## Local API

While macAppLibrary is open, it runs a local HTTP server on `127.0.0.1` so other tools — Raycast extensions, CLIs, MCP servers, Alfred workflows — can read your library, edit metadata, pull/submit community data, and trigger AI descriptions.

**Discovery.** On launch the app writes:

```
~/Library/Application Support/macAppLibrary/api.json
```

containing `{host, port, token, pid, apiVersion}` with mode `0600`. Clients should read this file, verify `kill(pid, 0) == 0` (the file can linger across crashes — it is overwritten atomically on the next launch), then send `Authorization: Bearer <token>` on every request except `/v1/health` and `/v1/version`.

**Reference.** Full OpenAPI documentation: <https://tommertron.github.io/macAppLibrary/>

### MCP (Claude Desktop, etc.)

The same server can expose an [MCP](https://modelcontextprotocol.io) endpoint at `POST /mcp` so MCP-aware tools — Claude Desktop, IDE plugins — can read and edit your library directly. It's off by default; turn it on under **Settings → MCP Server**.

**Connecting to Claude Desktop.** Two options, both require [Claude Desktop](https://claude.ai/download) and [Node.js](https://nodejs.org) (for `npx`) to be installed. Claude Desktop only supports stdio MCP servers natively, so the config uses [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) as a thin stdio→HTTP bridge to the local server.

- **One click:** click **Install for Claude Desktop**. macAppLibrary merges its entry into `~/Library/Application Support/Claude/claude_desktop_config.json` and offers to restart Claude Desktop so the new server is picked up.
- **Manual:** click **Copy config** and paste the snippet into `~/Library/Application Support/Claude/claude_desktop_config.json` yourself, then restart Claude Desktop.

The bearer token in the config is the same one used by the REST API and is stored in your Keychain.

Tools exposed: `list_apps`, `get_app`, `update_app_metadata`, `quit_app`, `list_categories`, `get_community_data`, `pull_community_data`, `submit_to_community`, `generate_ai_description`. Each mirrors its REST counterpart.

## Building from Source

Requires Xcode 15+ and macOS 14.0+.

```bash
git clone https://github.com/tommertron/macAppLibrary.git
cd macAppLibrary
open macAppLibrary.xcodeproj
```

To build a signed, notarized DMG (requires a Developer ID certificate and notarytool credentials):

```bash
./build.sh
```

## License

MIT
