import Foundation
import GRDB

/// A user-created group of clipboard items, shown as a chip in the history
/// panel. Items in a category are kept until the user removes them, like
/// pinned items. Items in a sensitive category show only their first
/// `visibleCharacters` characters in the UI. See ARCHITECTURE.md §4.2.
struct ClipboardCategory: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var isSensitive: Bool = false
    var createdAt: Date = Date()
    var color: String = "#7AB0FF"     // `#RRGGBB`, one of Theme.categoryColors
    var visibleCharacters: Int = 4
    var sortOrder: Int = 0            // chip order, ascending

    /// Maps Swift's camelCase properties to the snake_case database columns.
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isSensitive = "is_sensitive"
        case createdAt = "created_at"
        case color
        case visibleCharacters = "visible_characters"
        case sortOrder = "sort_order"
    }
}

extension ClipboardCategory: FetchableRecord, PersistableRecord {
    static let databaseTableName = "category"
}
