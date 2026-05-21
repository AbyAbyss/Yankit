import AppKit
import CryptoKit

/// Watches the system pasteboard and records new copies into the history.
///
/// `NSPasteboard` posts no change notifications, so the monitor polls
/// `changeCount` on a timer. See ARCHITECTURE.md §6.
final class ClipboardMonitor {
    private let repository: ClipboardRepository
    private let blobStore: BlobStore
    private let preferences: Preferences
    private let pasteboard: NSPasteboard = .general

    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    init(
        repository: ClipboardRepository,
        blobStore: BlobStore,
        preferences: Preferences
    ) {
        self.repository = repository
        self.blobStore = blobStore
        self.preferences = preferences
        // Seed with the current value so pre-existing clipboard content is
        // not captured on launch.
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // .common keeps polling during menu tracking and panel display.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Tells the monitor to ignore one upcoming pasteboard change — the one
    /// our own PasteService is about to cause — so the app never re-captures
    /// its own pastes. See ARCHITECTURE.md §6 (self-capture guard).
    func ignoreChangeCount(_ changeCount: Int) {
        ignoredChangeCount = changeCount
    }

    // MARK: - Polling

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        if current == ignoredChangeCount {
            ignoredChangeCount = nil
            return
        }
        capture()
    }

    private func capture() {
        if isPaused { return }
        if preferences.ignoreConcealedItems, hasConcealedMarker() { return }
        let source = NSWorkspace.shared.frontmostApplication
        if isExcludedApp(source) { return }

        // Priority: file URLs, then image, then text (ARCHITECTURE.md §6).
        if let fileURLs = readFileURLs() {
            for url in fileURLs { captureFile(url, source: source) }
        } else if let imageRep = readImageRep() {
            captureImage(imageRep, source: source)
        } else if let text = readText() {
            captureText(text, source: source)
        }
    }

    /// Whether capture is currently paused (ARCHITECTURE.md §6).
    private var isPaused: Bool {
        guard let until = preferences.pausedUntil else { return false }
        return until > Date()
    }

    /// Whether copies from `app` are excluded by the user
    /// (ARCHITECTURE.md §6 step 6).
    private func isExcludedApp(_ app: NSRunningApplication?) -> Bool {
        guard let bundleID = app?.bundleIdentifier else { return false }
        return preferences.excludedBundleIDs.contains(bundleID)
    }

    // MARK: - Per-kind capture

    private func captureText(_ text: String, source: NSRunningApplication?) {
        let data = Data(text.utf8)
        guard data.count <= preferences.maxCaptureBytes else { return }
        let item = ClipboardItem(
            kind: .text,
            contentHash: Self.hash(data),
            byteSize: data.count,
            textContent: text,
            previewText: String(text.prefix(200)),
            sourceBundleID: source?.bundleIdentifier,
            sourceAppName: source?.localizedName
        )
        store(item)
    }

    private func captureImage(_ rep: NSBitmapImageRep, source: NSRunningApplication?) {
        guard let png = ImageProcessing.pngData(from: rep) else { return }
        guard png.count <= preferences.maxCaptureBytes else { return }
        let contentHash = Self.hash(png)
        do {
            // Dedup before writing the blob, so a repeat copy leaves no
            // orphan file on disk (ARCHITECTURE.md §6 step 10).
            if try repository.refloatExisting(hash: contentHash) { return }
            let blobPath = try blobStore.write(png, fileExtension: "png")
            var thumbnailPath: String?
            if let thumb = ImageProcessing.thumbnailPNGData(from: rep) {
                thumbnailPath = try blobStore.write(thumb, fileExtension: "png")
            }
            let item = ClipboardItem(
                kind: .image,
                contentHash: contentHash,
                byteSize: png.count,
                blobPath: blobPath,
                thumbnailPath: thumbnailPath,
                pixelWidth: rep.pixelsWide,
                pixelHeight: rep.pixelsHigh,
                sourceBundleID: source?.bundleIdentifier,
                sourceAppName: source?.localizedName
            )
            try repository.insert(item, maxItems: preferences.maxItems)
        } catch {
            NSLog("ipaste: failed to store image: \(error)")
        }
    }

    private func captureFile(_ url: URL, source: NSRunningApplication?) {
        // Files are stored by reference, not copied. content_hash is the
        // path, so copying the same file again refloats its existing item.
        let contentHash = Self.hash(Data(url.path.utf8))
        let attributes = try? FileManager.default
            .attributesOfItem(atPath: url.path)
        let byteSize = (attributes?[.size] as? Int) ?? 0
        let item = ClipboardItem(
            kind: .file,
            contentHash: contentHash,
            byteSize: byteSize,
            fileURL: url.absoluteString,
            fileName: url.lastPathComponent,
            sourceBundleID: source?.bundleIdentifier,
            sourceAppName: source?.localizedName
        )
        store(item)
    }

    /// Refloats the item if its content is already in history, otherwise
    /// inserts it. Used by text and file capture; image capture inlines the
    /// same logic because it must dedup before writing a blob.
    private func store(_ item: ClipboardItem) {
        do {
            if try repository.refloatExisting(hash: item.contentHash) { return }
            try repository.insert(item, maxItems: preferences.maxItems)
        } catch {
            NSLog("ipaste: failed to store clipboard item: \(error)")
        }
    }

    // MARK: - Pasteboard reading

    private func hasConcealedMarker() -> Bool {
        guard let types = pasteboard.types else { return false }
        let markers: Set<String> = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.TransientType",
        ]
        return types.contains { markers.contains($0.rawValue) }
    }

    private func readFileURLs() -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self], options: options
        ) as? [URL], !objects.isEmpty else { return nil }
        return objects
    }

    private func readImageRep() -> NSBitmapImageRep? {
        if let png = pasteboard.data(forType: .png),
           let rep = NSBitmapImageRep(data: png) {
            return rep
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep
        }
        return nil
    }

    private func readText() -> String? {
        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty else { return nil }
        return text
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
