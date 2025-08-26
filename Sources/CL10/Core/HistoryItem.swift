import Foundation

struct HistoryItem: Codable, Equatable {
    var text: String
    var createdAt: Date
    var lastUsedAt: Date
    var sizeBytes: Int
    var previewFirstLine: String
}
