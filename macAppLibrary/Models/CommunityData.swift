import Foundation

struct CommunityAppData: Codable, Sendable {
    var name: String
    var description: String
    var categories: [String]
    var developer: String?
    var url: String?
}

typealias CommunityDatabase = [String: CommunityAppData]
