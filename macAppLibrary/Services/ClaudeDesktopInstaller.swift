import Foundation

enum ClaudeDesktopInstaller {
    static let serverKey = "macAppLibrary"

    enum InstallResult: Equatable {
        case installed
        case updated
        case alreadyInstalled
    }

    enum InstallError: LocalizedError {
        case claudeDesktopNotInstalled
        case configUnreadable(String)
        case configMalformed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeDesktopNotInstalled:
                return "Claude Desktop doesn't appear to be installed. Install it from claude.ai/download, then try again."
            case .configUnreadable(let detail):
                return "Couldn't read Claude Desktop's config file: \(detail)"
            case .configMalformed:
                return "Claude Desktop's config file isn't valid JSON. Open it in a text editor and fix the syntax, then try again."
            case .writeFailed(let detail):
                return "Couldn't write Claude Desktop's config file: \(detail)"
            }
        }
    }

    static var configURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Claude")
            .appendingPathComponent("claude_desktop_config.json")
    }

    static var claudeAppURL: URL {
        URL(fileURLWithPath: "/Applications/Claude.app")
    }

    static func install(port: Int, token: String) throws -> InstallResult {
        guard FileManager.default.fileExists(atPath: claudeAppURL.path) else {
            throw InstallError.claudeDesktopNotInstalled
        }

        let url = configURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                if !data.isEmpty {
                    guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw InstallError.configMalformed
                    }
                    root = parsed
                }
            } catch let error as InstallError {
                throw error
            } catch {
                throw InstallError.configUnreadable(error.localizedDescription)
            }
        }

        let entry: [String: Any] = [
            "command": "npx",
            "args": [
                "-y",
                "mcp-remote",
                "http://127.0.0.1:\(port)/mcp",
                "--header",
                "Authorization:${AUTH_HEADER}",
                "--allow-http",
                "--transport",
                "http-only"
            ],
            "env": [
                "AUTH_HEADER": "Bearer \(token)"
            ]
        ]

        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        let existing = servers[serverKey] as? [String: Any]
        let result: InstallResult
        if let existing, NSDictionary(dictionary: existing).isEqual(to: entry) {
            return .alreadyInstalled
        } else {
            result = (existing == nil) ? .installed : .updated
        }
        servers[serverKey] = entry
        root["mcpServers"] = servers

        do {
            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            throw InstallError.writeFailed(error.localizedDescription)
        }

        return result
    }
}
