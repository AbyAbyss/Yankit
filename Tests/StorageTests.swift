import XCTest
import GRDB
@testable import Yankit

/// Verifies the Phase 1 storage layer: insert, whole-history dedup,
/// pinned-aware eviction, blob cleanup, and auto-expiry.
final class StorageTests: XCTestCase {
    private var repository: ClipboardRepository!
    private var blobStore: BlobStore!
    private var blobDirectory: URL!

    override func setUpWithError() throws {
        let queue = try DatabaseQueue()          // in-memory database
        try AppDatabase.migrator.migrate(queue)

        blobDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Yankit-tests-\(UUID().uuidString)")
        blobStore = try BlobStore(directory: blobDirectory)
        repository = ClipboardRepository(queue: queue, blobStore: blobStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: blobDirectory)
        repository = nil
        blobStore = nil
        blobDirectory = nil
    }

    // MARK: - Helpers

    private func textItem(
        _ text: String,
        copiedAt: Date = Date(),
        pinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            kind: .text,
            copiedAt: copiedAt,
            pinned: pinned,
            contentHash: "hash-\(text)",
            byteSize: text.utf8.count,
            textContent: text,
            previewText: text
        )
    }

    // MARK: - Insert

    func testInsertStoresItem() throws {
        try repository.insert(textItem("hello"), maxItems: 30)

        XCTAssertEqual(try repository.count(), 1)
        XCTAssertEqual(try repository.allItems().first?.textContent, "hello")
    }

    // MARK: - Deduplication

    func testDuplicateHashRefloatsInsteadOfInserting() throws {
        let old = Date(timeIntervalSinceNow: -3600)
        try repository.insert(textItem("dup", copiedAt: old), maxItems: 30)

        let didRefloat = try repository.refloatExisting(hash: "hash-dup")

        XCTAssertTrue(didRefloat)
        XCTAssertEqual(try repository.count(), 1, "Dedup must not add a row")
        let item = try XCTUnwrap(repository.allItems().first)
        XCTAssertGreaterThan(item.copiedAt, old, "Refloat must update copiedAt")
    }

    func testRefloatReturnsFalseWhenContentIsNew() throws {
        XCTAssertFalse(try repository.refloatExisting(hash: "never-seen"))
    }

    // MARK: - Eviction

    func testEvictionDropsOldestUnpinnedBeyondCap() throws {
        for i in 0..<5 {
            try repository.insert(
                textItem("item\(i)",
                         copiedAt: Date(timeIntervalSinceNow: Double(i))),
                maxItems: 3
            )
        }

        let remaining = Set(try repository.allItems().compactMap(\.textContent))
        XCTAssertEqual(remaining, ["item2", "item3", "item4"])
    }

    func testPinnedItemsSurviveEvictionAndDoNotCountTowardCap() throws {
        try repository.insert(
            textItem("kept",
                     copiedAt: Date(timeIntervalSinceNow: -100),
                     pinned: true),
            maxItems: 2
        )
        for i in 0..<5 {
            try repository.insert(
                textItem("u\(i)",
                         copiedAt: Date(timeIntervalSinceNow: Double(i))),
                maxItems: 2
            )
        }

        let items = try repository.allItems()
        XCTAssertEqual(items.count, 3, "2 unpinned (cap) + 1 pinned (exempt)")
        XCTAssertTrue(items.contains { $0.textContent == "kept" })
    }

    func testEvictionDeletesImageBlobsFromDisk() throws {
        let relativePath = try blobStore.write(
            Data([0xDE, 0xAD]), fileExtension: "png"
        )
        let blobURL = blobStore.absoluteURL(forRelativePath: relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: blobURL.path))

        var image = textItem("image",
                             copiedAt: Date(timeIntervalSinceNow: -100))
        image.kind = .image
        image.blobPath = relativePath
        try repository.insert(image, maxItems: 1)

        // A newer unpinned item forces the older image out.
        try repository.insert(textItem("newer"), maxItems: 1)

        XCTAssertEqual(try repository.count(), 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: blobURL.path),
            "Evicting an image item must delete its blob file"
        )
    }

    // MARK: - Auto-expire

    func testExpireRemovesOldUnpinnedItemsOnly() throws {
        let tenDaysAgo = Date(timeIntervalSinceNow: -10 * 86_400)
        try repository.insert(
            textItem("ancient", copiedAt: tenDaysAgo), maxItems: 30
        )
        try repository.insert(
            textItem("ancientKept", copiedAt: tenDaysAgo, pinned: true),
            maxItems: 30
        )
        try repository.insert(textItem("fresh"), maxItems: 30)

        let removed = try repository.expireItems(olderThanDays: 7)

        XCTAssertEqual(removed, 1)
        let remaining = Set(try repository.allItems().compactMap(\.textContent))
        XCTAssertEqual(remaining, ["ancientKept", "fresh"])
    }

    func testExpireWithZeroDaysIsNoOp() throws {
        try repository.insert(
            textItem("x", copiedAt: Date(timeIntervalSinceNow: -86_400)),
            maxItems: 30
        )
        XCTAssertEqual(try repository.expireItems(olderThanDays: 0), 0)
        XCTAssertEqual(try repository.count(), 1)
    }

    // MARK: - Pinning

    func testSetPinnedUpdatesItem() throws {
        let item = textItem("pin me")
        try repository.insert(item, maxItems: 30)

        try repository.setPinned(true, id: item.id)

        XCTAssertEqual(try repository.allItems().first?.pinned, true)
    }

    // MARK: - Clear

    func testDeleteAllClearsRowsAndBlobs() throws {
        let relativePath = try blobStore.write(
            Data([0x01]), fileExtension: "png"
        )
        var image = textItem("image")
        image.kind = .image
        image.blobPath = relativePath
        try repository.insert(image, maxItems: 30)

        try repository.deleteAll()

        XCTAssertEqual(try repository.count(), 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: blobStore
                    .absoluteURL(forRelativePath: relativePath).path
            )
        )
    }

    // MARK: - Integrity sweep

    func testIntegritySweepRemovesOrphansAndBrokenRows() throws {
        let healthyBlob = try blobStore.write(
            Data([0x01]), fileExtension: "png"
        )
        var healthy = textItem("healthy")
        healthy.kind = .image
        healthy.blobPath = healthyBlob
        try repository.insert(healthy, maxItems: 30)

        var broken = textItem("broken")
        broken.kind = .image
        broken.blobPath = "missing-\(UUID().uuidString).png"
        try repository.insert(broken, maxItems: 30)

        let orphan = try blobStore.write(Data([0x02]), fileExtension: "png")

        try repository.runIntegritySweep()

        let texts = Set(try repository.allItems().compactMap(\.textContent))
        XCTAssertEqual(texts, ["healthy"], "Row with a missing blob is removed")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: blobStore.absoluteURL(forRelativePath: orphan).path
            ),
            "Unreferenced blob file is removed"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: blobStore
                    .absoluteURL(forRelativePath: healthyBlob).path
            ),
            "Referenced blob file is kept"
        )
    }
}
