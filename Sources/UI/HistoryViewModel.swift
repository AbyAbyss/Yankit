import AppKit
import SwiftUI

/// Which slice of the history the panel shows — one per chip.
enum HistoryFilter: Hashable {
    case recent
    case pinned
    case category(String)  // category id

    /// A string form for persisting the last selected chip.
    var storageValue: String {
        switch self {
        case .recent: "recent"
        case .pinned: "pinned"
        case .category(let id): "category:\(id)"
        }
    }

    init(storageValue: String) {
        if storageValue == "pinned" {
            self = .pinned
        } else if storageValue.hasPrefix("category:") {
            self = .category(String(storageValue.dropFirst("category:".count)))
        } else {
            self = .recent
        }
    }
}

/// Backs the history panel: loads items and categories from the repository,
/// filters them by the selected chip and the search text, tracks the
/// keyboard selection, and applies pin, label, and category changes.
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var categories: [ClipboardCategory] = []
    @Published var filter: HistoryFilter = .recent {
        didSet {
            selectedIndex = 0
            preferences.lastHistoryFilter = filter.storageValue
        }
    }
    @Published var searchText: String = "" {
        didSet { selectedIndex = 0 }
    }
    @Published var selectedIndex: Int = 0

    // Inline editing. At most one of these is active at a time; while one
    // is, the panel's key monitor leaves keys to the text field.
    @Published var editingLabelItemID: String?
    @Published var isAddingCategory = false
    @Published var renamingCategoryID: String?

    var isEditing: Bool {
        editingLabelItemID != nil || isAddingCategory || renamingCategoryID != nil
    }

    /// The selected row's frame in window coordinates, so ⌘M can open the
    /// move menu beside it.
    var selectedRowFrame: CGRect?

    /// Preloaded list thumbnails, keyed by item id. Only image items appear.
    private(set) var thumbnails: [String: NSImage] = [:]
    private var sensitiveCategoryIDs: Set<String> = []

    private let repository: ClipboardRepository
    private let blobStore: BlobStore
    private let preferences: Preferences

    init(
        repository: ClipboardRepository,
        blobStore: BlobStore,
        preferences: Preferences
    ) {
        self.repository = repository
        self.blobStore = blobStore
        self.preferences = preferences
        if preferences.rememberHistoryFilter {
            filter = HistoryFilter(storageValue: preferences.lastHistoryFilter)
        }
    }

    /// Items in the selected chip that match the current search text. An
    /// empty query shows all. Matches across label, text content, file name,
    /// and source app name (§8.2) — but never the hidden content of an item
    /// in a sensitive category.
    var filteredItems: [ClipboardItem] {
        let inFilter: [ClipboardItem]
        switch filter {
        case .recent:
            inFilter = items
        case .pinned:
            inFilter = items.filter(\.pinned)
        case .category(let id):
            inFilter = items.filter { $0.categoryID == id }
        }
        guard !searchText.isEmpty else { return inFilter }
        let query = searchText.lowercased()
        return inFilter.filter { item in
            let contentMatches = !isSensitive(item) && (
                item.textContent?.lowercased().contains(query) == true
                    || item.fileName?.lowercased().contains(query) == true
            )
            return contentMatches
                || item.label?.lowercased().contains(query) == true
                || item.sourceAppName?.lowercased().contains(query) == true
        }
    }

    /// True when the item is in a sensitive category, so its content must
    /// be redacted in the UI.
    func isSensitive(_ item: ClipboardItem) -> Bool {
        item.categoryID.map(sensitiveCategoryIDs.contains) ?? false
    }

    var selectedItem: ClipboardItem? {
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex) else { return nil }
        return visible[selectedIndex]
    }

    func reload() {
        do {
            let loaded = try repository.allItems()
            thumbnails = Self.buildThumbnails(for: loaded, blobStore: blobStore)
            items = loaded
            categories = try repository.allCategories()
        } catch {
            NSLog("Yankit: failed to load history: \(error)")
            thumbnails = [:]
            items = []
            categories = []
        }
        sensitiveCategoryIDs = Set(categories.filter(\.isSensitive).map(\.id))
        // A remembered or open category chip may have been deleted.
        if case .category(let id) = filter,
           !categories.contains(where: { $0.id == id }) {
            filter = .recent
        }
        selectedIndex = 0
    }

    func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = min(max(0, selectedIndex + delta), count - 1)
    }

    func togglePin(_ item: ClipboardItem) {
        do {
            try repository.setPinned(!item.pinned, id: item.id)
            reload()
        } catch {
            NSLog("Yankit: failed to toggle pin: \(error)")
        }
    }

    /// Removes one item from history, keeping the selection near where it was.
    func delete(_ item: ClipboardItem) {
        do {
            try repository.delete(id: item.id)
        } catch {
            NSLog("Yankit: failed to delete item: \(error)")
            return
        }
        let previousIndex = selectedIndex
        reload()
        let count = filteredItems.count
        if count > 0 {
            selectedIndex = min(previousIndex, count - 1)
        }
    }

    // MARK: - Labels & categories

    /// Saves the label being edited inline. Blank text removes the label.
    func commitLabel(_ text: String, for item: ClipboardItem) {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        editingLabelItemID = nil
        perform("set label") {
            try repository.setLabel(label.isEmpty ? nil : label, id: item.id)
        }
    }

    func setCategory(_ categoryID: String?, for item: ClipboardItem) {
        perform("move item") {
            try repository.setCategory(categoryID, id: item.id)
        }
    }

    /// Handles a row dropped on a chip: a category chip moves the item
    /// there, Recent takes it out of its category. Returns whether the drop
    /// was accepted.
    func moveDroppedItem(id: String, to filter: HistoryFilter) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        switch filter {
        case .recent:
            setCategory(nil, for: item)
        case .category(let categoryID):
            setCategory(categoryID, for: item)
        case .pinned:
            return false
        }
        return true
    }

    /// Creates a category from the chip bar's inline field. Blank text
    /// cancels.
    func commitNewCategory(named text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isAddingCategory = false
        guard !name.isEmpty else { return }
        perform("create category") {
            try repository.saveCategory(ClipboardCategory(name: name))
        }
    }

    /// Renames a category from its chip's inline field. Blank text cancels.
    func commitRename(_ category: ClipboardCategory, to text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        renamingCategoryID = nil
        guard !name.isEmpty else { return }
        var renamed = category
        renamed.name = name
        perform("rename category") { try repository.saveCategory(renamed) }
    }

    func toggleSensitive(_ category: ClipboardCategory) {
        var updated = category
        updated.isSensitive.toggle()
        perform("update category") { try repository.saveCategory(updated) }
    }

    /// Deletes a category; its items return to the normal history.
    func deleteCategory(_ category: ClipboardCategory) {
        perform("delete category") {
            try repository.deleteCategory(id: category.id)
        }
    }

    func cancelEditing() {
        editingLabelItemID = nil
        isAddingCategory = false
        renamingCategoryID = nil
    }

    /// Runs a repository change, then reloads. Failures are logged.
    private func perform(_ description: String, _ change: () throws -> Void) {
        do {
            try change()
        } catch {
            NSLog("Yankit: failed to \(description): \(error)")
            return
        }
        reload()
    }

    private static func buildThumbnails(
        for items: [ClipboardItem],
        blobStore: BlobStore
    ) -> [String: NSImage] {
        var result: [String: NSImage] = [:]
        for item in items where item.kind == .image {
            guard let path = item.thumbnailPath ?? item.blobPath else { continue }
            let url = blobStore.absoluteURL(forRelativePath: path)
            if let image = NSImage(contentsOf: url) {
                result[item.id] = image
            }
        }
        return result
    }
}
