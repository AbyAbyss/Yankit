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

/// A card drawn over the panel. Cards live inside the panel because a
/// separate window would take key focus and dismiss it.
enum PanelOverlay: Equatable {
    /// Edits the label of the item with this id.
    case label(itemID: String)
    /// Creates a category (`nil`) or edits one. When creating, the item
    /// with `moveItemID` is moved into the new category.
    case categoryEditor(ClipboardCategory?, moveItemID: String?)
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
        // The search field also writes back unchanged text (e.g. on focus),
        // which must not reset the selection.
        didSet { if searchText != oldValue { selectedIndex = 0 } }
    }
    @Published var selectedIndex: Int = 0 {
        didSet { isPeekToggled = false }
    }
    @Published var overlay: PanelOverlay?
    /// Sensitive content is revealed in the preview while either is set.
    @Published var isPeekToggled = false
    @Published var isOptionHeld = false
    /// Bumped to ask the view to focus the search field (⌘K).
    @Published private(set) var searchFocusRequest = 0
    /// Bumped when the keyboard moves the selection, so the list scrolls
    /// to keep it visible. Clicks don't bump it: scrolling would move the
    /// row out from under the pointer and break double-click.
    @Published private(set) var keyboardScrollRequest = 0

    /// While an overlay is open, the panel's key monitor leaves keys to it.
    var isEditing: Bool { overlay != nil }
    var isRevealing: Bool { isPeekToggled || isOptionHeld }

    /// The selected row's frame in window coordinates, so ⌘M can open the
    /// move menu beside it.
    var selectedRowFrame: CGRect?

    /// Preloaded list thumbnails, keyed by item id. Only image items appear.
    private(set) var thumbnails: [String: NSImage] = [:]
    private var categoriesByID: [String: ClipboardCategory] = [:]

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

    // MARK: - Visible items

    /// Items in the selected chip that match the current search text. An
    /// empty query shows all. Matches across label, text content, file name,
    /// source app, and category name (§8.2) — but never the hidden content
    /// of an item in a sensitive category.
    var filteredItems: [ClipboardItem] {
        let inFilter: [ClipboardItem]
        switch filter {
        case .recent:
            inFilter = preferences.showPinnedInRecent
                ? items : items.filter { !$0.pinned }
        case .pinned:
            inFilter = items.filter(\.pinned)
        case .category(let id):
            inFilter = items.filter { $0.categoryID == id }
        }
        guard !searchText.isEmpty else { return inFilter }
        let query = searchText.lowercased()
        return inFilter.filter { item in
            let category = category(of: item)
            let contentMatches = category?.isSensitive != true && (
                item.textContent?.lowercased().contains(query) == true
                    || item.fileName?.lowercased().contains(query) == true
            )
            return contentMatches
                || item.label?.lowercased().contains(query) == true
                || item.sourceAppName?.lowercased().contains(query) == true
                || category?.name.lowercased().contains(query) == true
        }
    }

    var selectedItem: ClipboardItem? {
        let visible = filteredItems
        guard visible.indices.contains(selectedIndex) else { return nil }
        return visible[selectedIndex]
    }

    func category(of item: ClipboardItem) -> ClipboardCategory? {
        item.categoryID.flatMap { categoriesByID[$0] }
    }

    func presentation(of item: ClipboardItem) -> ItemPresentation {
        ItemPresentation(item: item, category: category(of: item))
    }

    var pinnedCount: Int { items.filter(\.pinned).count }

    func itemCount(in category: ClipboardCategory) -> Int {
        items.filter { $0.categoryID == category.id }.count
    }

    /// Up to four labels already in use, newest first, for the label card.
    func labelSuggestions(excluding current: String?) -> [String] {
        var seen = Set<String>()
        return items.compactMap(\.label)
            .filter { $0 != current && seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }

    // MARK: - Loading

    /// Reloads from the repository, keeping the same item selected when it
    /// is still visible.
    func reload() {
        let selectedID = selectedItem?.id
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
        categoriesByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        // A remembered or open category chip may have been deleted.
        if case .category(let id) = filter, categoriesByID[id] == nil {
            filter = .recent
        }
        selectedIndex = filteredItems.firstIndex { $0.id == selectedID } ?? 0
    }

    /// The full-size image for the preview pane, read from disk on demand.
    func fullImage(for item: ClipboardItem) -> NSImage? {
        guard let path = item.blobPath else { return nil }
        return NSImage(contentsOf: blobStore.absoluteURL(forRelativePath: path))
    }

    // MARK: - Navigation

    func moveSelection(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = min(max(0, selectedIndex + delta), count - 1)
        keyboardScrollRequest += 1
    }

    /// The chips in Tab order.
    var filters: [HistoryFilter] {
        [.recent, .pinned] + categories.map { .category($0.id) }
    }

    /// Selects the next (or previous, for a negative `delta`) chip,
    /// wrapping around.
    func cycleFilter(by delta: Int) {
        let all = filters
        let current = all.firstIndex(of: filter) ?? 0
        filter = all[(current + delta + all.count) % all.count]
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    // MARK: - Item changes

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

    /// Saves the label typed in the label card. Blank text removes the label.
    func commitLabel(_ text: String, forItemID id: String) {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        overlay = nil
        perform("set label") {
            try repository.setLabel(label.isEmpty ? nil : label, id: id)
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

    // MARK: - Categories

    /// Saves the category from the editor card: inserts it when new (and
    /// moves the pending item into it), updates it otherwise.
    func saveCategory(_ category: ClipboardCategory, isNew: Bool, moveItemID: String?) {
        overlay = nil
        perform("save category") {
            if isNew {
                try repository.addCategory(category)
                if let moveItemID {
                    try repository.setCategory(category.id, id: moveItemID)
                }
            } else {
                try repository.saveCategory(category)
            }
        }
    }

    /// Deletes a category; its items return to the normal history.
    func deleteCategory(_ category: ClipboardCategory) {
        perform("delete category") {
            try repository.deleteCategory(id: category.id)
        }
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
