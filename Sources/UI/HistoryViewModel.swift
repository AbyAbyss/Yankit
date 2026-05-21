import AppKit
import SwiftUI

/// Backs the history panel: loads items from the repository, filters them by
/// the search text, tracks the keyboard selection, and toggles pins.
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var searchText: String = "" {
        didSet { selectedIndex = 0 }
    }
    @Published var selectedIndex: Int = 0

    /// Preloaded list thumbnails, keyed by item id. Only image items appear.
    private(set) var thumbnails: [String: NSImage] = [:]

    private let repository: ClipboardRepository
    private let blobStore: BlobStore

    init(repository: ClipboardRepository, blobStore: BlobStore) {
        self.repository = repository
        self.blobStore = blobStore
    }

    /// Items matching the current search text. An empty query shows all.
    /// Matches across text content, file name, and source app name (§8.2).
    var filteredItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return items }
        let query = searchText.lowercased()
        return items.filter { item in
            item.textContent?.lowercased().contains(query) == true
                || item.fileName?.lowercased().contains(query) == true
                || item.sourceAppName?.lowercased().contains(query) == true
        }
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
        } catch {
            NSLog("ipaste: failed to load history: \(error)")
            thumbnails = [:]
            items = []
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
            NSLog("ipaste: failed to toggle pin: \(error)")
        }
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
