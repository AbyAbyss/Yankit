import Foundation
import GRDB

/// A user-created group of clipboard items, shown as a chip in the history
/// panel. Items in a category are kept until the user removes them, like
/// pinned items. Items in a sensitive category have their content redacted
/// in the UI. See ARCHITECTURE.md §4.2.
struct ClipboardCategory: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var isSensitive: Bool = false
    var createdAt: Date = Date()

    /// Maps Swift's camelCase properties to the snake_case database columns.
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isSensitive = "is_sensitive"
        case createdAt = "created_at"
    }
}

extension ClipboardCategory: FetchableRecord, PersistableRecord {
    static let databaseTableName = "category"
}
