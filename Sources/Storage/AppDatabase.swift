import Foundation
import GRDB

/// Owns Yankit's on-disk locations and the SQLite schema migration.
enum AppDatabase {
    /// `~/Library/Application Support/Yankit`, created if missing.
    ///
    /// The directory is created private (`0700`), excluded from Time Machine
    /// backups, and excluded from Spotlight indexing — clipboard history can
    /// contain sensitive content (ARCHITECTURE.md §4.1).
    static func supportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var directory = base.appendingPathComponent("Yankit", isDirectory: true)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? directory.setResourceValues(resourceValues)

        let neverIndex = directory
            .appendingPathComponent(".metadata_never_index")
        if !fileManager.fileExists(atPath: neverIndex.path) {
            fileManager.createFile(atPath: neverIndex.path, contents: nil)
        }
        return directory
    }

    /// `~/Library/Application Support/Yankit/blobs` — image & file payloads.
    static func blobsDirectory() throws -> URL {
        try supportDirectory().appendingPathComponent("blobs", isDirectory: true)
    }

    /// Schema migrations. New schema versions append new migrations so an
    /// existing user's history survives upgrades.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_clipboard_item") { db in
            try db.create(table: "clipboard_item") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("copied_at", .datetime).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("content_hash", .text).notNull()
                t.column("byte_size", .integer).notNull()
                t.column("text_content", .text)
                t.column("preview_text", .text)
                t.column("blob_path", .text)
                t.column("thumbnail_path", .text)
                t.column("pixel_width", .integer)
                t.column("pixel_height", .integer)
                t.column("file_url", .text)
                t.column("file_name", .text)
                t.column("source_bundle_id", .text)
                t.column("source_app_name", .text)
            }
            try db.create(
                index: "idx_item_copied_at",
                on: "clipboard_item", columns: ["copied_at"]
            )
            try db.create(
                index: "idx_item_content_hash",
                on: "clipboard_item", columns: ["content_hash"]
            )
        }
        return migrator
    }

    /// Opens the history database on disk, applying any pending migrations.
    static func openHistoryDatabase() throws -> DatabaseQueue {
        let url = try supportDirectory()
            .appendingPathComponent("history.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        // Restrict the database file to the current user.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
        return queue
    }
}
