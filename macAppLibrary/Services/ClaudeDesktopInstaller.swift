import Foundation
import AppKit

enum ClaudeDesktopInstaller {
    enum InstallError: LocalizedError {
        case claudeDesktopNotInstalled
        case bundleResourceMissing
        case manifestMalformed
        case zipFailed(String)
        case openFailed(String)

        var errorDescription: String? {
            switch self {
            case .claudeDesktopNotInstalled:
                return "Claude Desktop doesn't appear to be installed. Install it from claude.ai/download, then try again."
            case .bundleResourceMissing:
                return "macAppLibrary's MCP bundle template is missing from the app — try reinstalling macAppLibrary."
            case .manifestMalformed:
                return "MCP bundle manifest is malformed — try reinstalling macAppLibrary."
            case .zipFailed(let detail):
                return "Couldn't build the MCP bundle: \(detail)"
            case .openFailed(let detail):
                return "Couldn't hand the MCP bundle to Claude Desktop: \(detail)"
            }
        }
    }

    static var claudeAppURL: URL {
        URL(fileURLWithPath: "/Applications/Claude.app")
    }

    /// Build a per-install .mcpb file with the current port + token baked into
    /// the manifest's env, then hand it to Claude Desktop via NSWorkspace.open.
    /// Claude Desktop shows a native install prompt; the user clicks Install.
    @discardableResult
    static func installMCPB(port: Int, token: String) throws -> URL {
        guard FileManager.default.fileExists(atPath: claudeAppURL.path) else {
            throw InstallError.claudeDesktopNotInstalled
        }

        guard let templateURL = Bundle.main.url(forResource: "mcpb", withExtension: nil) else {
            throw InstallError.bundleResourceMissing
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("macapplibrary-mcpb-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        // Copy template files into a writable temp dir.
        let stageDir = workDir.appendingPathComponent("stage", isDirectory: true)
        try fm.copyItem(at: templateURL, to: stageDir)

        // Patch the manifest: replace ${user_config.*} env values with concrete
        // values and drop the user_config block so Claude Desktop doesn't prompt.
        let manifestURL = stageDir.appendingPathComponent("manifest.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw InstallError.manifestMalformed
        }

        var server = (manifest["server"] as? [String: Any]) ?? [:]
        var mcpConfig = (server["mcp_config"] as? [String: Any]) ?? [:]
        mcpConfig["env"] = [
            "MACAPPLIBRARY_PORT": String(port),
            "MACAPPLIBRARY_TOKEN": token
        ]
        server["mcp_config"] = mcpConfig
        manifest["server"] = server
        manifest.removeValue(forKey: "user_config")

        let patched = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try patched.write(to: manifestURL, options: .atomic)

        // Zip the staged directory into a .mcpb. /usr/bin/zip writes a flat
        // archive whose top-level entries match the directory contents (which
        // is exactly what the .mcpb format requires).
        let outputURL = workDirOutput()
        try? fm.removeItem(at: outputURL)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = stageDir
        proc.arguments = ["-r", "-q", outputURL.path, "."]
        let errPipe = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            throw InstallError.zipFailed(error.localizedDescription)
        }
        if proc.terminationStatus != 0 {
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw InstallError.zipFailed("zip exited \(proc.terminationStatus): \(stderr)")
        }

        let opened = NSWorkspace.shared.open(outputURL)
        if !opened {
            throw InstallError.openFailed("NSWorkspace refused to open \(outputURL.lastPathComponent). Is Claude Desktop installed?")
        }
        return outputURL
    }

    /// Stable per-user output path so we don't litter /tmp with .mcpb files
    /// across installs. The temp directory in workDir cleanup deletes the
    /// staging copy; this final artifact lives in the app's caches dir.
    private static func workDirOutput() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("macAppLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("macapplibrary.mcpb")
    }
}
