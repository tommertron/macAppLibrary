import Foundation

struct CommunityService {
    private static let rawURL = "https://raw.githubusercontent.com/tommertron/macAppLibrary/main/community-data.json"
    private static let workerURL = "https://macapplibrary-submissions.tommertron.workers.dev"

    func fetchCommunityData() async throws -> CommunityDatabase {
        guard let url = URL(string: Self.rawURL) else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(CommunityDatabase.self, from: data)
    }

    func submitEntry(_ entry: CommunitySubmission) async throws -> SubmissionResult {
        guard let url = URL(string: Self.workerURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(entry)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(SubmissionResult.self, from: data)
    }
}

struct CommunitySubmission: Encodable {
    let bundleID: String
    let name: String
    let description: String
    let categories: [String]
    let developer: String?
    let url: String?
}

struct SubmissionResult: Decodable {
    let prURL: String
    let prNumber: Int
}
