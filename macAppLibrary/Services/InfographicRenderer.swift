import AppKit
import Foundation

/// Renders a self-contained HTML infographic of the user's app library.
///
/// Design language is lifted from the coefficiencies.com style sheet —
/// neutral-50 background, orange accent (#f97316), serif display headings,
/// 14px-radius cards with a thin top accent on hover.
///
/// Icons are embedded as base64 PNG data URIs so the resulting document is
/// fully self-contained (no asset paths to break when shared).
enum InfographicRenderer {

    static func render(apps: [AppEntry], config: InfographicConfig) -> String {
        let included = apps
            .filter { config.isIncluded($0.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let total = included.count
        let favorites = included.filter(\.isFavorite)
        let categoryCounts = categoryCounts(for: included)

        // Size loads asynchronously after the initial scan, so some entries may
        // not have it yet — sum what's available and flag if any are missing.
        let knownSizes = included.compactMap(\.sizeBytes)
        let totalBytes = knownSizes.reduce(0, +)
        let sizesIncomplete = knownSizes.count < total

        let safeName = htmlEscape(config.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? "My"
                                  : config.displayName)

        let websiteLine: String = {
            let raw = config.websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return "" }
            let href = raw.contains("://") ? raw : "https://\(raw)"
            return #"<a class="site-link" href="\#(htmlEscape(href))">\#(htmlEscape(raw))</a>"#
        }()

        let statsBand = statsBand(total: total,
                                  totalBytes: totalBytes,
                                  sizesIncomplete: sizesIncomplete,
                                  favoriteCount: favorites.count,
                                  categoryCount: categoryCounts.count)
        let categorySection = categorySection(categoryCounts)
        let favoritesSection = favoritesSection(favorites)
        let cards = included.map(card(for:)).joined(separator: "\n      ")

        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <title>\(safeName)’s Mac App Library</title>
          <style>\(css)</style>
        </head>
        <body>
          <div class="page">
            <header class="hero">
              <h1>\(safeName)’s Mac App Library</h1>
              \(websiteLine)
            </header>
            \(statsBand)
            \(categorySection)
            \(favoritesSection)
            <section class="apps">
              <h2 class="section-heading">All Apps</h2>
              <div class="grid">
                \(cards)
              </div>
            </section>
            <footer class="footer">
              Created with <a href="https://coefficiencies.com/apps/macapplibrary/">macAppLibrary</a>
            </footer>
          </div>
        </body>
        </html>
        """
    }

    // MARK: - Stats

    private static func statsBand(total: Int,
                                  totalBytes: Int64,
                                  sizesIncomplete: Bool,
                                  favoriteCount: Int,
                                  categoryCount: Int) -> String {
        var blocks: [String] = [
            statBlock(num: "\(total)", label: total == 1 ? "App" : "Apps")
        ]
        if totalBytes > 0 {
            let size = formatBytes(totalBytes)
            blocks.append(statBlock(num: size,
                                    label: sizesIncomplete ? "Total Size (so far)" : "Total Size"))
        }
        if favoriteCount > 0 {
            blocks.append(statBlock(num: "\(favoriteCount)",
                                    label: favoriteCount == 1 ? "Favorite" : "Favorites"))
        }
        blocks.append(statBlock(num: "\(categoryCount)",
                                label: categoryCount == 1 ? "Category" : "Categories"))

        return #"""
        <section class="stats-band">
              \#(blocks.joined(separator: "\n      "))
            </section>
        """#
    }

    private static func statBlock(num: String, label: String) -> String {
        #"""
        <div class="stat-block">
                <div class="stat-num">\#(htmlEscape(num))</div>
                <div class="stat-label">\#(htmlEscape(label))</div>
              </div>
        """#
    }

    /// App counts per category, highest first. Apps with multiple categories
    /// are counted under each.
    private static func categoryCounts(for apps: [AppEntry]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for app in apps {
            for cat in app.effectiveCategories where !cat.isEmpty {
                counts[cat, default: 0] += 1
            }
        }
        return counts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count
                                           : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func categorySection(_ categories: [(name: String, count: Int)]) -> String {
        guard !categories.isEmpty else { return "" }
        let maxCount = categories.first?.count ?? 1
        let rows = categories.map { cat -> String in
            let pct = maxCount > 0 ? Int((Double(cat.count) / Double(maxCount)) * 100) : 0
            return #"""
            <div class="cat-row">
                  <span class="cat-name">\#(htmlEscape(cat.name))</span>
                  <span class="cat-bar"><span class="cat-fill" style="width:\#(pct)%"></span></span>
                  <span class="cat-count">\#(cat.count)</span>
                </div>
            """#
        }.joined(separator: "\n      ")

        return #"""
        <section class="cat-section">
              <h2 class="section-heading">By Category</h2>
              <div class="cat-list">
                \#(rows)
              </div>
            </section>
        """#
    }

    private static func favoritesSection(_ favorites: [AppEntry]) -> String {
        guard !favorites.isEmpty else { return "" }
        let cards = favorites.map(card(for:)).joined(separator: "\n      ")
        return #"""
        <section class="favorites">
              <h2 class="section-heading">★ Favorites</h2>
              <div class="grid">
                \#(cards)
              </div>
            </section>
        """#
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useMB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    // MARK: - Cards

    private static func card(for app: AppEntry) -> String {
        let icon = iconDataURI(forBundlePath: app.bundlePath)
        let name = htmlEscape(app.name)
        let inner = #"""
        <img class="icon" src="\#(icon)" alt="">
              <div class="name">\#(name)</div>
        """#

        if let raw = app.effectiveWebsiteURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            let href = raw.contains("://") ? raw : "https://\(raw)"
            return #"""
            <a class="app-card linked" href="\#(htmlEscape(href))" title="\#(name)">
              \#(inner)
            </a>
            """#
        }
        return #"""
        <div class="app-card" title="\#(name)">
          \#(inner)
        </div>
        """#
    }

    // MARK: - Icons

    /// Returns a `data:image/png;base64,…` URI for the app icon at `path`,
    /// rendered to a fixed 128×128 PNG so all icons in the grid match weight.
    private static func iconDataURI(forBundlePath path: String) -> String {
        let source = NSWorkspace.shared.icon(forFile: path)
        let target = NSSize(width: 128, height: 128)

        let resized = NSImage(size: target)
        resized.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target),
                    from: .zero,
                    operation: .copy,
                    fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            // Fall back to a 1×1 transparent pixel rather than breaking the grid.
            return "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    // MARK: - Escaping

    private static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    // MARK: - CSS

    /// Inline CSS — mirrors the design tokens from coefficiencies.com so the
    /// shared infographic feels like it belongs to the same family of pages.
    private static let css = """
    :root {
      --bg: rgb(250, 250, 249);
      --card-bg: #ffffff;
      --border: rgb(231, 229, 228);
      --text: rgb(41, 37, 36);
      --muted: rgb(120, 113, 108);
      --accent: rgb(249, 115, 22);
      --accent-hover: rgb(234, 88, 12);
      --serif: ui-serif, Georgia, Cambria, "Times New Roman", serif;
      --sans: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      --shadow-sm: 0 1px 3px rgba(41,37,36,.08), 0 1px 2px rgba(41,37,36,.05);
      --shadow-md: 0 4px 12px rgba(41,37,36,.10), 0 2px 4px rgba(41,37,36,.06);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: rgb(28, 25, 23);
        --card-bg: rgb(41, 37, 36);
        --border: rgb(68, 64, 60);
        --text: rgb(245, 245, 244);
        --muted: rgb(168, 162, 158);
        --accent: rgb(251, 146, 60);
        --accent-hover: rgb(253, 186, 116);
      }
    }
    * { box-sizing: border-box; }
    html, body {
      margin: 0;
      padding: 0;
      background: var(--bg);
      color: var(--text);
      font-family: var(--sans);
      -webkit-font-smoothing: antialiased;
    }
    .page {
      max-width: 1100px;
      margin: 0 auto;
      padding: 3rem 2rem 4rem;
    }
    .hero { text-align: center; margin-bottom: 2.5rem; }
    .hero h1 {
      font-family: var(--serif);
      font-weight: 600;
      font-size: 2.5rem;
      line-height: 1.15;
      letter-spacing: -0.01em;
      margin: 0 0 0.5rem;
    }
    .site-link {
      display: inline-block;
      margin-bottom: 1rem;
      color: var(--accent);
      text-decoration: none;
      font-size: 0.95rem;
    }
    .site-link:hover { color: var(--accent-hover); text-decoration: underline; }

    .stats-band {
      display: flex;
      flex-wrap: wrap;
      justify-content: center;
      gap: 1rem 2.5rem;
      padding: 1.5rem 1rem;
      margin-bottom: 2.5rem;
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: var(--shadow-sm);
    }
    .stat-block { text-align: center; min-width: 5rem; }
    .stat-num {
      font-family: var(--serif);
      font-weight: 600;
      font-size: 2rem;
      line-height: 1.1;
      color: var(--accent);
    }
    .stat-label {
      margin-top: 0.25rem;
      font-size: 0.7rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      color: var(--muted);
    }

    .section-heading {
      font-family: var(--serif);
      font-weight: 600;
      font-size: 1.375rem;
      margin: 0 0 1rem;
    }
    .cat-section, .favorites { margin-bottom: 2.5rem; }

    .cat-list {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 0.5rem 2rem;
    }
    .cat-row {
      display: grid;
      grid-template-columns: 1fr 4rem auto;
      align-items: center;
      gap: 0.75rem;
    }
    .cat-name { font-size: 0.9rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .cat-bar {
      height: 8px;
      border-radius: 999px;
      background: var(--accent-light, rgba(249,115,22,.15));
      overflow: hidden;
    }
    .cat-fill { display: block; height: 100%; background: var(--accent); border-radius: 999px; }
    .cat-count {
      font-variant-numeric: tabular-nums;
      font-weight: 600;
      font-size: 0.85rem;
      color: var(--muted);
      text-align: right;
    }

    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
      gap: 1rem;
    }
    .app-card {
      position: relative;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0.625rem;
      padding: 1rem 0.75rem 0.875rem;
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 14px;
      box-shadow: var(--shadow-sm);
      color: inherit;
      text-decoration: none;
      transition: box-shadow 200ms ease, transform 200ms ease, border-color 200ms ease;
    }
    a.app-card.linked { cursor: pointer; }
    a.app-card.linked:hover {
      box-shadow: var(--shadow-md);
      transform: translateY(-2px);
      border-color: var(--accent);
    }
    a.app-card.linked::after {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 3px;
      background: var(--accent);
      opacity: 0;
      transition: opacity 200ms ease;
    }
    a.app-card.linked:hover::after { opacity: 1; }
    .icon {
      width: 64px; height: 64px;
      image-rendering: -webkit-optimize-contrast;
    }
    .name {
      font-size: 0.85rem;
      font-weight: 500;
      text-align: center;
      line-height: 1.25;
      word-break: break-word;
    }
    .footer {
      text-align: center;
      margin-top: 3rem;
      color: var(--muted);
      font-size: 0.85rem;
    }
    .footer a { color: var(--accent); text-decoration: none; }
    .footer a:hover { text-decoration: underline; }
    """
}
