import Foundation

/// Stores image and file payloads as individual files on disk, keeping the
/// SQLite database itself small and fast. Items reference a blob by a path
/// relative to the blob directory. See ARCHITECTURE.md §4.1.
final class BlobStore {
    private let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// Writes `data` to a uniquely named file and returns its path relative
    /// to the blob directory — that relative path is what gets stored in the
    /// database row.
    func write(_ data: Data, fileExtension: String) throws -> String {
        let name = UUID().uuidString + "." + fileExtension
        try data.write(to: directory.appendingPathComponent(name))
        return name
    }

    func absoluteURL(forRelativePath relativePath: String) -> URL {
        directory.appendingPathComponent(relativePath)
    }

    func data(forRelativePath relativePath: String) throws -> Data {
        try Data(contentsOf: absoluteURL(forRelativePath: relativePath))
    }

    /// Deletes a blob. A missing file is not an error: eviction must be
    /// tolerant of a half-completed earlier run.
    func delete(relativePath: String) {
        try? FileManager.default.removeItem(
            at: absoluteURL(forRelativePath: relativePath)
        )
    }

    func fileExists(relativePath: String) -> Bool {
        FileManager.default.fileExists(
            atPath: absoluteURL(forRelativePath: relativePath).path
        )
    }

    /// Deletes every blob whose name is not in `referenced` — used by the
    /// startup integrity sweep (ARCHITECTURE.md §7).
    func deleteUnreferenced(keeping referenced: Set<String>) throws {
        let names = try FileManager.default.contentsOfDirectory(
            atPath: directory.path
        )
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(
                at: directory.appendingPathComponent(name)
            )
        }
    }

    /// Removes every stored blob.
    func deleteAll() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }
}
