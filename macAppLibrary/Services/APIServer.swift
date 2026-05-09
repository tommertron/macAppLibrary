import Foundation
import Network
import AppKit

// MARK: - Request / Response

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? encoder.encode(value)) ?? Data()
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    static func error(_ code: String, message: String, status: Int) -> HTTPResponse {
        json(ErrorResponse(error: code, message: message), status: status)
    }

    static func empty(status: Int) -> HTTPResponse {
        HTTPResponse(status: status, headers: [:], body: Data())
    }
}

// MARK: - Server

@MainActor
final class APIServer {
    private weak var store: AppLibraryStore?
    private var listener: NWListener?
    private var token: String = ""
    private(set) var port: UInt16 = 0
    private var connections: Set<ObjectIdentifier> = []
    private var connectionHandles: [ObjectIdentifier: NWConnection] = [:]
    private var mcp: MCPServer?

    static let mcpEnabledKey = "mcpServerEnabled"
    private static let tokenKey = "macAppLibrary.api.token"
    private static let appVersion = "1.0.0"

    init(store: AppLibraryStore) {
        self.store = store
        self.mcp = MCPServer(store: store)
    }

    func start() {
        guard listener == nil else { return }
        token = Self.loadOrCreateToken()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback
            let l = try NWListener(using: params)
            listener = l
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                Task { @MainActor in self.handleListenerState(state) }
            }
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                Task { @MainActor in self.accept(conn) }
            }
            l.start(queue: .global(qos: .userInitiated))
        } catch {
            NSLog("APIServer failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connectionHandles.values { conn.cancel() }
        connectionHandles.removeAll()
        connections.removeAll()
        DiscoveryFile.remove()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let p = listener?.port?.rawValue {
                port = p
                DiscoveryFile.write(port: p, token: token)
                NSLog("APIServer listening on 127.0.0.1:\(p)")
            }
        case .failed(let err):
            NSLog("APIServer listener failed: \(err)")
            stop()
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections.insert(id)
        connectionHandles[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            if case .failed = state {
                Task { @MainActor in self.cleanup(id) }
            } else if case .cancelled = state {
                Task { @MainActor in self.cleanup(id) }
            }
        }
        conn.start(queue: .global(qos: .userInitiated))
        readRequest(on: conn, accumulated: Data())
    }

    private func cleanup(_ id: ObjectIdentifier) {
        connections.remove(id)
        connectionHandles.removeValue(forKey: id)
    }

    // MARK: HTTP framing

    private func readRequest(on conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("APIServer recv error: \(error)")
                conn.cancel()
                return
            }
            var buf = accumulated
            if let data { buf.append(data) }

            if let req = HTTPParser.tryParse(&buf) {
                Task { @MainActor in
                    let resp = await self.route(req)
                    self.send(resp, on: conn, closeAfter: true)
                }
                return
            }

            if isComplete {
                conn.cancel()
                return
            }
            self.readRequest(on: conn, accumulated: buf)
        }
    }

    private func send(_ resp: HTTPResponse, on conn: NWConnection, closeAfter: Bool) {
        var headers = resp.headers
        headers["Content-Length"] = String(resp.body.count)
        headers["Connection"] = closeAfter ? "close" : "keep-alive"
        var head = "HTTP/1.1 \(resp.status) \(Self.reason(resp.status))\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(resp.body)
        conn.send(content: out, completion: .contentProcessed { _ in
            if closeAfter { conn.cancel() }
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }

    // MARK: Routing

    private func route(_ req: HTTPRequest) async -> HTTPResponse {
        // Health and version are unauthenticated so clients can probe.
        switch (req.method, req.path) {
        case ("GET", "/v1/health"):
            return .json(HealthResponse(status: "ok", appVersion: Self.appVersion, apiVersion: APIDTO.apiVersion))
        case ("GET", "/v1/version"):
            return .json(VersionResponse(
                appVersion: Self.appVersion,
                apiVersion: APIDTO.apiVersion,
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ))
        default:
            break
        }

        guard authorize(req) else {
            return .error("unauthorized", message: "Missing or invalid Authorization header", status: 401)
        }

        guard let store else {
            return .error("unavailable", message: "Store not initialized", status: 500)
        }

        // MCP — gated on the Settings toggle
        if req.path == "/mcp" {
            guard UserDefaults.standard.bool(forKey: Self.mcpEnabledKey) else {
                return .error("mcp_disabled", message: "MCP server is disabled in Settings", status: 404)
            }
            switch req.method {
            case "POST":
                guard let mcp else {
                    return .error("unavailable", message: "MCP not initialized", status: 500)
                }
                let (status, data) = await mcp.handle(req.body)
                if let data {
                    return HTTPResponse(
                        status: status,
                        headers: ["Content-Type": "application/json; charset=utf-8"],
                        body: data
                    )
                }
                return .empty(status: status)
            case "GET":
                // SSE / server-initiated streaming not supported in this version.
                return .error("not_supported", message: "GET /mcp (SSE) not supported. Use POST.", status: 405)
            default:
                return .error("method_not_allowed", message: "Use POST /mcp", status: 405)
            }
        }

        // Refresh running apps cheaply on read
        store.refreshRunningApps()

        switch (req.method, req.path) {
        case ("GET", "/v1/apps"):
            return handleListApps(req, store: store)

        case ("GET", "/v1/categories"):
            var counts: [String: Int] = [:]
            for app in store.apps {
                for cat in app.effectiveCategories { counts[cat, default: 0] += 1 }
            }
            let dtos = counts
                .map { CategoryDTO(name: $0.key, appCount: $0.value) }
                .sorted { $0.name < $1.name }
            return .json(dtos)

        default:
            break
        }

        // /v1/community/{bundleID}
        if req.method == "GET", let id = pathParam(req.path, prefix: "/v1/community/") {
            return await handleGetCommunity(bundleID: id)
        }

        // Routes under /v1/apps/{bundleID}[/...]
        if let (id, suffix) = parseAppPath(req.path) {
            guard let app = store.apps.first(where: { $0.bundleID == id }) else {
                return .error("not_found", message: "No app with bundleID \(id)", status: 404)
            }
            switch (req.method, suffix) {
            case ("GET", ""):
                let running = store.runningBundleIDs.contains(app.bundleID)
                return .json(AppDTO(app, isRunning: running, includeOverrides: true))
            case ("PATCH", ""):
                return handlePatchApp(req, app: app, store: store)
            case ("POST", "/quit"):
                return handleQuit(bundleID: app.bundleID)
            case ("POST", "/community/pull"):
                store.pullCommunityFieldsToUser(for: app.bundleID)
                let updated = store.apps.first { $0.bundleID == app.bundleID } ?? app
                let running = store.runningBundleIDs.contains(updated.bundleID)
                return .json(AppDTO(updated, isRunning: running, includeOverrides: true))
            case ("POST", "/community/submit"):
                return await handleSubmit(app: app)
            case ("POST", "/ai-describe"):
                return await handleAIDescribe(app: app, store: store)
            default:
                return .error("not_found", message: "Unknown route \(req.method) \(req.path)", status: 404)
            }
        }

        return .error("not_found", message: "Unknown route \(req.method) \(req.path)", status: 404)
    }

    // MARK: Handlers

    private func handleListApps(_ req: HTTPRequest, store: AppLibraryStore) -> HTTPResponse {
        let running = store.runningBundleIDs
        let category = req.query["category"]
        let developer = req.query["developer"]
        let runningOnly = req.query["running"] == "true"
        let filtered = store.apps.filter { app in
            if let category, !app.effectiveCategories.contains(category) { return false }
            if let developer, app.effectiveDeveloper != developer { return false }
            if runningOnly, !running.contains(app.bundleID) { return false }
            return true
        }
        let dtos = filtered.map { AppDTO($0, isRunning: running.contains($0.bundleID), includeOverrides: false) }
        return .json(dtos)
    }

    private func handlePatchApp(_ req: HTTPRequest, app: AppEntry, store: AppLibraryStore) -> HTTPResponse {
        let update: AppUpdateRequest
        do {
            update = try JSONDecoder().decode(AppUpdateRequest.self, from: req.body)
        } catch {
            return .error("bad_request", message: "Invalid JSON body: \(error.localizedDescription)", status: 400)
        }
        var modified = app
        if let v = update.description { modified.userDescription = v.isEmpty ? nil : v }
        if let v = update.developer { modified.userDeveloper = v.isEmpty ? nil : v }
        if let v = update.categories { modified.userCategories = v }
        if let v = update.notes { modified.userNotes = v.isEmpty ? nil : v }
        if let v = update.websiteURL { modified.userWebsiteURL = v.isEmpty ? nil : v }
        if let v = update.isFavorite { modified.isFavorite = v }
        store.updateApp(modified)
        let running = store.runningBundleIDs.contains(modified.bundleID)
        return .json(AppDTO(modified, isRunning: running, includeOverrides: true))
    }

    private func handleQuit(bundleID: String) -> HTTPResponse {
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleID }
        guard !running.isEmpty else {
            return .error("not_running", message: "App is not currently running", status: 404)
        }
        var anyTerminated = false
        for app in running {
            if app.terminate() { anyTerminated = true }
        }
        return anyTerminated
            ? .empty(status: 204)
            : .error("terminate_failed", message: "Could not terminate app", status: 500)
    }

    private func handleGetCommunity(bundleID: String) async -> HTTPResponse {
        do {
            let db = try await CommunityService().fetchCommunityData()
            if let entry = db[bundleID] {
                return .json(CommunityDataDTO(
                    bundleID: bundleID,
                    description: entry.description,
                    categories: entry.categories,
                    developer: entry.developer,
                    websiteURL: entry.url,
                    exists: true
                ))
            }
            return .json(CommunityDataDTO(
                bundleID: bundleID,
                description: nil,
                categories: [],
                developer: nil,
                websiteURL: nil,
                exists: false
            ))
        } catch {
            return .error("upstream_error", message: "Failed to fetch community data: \(error.localizedDescription)", status: 502)
        }
    }

    private func handleSubmit(app: AppEntry) async -> HTTPResponse {
        guard let description = app.effectiveDescription, !description.isEmpty else {
            return .error("missing_description", message: "App must have a description before submitting", status: 400)
        }
        let submission = CommunitySubmission(
            bundleID: app.bundleID,
            name: app.name,
            description: description,
            categories: app.effectiveCategories,
            developer: app.effectiveDeveloper,
            url: app.effectiveWebsiteURL
        )
        do {
            let result = try await CommunityService().submitEntry(submission)
            return .json(SubmitResponseDTO(prURL: result.prURL, prNumber: result.prNumber))
        } catch {
            return .error("upstream_error", message: "Submit failed: \(error.localizedDescription)", status: 502)
        }
    }

    private func handleAIDescribe(app: AppEntry, store: AppLibraryStore) async -> HTTPResponse {
        guard let apiKey = KeychainHelper.load(for: "anthropic-api-key"), !apiKey.isEmpty else {
            return .error("no_api_key", message: "No Anthropic API key configured. Add one in app Settings.", status: 412)
        }
        do {
            let desc = try await AIService().generateDescription(
                appName: app.name,
                bundleID: app.bundleID,
                apiKey: apiKey
            )
            var modified = app
            modified.userDescription = desc
            store.updateApp(modified)
            return .json(AIDescribeResponseDTO(description: desc))
        } catch {
            return .error("ai_error", message: error.localizedDescription, status: 502)
        }
    }

    // MARK: Path helpers

    private func pathParam(_ path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let id = String(path.dropFirst(prefix.count))
        guard !id.isEmpty, !id.contains("/") else { return nil }
        return id
    }

    /// Parses /v1/apps/{bundleID} and /v1/apps/{bundleID}/{action}.
    /// Returns (bundleID, suffix) where suffix is "" for the bare resource or "/action[/sub]".
    private func parseAppPath(_ path: String) -> (String, String)? {
        let prefix = "/v1/apps/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = String(path.dropFirst(prefix.count))
        guard !rest.isEmpty else { return nil }
        if let slash = rest.firstIndex(of: "/") {
            let id = String(rest[..<slash])
            let suffix = String(rest[slash...])
            guard !id.isEmpty else { return nil }
            return (id, suffix)
        }
        return (rest, "")
    }

    private func authorize(_ req: HTTPRequest) -> Bool {
        guard let header = req.headers["authorization"] ?? req.headers["Authorization"] else { return false }
        let prefix = "Bearer "
        guard header.hasPrefix(prefix) else { return false }
        let provided = String(header.dropFirst(prefix.count))
        return constantTimeEqual(provided, token)
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        if ab.count != bb.count { return false }
        var diff: UInt8 = 0
        for i in 0..<ab.count { diff |= ab[i] ^ bb[i] }
        return diff == 0
    }

    private static func loadOrCreateToken() -> String {
        if let existing = KeychainHelper.load(for: tokenKey), !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token: String
        if status == errSecSuccess {
            token = bytes.map { String(format: "%02x", $0) }.joined()
        } else {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        KeychainHelper.save(token, for: tokenKey)
        return token
    }
}

// MARK: - HTTP parsing

private enum HTTPParser {
    /// Returns a request once headers + Content-Length body are present in `buf`.
    /// Consumes the parsed bytes from `buf` on success.
    static func tryParse(_ buf: inout Data) -> HTTPRequest? {
        guard let headerEnd = rangeOf(buf, pattern: Data([0x0d, 0x0a, 0x0d, 0x0a])) else { return nil }
        let headerData = buf.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            buf.removeAll()
            return nil
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let startLine = lines.first else { return nil }
        lines.removeFirst()
        let parts = startLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let target = parts[1]

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { headers[name] = value }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let totalNeeded = bodyStart + contentLength
        guard buf.count >= totalNeeded else { return nil }

        let body = buf.subdata(in: bodyStart..<totalNeeded)
        buf.removeSubrange(0..<totalNeeded)

        let (path, query) = splitTarget(target)
        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }

    private static func rangeOf(_ data: Data, pattern: Data) -> Range<Data.Index>? {
        data.range(of: pattern)
    }

    private static func splitTarget(_ target: String) -> (String, [String: String]) {
        guard let q = target.firstIndex(of: "?") else { return (target, [:]) }
        let path = String(target[..<q])
        let raw = String(target[target.index(after: q)...])
        var query: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            let key = kv[0].removingPercentEncoding ?? kv[0]
            let value = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
            query[key] = value
        }
        return (path, query)
    }
}

// MARK: - Discovery file

private enum DiscoveryFile {
    static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("macAppLibrary")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("api.json")
    }

    struct Payload: Codable {
        let host: String
        let port: UInt16
        let token: String
        let pid: Int32
        let apiVersion: String
    }

    static func write(port: UInt16, token: String) {
        let payload = Payload(
            host: "127.0.0.1",
            port: port,
            token: token,
            pid: ProcessInfo.processInfo.processIdentifier,
            apiVersion: APIDTO.apiVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
        // Restrict to user only.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
