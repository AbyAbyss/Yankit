import Foundation
import GRDB

/// Reads and writes the clipboard history. Owns deduplication, eviction, and
/// auto-expiry.
///
/// This is pure storage logic — it knows nothing about UserDefaults. Callers
/// pass `maxItems` explicitly, which keeps the repository fully testable.
/// See ARCHITECTURE.md §7.
final class ClipboardRepository {
    private let queue: DatabaseQueue
    private let blobStore: BlobStore

    init(queue: DatabaseQueue, blobStore: BlobStore) {
        self.queue = queue
        self.blobStore = blobStore
    }

    /// Items that are neither pinned nor in a category — the auto-managed
    /// part of the history that eviction and auto-expiry may delete.
    private static let isEvictable =
        Column("pinned") == false && Column("category_id") == nil

    /// Inserts a new item, then evicts the oldest evictable items so that no
    /// more than `maxItems` evictable items remain. Pinned and categorized
    /// items are exempt and do not count toward the cap.
    func insert(_ item: ClipboardItem, maxItems: Int) throws {
        try queue.write { db in
            try item.insert(db)
            try self.evictExcess(db, maxItems: maxItems)
        }
    }

    /// Evicts the oldest evictable items so that at most `maxItems` remain.
    /// Used when the user lowers the cap in Settings (ARCHITECTURE.md §7).
    func enforceLimit(maxItems: Int) throws {
        try queue.write { db in
            try self.evictExcess(db, maxItems: maxItems)
        }
    }

    /// If an item with the same content already exists anywhere in the
    /// history, refloats it to the top (updates `copiedAt`) and returns
    /// `true`. Otherwise returns `false`.
    ///
    /// This is the whole-history dedup callers run *before* inserting, so a
    /// repeated copy never produces a duplicate row. See ARCHITECTURE.md §7.
    @discardableResult
    func refloatExisting(hash: String) throws -> Bool {
        try queue.write { db in
            guard var existing = try ClipboardItem
                .filter(Column("content_hash") == hash)
                .fetchOne(db)
            else { return false }
            existing.copiedAt = Date()
            try existing.update(db)
            return true
        }
    }

    /// All items, newest first.
    func allItems() throws -> [ClipboardItem] {
        try queue.read { db in
            try ClipboardItem
                .order(Column("copied_at").desc)
                .fetchAll(db)
        }
    }

    func count() throws -> Int {
        try queue.read { db in try ClipboardItem.fetchCount(db) }
    }

    func setPinned(_ pinned: Bool, id: String) throws {
        try queue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id)
            else { return }
            item.pinned = pinned
            try item.update(db)
        }
    }

    /// Moves an item into a category, or back to normal history when
    /// `categoryID` is nil.
    func setCategory(_ categoryID: String?, id: String) throws {
        try queue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id)
            else { return }
            item.categoryID = categoryID
            try item.update(db)
        }
    }

    /// Sets an item's user label; nil removes it.
    func setLabel(_ label: String?, id: String) throws {
        try queue.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id)
            else { return }
            item.label = label
            try item.update(db)
        }
    }

    func delete(id: String) throws {
        try queue.write { db in
            guard let item = try ClipboardItem.fetchOne(db, key: id)
            else { return }
            self.deleteBlobs(of: item)
            try item.delete(db)
        }
    }

    /// Clears every history row and every blob on disk.
    func deleteAll() throws {
        try queue.write { db in
            _ = try ClipboardItem.deleteAll(db)
        }
        try blobStore.deleteAll()
    }

    /// Deletes evictable items older than `days`, returning how many were
    /// removed. A non-positive `days` is a no-op. See ARCHITECTURE.md §7.
    @discardableResult
    func expireItems(olderThanDays days: Int) throws -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Calendar.current.date(
            byAdding: .day, value: -days, to: Date()
        ) ?? Date()
        return try queue.write { db in
            let stale = try ClipboardItem
                .filter(Self.isEvictable)
                .filter(Column("copied_at") < cutoff)
                .fetchAll(db)
            for item in stale {
                self.deleteBlobs(of: item)
                try item.delete(db)
            }
            return stale.count
        }
    }

    /// Removes blob files that no row references, and rows whose image blob
    /// is missing from disk. Run once at launch (ARCHITECTURE.md §7).
    func runIntegritySweep() throws {
        for item in try allItems() {
            if let blobPath = item.blobPath,
               !blobStore.fileExists(relativePath: blobPath) {
                try delete(id: item.id)
            }
        }
        var referenced = Set<String>()
        for item in try allItems() {
            if let blobPath = item.blobPath { referenced.insert(blobPath) }
            if let thumbnailPath = item.thumbnailPath {
                referenced.insert(thumbnailPath)
            }
        }
        try blobStore.deleteUnreferenced(keeping: referenced)
    }

    // MARK: - Categories

    /// All categories, oldest first — the order their chips appear in.
    func allCategories() throws -> [ClipboardCategory] {
        try queue.read { db in
            try ClipboardCategory.order(Column("created_at")).fetchAll(db)
        }
    }

    /// Inserts a new category or updates an existing one.
    func saveCategory(_ category: ClipboardCategory) throws {
        try queue.write { db in
            try category.save(db)
        }
    }

    /// Deletes a category. Its items stay in the history: the foreign key
    /// clears their `category_id`, so they become evictable again.
    func deleteCategory(id: String) throws {
        try queue.write { db in
            _ = try ClipboardCategory.deleteOne(db, key: id)
        }
    }

    // MARK: - Private

    /// Drops the oldest evictable rows (and their blobs) until at most
    /// `maxItems` evictable rows remain.
    private func evictExcess(_ db: Database, maxItems: Int) throws {
        let evictableCount = try ClipboardItem
            .filter(Self.isEvictable)
            .fetchCount(db)
        let surplus = evictableCount - maxItems
        guard surplus > 0 else { return }

        let victims = try ClipboardItem
            .filter(Self.isEvictable)
            .order(Column("copied_at").asc)
            .limit(surplus)
            .fetchAll(db)
        for item in victims {
            deleteBlobs(of: item)
            try item.delete(db)
        }
    }

    private func deleteBlobs(of item: ClipboardItem) {
        if let blobPath = item.blobPath {
            blobStore.delete(relativePath: blobPath)
        }
        if let thumbnailPath = item.thumbnailPath {
            blobStore.delete(relativePath: thumbnailPath)
        }
    }
}
