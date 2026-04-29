import Foundation

struct AppMetadata: Sendable {
    var sizeBytes: Int64?
    var lastLaunched: Date?
    var lastModified: Date?
    var dateAdded: Date?
}

struct MetadataService {
    func load(bundlePath: String) async -> AppMetadata {
        await Task.detached(priority: .background) {
            return AppMetadata(
                sizeBytes: Self.duSize(path: bundlePath),
                lastLaunched: Self.mdlsDate(path: bundlePath, attribute: "kMDItemLastUsedDate"),
                lastModified: Self.mdlsDate(path: bundlePath, attribute: "kMDItemContentModificationDate"),
                dateAdded: Self.mdlsDate(path: bundlePath, attribute: "kMDItemFSCreationDate")
            )
        }.value
    }

    private static func runProcess(executable: String, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func duSize(path: String) -> Int64? {
        guard let output = runProcess(executable: "/usr/bin/du", args: ["-sk", path]),
              let kbStr = output.components(separatedBy: "\t").first,
              let kb = Int64(kbStr.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return kb * 1024
    }

    private static func mdlsDate(path: String, attribute: String) -> Date? {
        guard let output = runProcess(
            executable: "/usr/bin/mdls",
            args: ["-name", attribute, "-raw", path]
        ) else { return nil }
        let raw = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw != "(null)", !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: raw)
    }
}
