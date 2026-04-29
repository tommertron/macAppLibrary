import Foundation

struct CommunityAppData: Codable, Sendable {
    var name: String
    var description: String
    var category: String
    var tags: [String]
}

typealias CommunityDatabase = [String: CommunityAppData]
