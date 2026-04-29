import Foundation

struct CommunityService {
    // Update this URL once the repo is public on GitHub
    private static let rawURL = "https://raw.githubusercontent.com/tommertron/macAppLibrary/main/community-data.json"

    func fetchCommunityData() async throws -> CommunityDatabase {
        guard let url = URL(string: Self.rawURL) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CommunityDatabase.self, from: data)
    }
}

// TODO: PR submission flow
// Contributions will be submitted via a Cloudflare Worker that holds a GitHub bot token
// and creates a pull request on behalf of the user — no GitHub auth required from contributors.
// The Worker endpoint will be added here once deployed.
