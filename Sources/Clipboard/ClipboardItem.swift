import Foundation
import GRDB

/// The kind of content a clipboard item holds.
enum ClipboardItemKind: String, Codable {
    case text
    case image
    case file
}

/// One entry in the clipboard history.
///
/// Persisted in the `clipboard_item` table. Image and file payloads are not
/// stored inline — they live on disk and are referenced by path (see
/// `BlobStore`). See ARCHITECTURE.md §4.
struct ClipboardItem: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var kind: ClipboardItemKind
    var copiedAt: Date = Date()
    var pinned: Bool = false
    var contentHash: String
    var byteSize: Int

    // Text items.
    var textContent: String? = nil
    var previewText: String? = nil

    // Image items — payload + thumbnail are stored on disk by BlobStore.
    var blobPath: String? = nil
    var thumbnailPath: String? = nil
    var pixelWidth: Int? = nil
    var pixelHeight: Int? = nil

    // File items — a reference to the original on-disk location.
    var fileURL: String? = nil
    var fileName: String? = nil

    // Provenance — drives the app-exclusion feature.
    var sourceBundleID: String? = nil
    var sourceAppName: String? = nil

    /// Maps Swift's camelCase properties to the snake_case database columns.
    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case copiedAt = "copied_at"
        case pinned
        case contentHash = "content_hash"
        case byteSize = "byte_size"
        case textContent = "text_content"
        case previewText = "preview_text"
        case blobPath = "blob_path"
        case thumbnailPath = "thumbnail_path"
        case pixelWidth = "pixel_width"
        case pixelHeight = "pixel_height"
        case fileURL = "file_url"
        case fileName = "file_name"
        case sourceBundleID = "source_bundle_id"
        case sourceAppName = "source_app_name"
    }
}

extension ClipboardItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "clipboard_item"
}
