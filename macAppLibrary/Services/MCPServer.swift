import Foundation
import AppKit

/// MCP (Model Context Protocol) server that translates JSON-RPC tool calls
/// into the same operations exposed by the REST API.
///
/// Transport: streamable HTTP. Single endpoint POST /mcp accepting one JSON-RPC
/// message per request, responding with one JSON-RPC message. No SSE/streaming
/// — the tool surface is request/response only.
///
/// Spec: https://modelcontextprotocol.io/specification/
@MainActor
final class MCPServer {
    private weak var store: AppLibraryStore?
    private let protocolVersion = "2025-03-26"
    private let serverName = "macAppLibrary"
    private let serverVersion = "1.0.0"

    init(store: AppLibraryStore) {
        self.store = store
    }

    /// Process a single JSON-RPC request body. Returns the JSON-encoded response,
    /// or nil for notification messages (which receive HTTP 202 + empty body).
    func handle(_ body: Data) async -> (status: Int, data: Data?) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return (200, errorResponse(id: nil, code: -32700, message: "Parse error"))
        }
        let id = json["id"]
        let method = json["method"] as? String ?? ""
        let params = json["params"] as? [String: Any] ?? [:]

        // Notifications (no id, no response expected)
        if id == nil {
            switch method {
            case "notifications/initialized", "notifications/cancelled":
                return (202, nil)
            default:
                return (202, nil)
            }
        }

        let result: Result<Any, JSONRPCError>
        switch method {
        case "initialize":
            result = .success(initializeResult())
        case "ping":
            result = .success([String: Any]())
        case "tools/list":
            result = .success(["tools": Self.toolDefinitions])
        case "tools/call":
            result = await callTool(params: params)
        default:
            result = .failure(JSONRPCError(code: -32601, message: "Method not found: \(method)"))
        }

        switch result {
        case .success(let value):
            return (200, successResponse(id: id, result: value))
        case .failure(let err):
            return (200, errorResponse(id: id, code: err.code, message: err.message))
        }
    }

    // MARK: Initialize

    private func initializeResult() -> [String: Any] {
        [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": [
                "name": serverName,
                "version": serverVersion
            ]
        ]
    }

    // MARK: Tool dispatch

    private func callTool(params: [String: Any]) async -> Result<Any, JSONRPCError> {
        guard let name = params["name"] as? String else {
            return .failure(JSONRPCError(code: -32602, message: "Missing tool name"))
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        guard let store else {
            return .failure(JSONRPCError(code: -32603, message: "Store unavailable"))
        }

        do {
            let payload: Any
            switch name {
            case "list_apps":
                payload = try toolListApps(args: args, store: store)
            case "get_app":
                payload = try toolGetApp(args: args, store: store)
            case "update_app_metadata":
                payload = try toolUpdateApp(args: args, store: store)
            case "quit_app":
                payload = try toolQuitApp(args: args)
            case "list_categories":
                payload = toolListCategories(store: store)
            case "get_community_data":
                payload = try await toolGetCommunity(args: args)
            case "pull_community_data":
                payload = try toolPullCommunity(args: args, store: store)
            case "submit_to_community":
                payload = try await toolSubmit(args: args, store: store)
            case "generate_ai_description":
                payload = try await toolGenerateAI(args: args, store: store)
            default:
                return .failure(JSONRPCError(code: -32602, message: "Unknown tool: \(name)"))
            }
            return .success(toolContent(payload, isError: false))
        } catch let err as ToolError {
            return .success(toolContent(["error": err.code, "message": err.message], isError: true))
        } catch {
            return .success(toolContent(["error": "internal", "message": error.localizedDescription], isError: true))
        }
    }

    /// Wraps a payload in MCP tools/call result format.
    private func toolContent(_ payload: Any, isError: Bool) -> [String: Any] {
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "{}"
        return [
            "content": [["type": "text", "text": json]],
            "isError": isError
        ]
    }

    // MARK: Tool implementations

    private func toolListApps(args: [String: Any], store: AppLibraryStore) throws -> [[String: Any]] {
        store.refreshRunningApps()
        let category = args["category"] as? String
        let developer = args["developer"] as? String
        let runningOnly = args["running"] as? Bool ?? false
        let running = store.runningBundleIDs
        let filtered = store.apps.filter { app in
            if let category, !app.effectiveCategories.contains(category) { return false }
            if let developer, app.effectiveDeveloper != developer { return false }
            if runningOnly, !running.contains(app.bundleID) { return false }
            return true
        }
        return filtered.map { encodeAppSummary($0, isRunning: running.contains($0.bundleID)) }
    }

    private func toolGetApp(args: [String: Any], store: AppLibraryStore) throws -> [String: Any] {
        let id = try requireBundleID(args)
        store.refreshRunningApps()
        guard let app = store.apps.first(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "No app with bundleID \(id)")
        }
        let isRunning = store.runningBundleIDs.contains(app.bundleID)
        return encodeAppDetail(app, isRunning: isRunning)
    }

    private func toolUpdateApp(args: [String: Any], store: AppLibraryStore) throws -> [String: Any] {
        let id = try requireBundleID(args)
        guard var app = store.apps.first(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "No app with bundleID \(id)")
        }
        if let v = args["description"] as? String { app.userDescription = v.isEmpty ? nil : v }
        if let v = args["developer"] as? String { app.userDeveloper = v.isEmpty ? nil : v }
        if let v = args["categories"] as? [String] { app.userCategories = v }
        if let v = args["notes"] as? String { app.userNotes = v.isEmpty ? nil : v }
        if let v = args["websiteURL"] as? String { app.userWebsiteURL = v.isEmpty ? nil : v }
        if let v = args["isFavorite"] as? Bool { app.isFavorite = v }
        store.updateApp(app)
        return encodeAppDetail(app, isRunning: store.runningBundleIDs.contains(app.bundleID))
    }

    private func toolQuitApp(args: [String: Any]) throws -> [String: Any] {
        let id = try requireBundleID(args)
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == id }
        guard !running.isEmpty else {
            throw ToolError("not_running", "App is not currently running")
        }
        var terminated = false
        for app in running where app.terminate() { terminated = true }
        guard terminated else {
            throw ToolError("terminate_failed", "Could not terminate app")
        }
        return ["terminated": true, "bundleID": id]
    }

    private func toolListCategories(store: AppLibraryStore) -> [[String: Any]] {
        var counts: [String: Int] = [:]
        for app in store.apps {
            for cat in app.effectiveCategories { counts[cat, default: 0] += 1 }
        }
        return counts
            .sorted { $0.key < $1.key }
            .map { ["name": $0.key, "appCount": $0.value] }
    }

    private func toolGetCommunity(args: [String: Any]) async throws -> [String: Any] {
        let id = try requireBundleID(args)
        do {
            let db = try await CommunityService().fetchCommunityData()
            if let entry = db[id] {
                return [
                    "bundleID": id,
                    "exists": true,
                    "description": entry.description as Any,
                    "categories": entry.categories,
                    "developer": entry.developer as Any,
                    "websiteURL": entry.url as Any
                ]
            }
            return ["bundleID": id, "exists": false, "categories": [String]()]
        } catch {
            throw ToolError("upstream_error", "Failed to fetch community data: \(error.localizedDescription)")
        }
    }

    private func toolPullCommunity(args: [String: Any], store: AppLibraryStore) throws -> [String: Any] {
        let id = try requireBundleID(args)
        guard store.apps.contains(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "No app with bundleID \(id)")
        }
        store.pullCommunityFieldsToUser(for: id)
        guard let updated = store.apps.first(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "App vanished after pull")
        }
        return encodeAppDetail(updated, isRunning: store.runningBundleIDs.contains(updated.bundleID))
    }

    private func toolSubmit(args: [String: Any], store: AppLibraryStore) async throws -> [String: Any] {
        let id = try requireBundleID(args)
        guard let app = store.apps.first(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "No app with bundleID \(id)")
        }
        guard let description = app.effectiveDescription, !description.isEmpty else {
            throw ToolError("missing_description", "App must have a description before submitting")
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
            return ["prURL": result.prURL, "prNumber": result.prNumber]
        } catch {
            throw ToolError("upstream_error", "Submit failed: \(error.localizedDescription)")
        }
    }

    private func toolGenerateAI(args: [String: Any], store: AppLibraryStore) async throws -> [String: Any] {
        let id = try requireBundleID(args)
        guard var app = store.apps.first(where: { $0.bundleID == id }) else {
            throw ToolError("not_found", "No app with bundleID \(id)")
        }
        guard let apiKey = KeychainHelper.load(for: "anthropic-api-key"), !apiKey.isEmpty else {
            throw ToolError("no_api_key", "No Anthropic API key configured. Add one in macAppLibrary Settings.")
        }
        do {
            let desc = try await AIService().generateDescription(
                appName: app.name,
                bundleID: app.bundleID,
                apiKey: apiKey
            )
            app.userDescription = desc
            store.updateApp(app)
            return ["description": desc]
        } catch {
            throw ToolError("ai_error", error.localizedDescription)
        }
    }

    // MARK: Helpers

    private func requireBundleID(_ args: [String: Any]) throws -> String {
        guard let id = args["bundleID"] as? String, !id.isEmpty else {
            throw ToolError("invalid_arguments", "Missing required argument: bundleID")
        }
        return id
    }

    private func encodeAppSummary(_ app: AppEntry, isRunning: Bool) -> [String: Any] {
        var dict: [String: Any] = [
            "bundleID": app.bundleID,
            "name": app.name,
            "bundlePath": app.bundlePath,
            "categories": app.effectiveCategories,
            "isFavorite": app.isFavorite,
            "isRunning": isRunning
        ]
        if let v = app.version { dict["version"] = v }
        if let v = app.effectiveDeveloper { dict["developer"] = v }
        if let v = app.effectiveDescription { dict["description"] = v }
        if let v = app.effectiveWebsiteURL { dict["websiteURL"] = v }
        return dict
    }

    private func encodeAppDetail(_ app: AppEntry, isRunning: Bool) -> [String: Any] {
        var dict = encodeAppSummary(app, isRunning: isRunning)
        var community: [String: Any] = ["categories": app.communityCategories]
        if let v = app.communityDescription { community["description"] = v }
        if let v = app.communityDeveloper { community["developer"] = v }
        if let v = app.communityURL { community["websiteURL"] = v }
        var user: [String: Any] = ["categories": app.userCategories]
        if let v = app.userDescription { user["description"] = v }
        if let v = app.userDeveloper { user["developer"] = v }
        if let v = app.userNotes { user["notes"] = v }
        if let v = app.userWebsiteURL { user["websiteURL"] = v }
        dict["community"] = community
        dict["user"] = user
        return dict
    }

    // MARK: JSON-RPC framing

    private func successResponse(id: Any?, result: Any) -> Data {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": idValue(id),
            "result": result
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
    }

    private func errorResponse(id: Any?, code: Int, message: String) -> Data {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": idValue(id),
            "error": ["code": code, "message": message]
        ]
        return (try? JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])) ?? Data()
    }

    private func idValue(_ id: Any?) -> Any {
        // JSON-RPC ids may be string, number, or null
        id ?? NSNull()
    }
}

