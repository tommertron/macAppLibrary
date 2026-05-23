import Foundation

/// Publishes a library to coefficiencies.com via the publish worker.
///
/// The worker accepts **structured data only** — never the rendered HTML, never
/// images or icon URLs. It derives every icon server-side from the bundle ID and
/// commits a Hugo content file; the page builds and deploys from there.
/// See `publish-worker/` and `scripts/publishing-workflow-spec.md`.
enum PublishService {

    /// The deployed Cloudflare worker. (workers.dev for now; swap for a custom
    /// route if one is added later.)
    static let endpoint = URL(string: "https://macapplibrary-publish.tommertron.workers.dev/publish")!

    // MARK: - Wire types

    private struct Payload: Encodable {
        let displayName: String
        let websiteURL: String?
        let apps: [App]

        struct App: Encodable {
            let bundleID: String
            let name: String
            let url: String?
            let categories: [String]
            let sizeBytes: Int64?
            let favorite: Bool
        }
    }

    private struct SuccessResponse: Decodable {
        let url: String
        let slug: String
    }

    private struct ErrorResponse: Decodable {
        let error: String
        let details: [String]?
    }

    // MARK: - API

    enum PublishError: LocalizedError {
        case validation([String])
        case rateLimited
        case server(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .validation(let issues):
                return issues.isEmpty ? "The library failed validation."
                                      : "Couldn’t publish:\n• " + issues.joined(separator: "\n• ")
            case .rateLimited:
                return "You’ve hit today’s publish limit. Try again tomorrow."
            case .server(let message):
                return "The publish service returned an error: \(message)"
            case .badResponse:
                return "Got an unexpected response from the publish service."
            }
        }
    }

    /// Publishes the included apps and returns the public URL of the new page.
    /// The page is committed immediately but may take a minute to build+deploy.
    static func publish(apps: [AppEntry], config: InfographicConfig) async throws -> URL {
        let included = apps.filter { config.isIncluded($0.bundleID) }

        let payloadApps = included.map { app in
            Payload.App(
                bundleID: app.bundleID,
                name: app.name,
                url: trimmedOrNil(app.effectiveWebsiteURL),
                categories: app.effectiveCategories,
                sizeBytes: app.sizeBytes,
                favorite: app.isFavorite
            )
        }

        let payload = Payload(
            displayName: config.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            websiteURL: trimmedOrNil(config.websiteURL),
            apps: payloadApps
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PublishError.badResponse }

        switch http.statusCode {
        case 200:
            guard let ok = try? JSONDecoder().decode(SuccessResponse.self, from: data),
                  let url = URL(string: ok.url) else {
                throw PublishError.badResponse
            }
            return url
        case 429:
            throw PublishError.rateLimited
        case 400, 403:
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw PublishError.validation(err.details ?? [err.error])
            }
            throw PublishError.server("HTTP \(http.statusCode)")
        default:
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
                ?? "HTTP \(http.statusCode)"
            throw PublishError.server(message)
        }
    }

    /// Polls `url` until it returns HTTP 200 (the build + deploy has finished),
    /// or `timeout` elapses. The page genuinely doesn't exist during the build
    /// window, so we cache-bust every probe to avoid re-seeing a stale 404 from
    /// the browser/URL cache. Returns `true` if it went live, `false` on timeout
    /// or cancellation.
    static func waitUntilLive(_ url: URL, timeout: TimeInterval = 180, interval: TimeInterval = 4) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if Task.isCancelled { return false }
            if await isLive(url) { return true }
            try? await Task.sleep(for: .seconds(interval))
        }
        return false
    }

    private static func isLive(_ url: URL) async -> Bool {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        comps.queryItems = (comps.queryItems ?? [])
            + [URLQueryItem(name: "_cb", value: String(Int(Date().timeIntervalSince1970)))]
        guard let busted = comps.url else { return false }

        var request = URLRequest(url: busted)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    private static func trimmedOrNil(_ s: String?) -> String? {
        guard let trimmed = s?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