private struct JSONRPCError: Error {
    let code: Int
    let message: String
}

private struct ToolError: Error {
    let code: String
    let message: String
    init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Tool definitions

extension MCPServer {
    /// JSON-serializable tool definitions returned by tools/list.
    fileprivate static let toolDefinitions: [[String: Any]] = [
        [
            "name": "list_apps",
            "description": "List installed Mac apps. Optionally filter by category, developer, or running state.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "category": ["type": "string", "description": "Return only apps with this category in their effective categories."],
                    "developer": ["type": "string", "description": "Exact match against effective developer."],
                    "running": ["type": "boolean", "description": "If true, return only currently-running apps."]
                ]
            ]
        ],
        [
            "name": "get_app",
            "description": "Get full metadata for one app, including the community/user override breakdown.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string", "description": "macOS bundle identifier, e.g. com.apple.Safari"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "update_app_metadata",
            "description": "Update user-set metadata for an app. Empty strings clear the override; missing fields are left unchanged.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"],
                    "description": ["type": "string"],
                    "developer": ["type": "string"],
                    "categories": ["type": "array", "items": ["type": "string"]],
                    "notes": ["type": "string"],
                    "websiteURL": ["type": "string"],
                    "isFavorite": ["type": "boolean"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "quit_app",
            "description": "Politely terminate a running app. Returns an error if the app isn't running.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "list_categories",
            "description": "List all categories present in the user's library, with counts.",
            "inputSchema": ["type": "object", "properties": [String: Any]()]
        ],
        [
            "name": "get_community_data",
            "description": "Look up the community-database entry for a bundle ID. Returns exists:false if absent.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "pull_community_data",
            "description": "Apply the community description, categories, developer, and website to the user fields for an app. Mirrors the in-app Pull All button.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "submit_to_community",
            "description": "Open a pull request submitting the app's current metadata to the community database. Requires a non-empty description.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"]
                ],
                "required": ["bundleID"]
            ]
        ],
        [
            "name": "generate_ai_description",
            "description": "Use Anthropic to generate a 1-2 sentence description for the app, save it as the user description, and return it. Requires the user to have configured an Anthropic API key in macAppLibrary Settings.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "bundleID": ["type": "string"]
                ],
                "required": ["bundleID"]
            ]
        ]
    ]
}
