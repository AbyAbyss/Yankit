import Foundation

/// The visual kind of a history item: picks its icon tile, its preview, and
/// whether its title is set in a monospaced font.
enum ItemStyle: Equatable {
    case url
    case code
    case terminal
    case color(hex: String)
    case text
    case image
    case file(FileKind)
    case secret
}

/// Display strings and the visual kind for one item, shared by the history
/// row and the preview pane. See ARCHITECTURE.md §8.2.
struct ItemPresentation {
    let item: ClipboardItem
    /// The item's category, if it has one.
    let category: ClipboardCategory?

    init(item: ClipboardItem, category: ClipboardCategory?) {
        self.item = item
        self.category = category
        style = Self.detectStyle(of: item, isSensitive: category?.isSensitive == true)
    }

    let style: ItemStyle

    var isSensitive: Bool { category?.isSensitive == true }

    var isMonospaced: Bool {
        switch style {
        case .code, .terminal, .color: return true
        case .secret: return item.kind == .text
        default: return false
        }
    }

    /// The first line of the item's content, redacted for sensitive items
    /// unless `revealed`.
    func title(revealed: Bool = false) -> String {
        let text: String
        switch item.kind {
        case .text:
            let raw = item.previewText ?? item.textContent ?? ""
            text = Self.firstLine(of: raw)
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight {
                return "Image · \(width) × \(height)"
            }
            return "Image"
        case .file:
            text = item.fileName ?? "File"
        }
        return redactedIfNeeded(text, revealed: revealed)
    }

    /// The whole text content, for the preview pane.
    func fullText(revealed: Bool = false) -> String {
        let raw = (item.textContent ?? item.previewText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return redactedIfNeeded(raw, revealed: revealed)
    }

    /// "Safari · 2 min ago"
    var sourceAndTime: String {
        var parts: [String] = []
        if let app = item.sourceAppName, !app.isEmpty { parts.append(app) }
        parts.append(relativeTime)
        return parts.joined(separator: " · ")
    }

    var relativeTime: String {
        item.copiedAt.formatted(.relative(presentation: .named))
    }

    /// A short description of the content's size or shape.
    var details: String {
        switch item.kind {
        case .text:
            let text = item.textContent ?? ""
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            return lines > 1 ? "\(lines) lines" : "\(text.count) chars"
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight {
                return "\(width) × \(height)"
            }
            return "Image"
        case .file:
            return ByteCountFormatter.string(
                fromByteCount: Int64(item.byteSize), countStyle: .file
            )
        }
    }

    // MARK: - Redaction

    private func redactedIfNeeded(_ text: String, revealed: Bool) -> String {
        guard isSensitive, !revealed else { return text }
        return Self.redacted(text, visible: category?.visibleCharacters ?? 4)
    }

    /// Keeps the first `visible` characters — at most half, so short
    /// secrets stay mostly hidden — and masks the rest.
    static func redacted(_ text: String, visible: Int) -> String {
        let shown = min(max(visible, 0), text.count / 2)
        return text.prefix(shown) + String(repeating: "•", count: 10)
    }

    private static func firstLine(of raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix { $0 != "\n" })
    }

    // MARK: - Kind detection

    private static func detectStyle(of item: ClipboardItem, isSensitive: Bool) -> ItemStyle {
        if isSensitive { return .secret }
        switch item.kind {
        case .image:
            return .image
        case .file:
            return .file(FileKind(fileName: item.fileName))
        case .text:
            let text = (item.previewText ?? item.textContent ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isHexColor(text) { return .color(hex: text) }
            if isURL(text) { return .url }
            if looksLikeShellCommand(text) { return .terminal }
            if isDeveloperSourceApp(item.sourceBundleID) || looksLikeCode(text) {
                return .code
            }
            return .text
        }
    }

    /// `#RGB` or `#RRGGBB`.
    private static func isHexColor(_ text: String) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let digits = text.dropFirst()
        return (digits.count == 3 || digits.count == 6)
            && digits.allSatisfy(\.isHexDigit)
    }

    /// A single http(s) link with nothing else around it.
    private static func isURL(_ text: String) -> Bool {
        (text.hasPrefix("http://") || text.hasPrefix("https://"))
            && !text.contains(where: \.isWhitespace)
    }

    private static func isDeveloperSourceApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        if developerAppBundleIDs.contains(id) { return true }
        return developerBundlePrefixes.contains { id.hasPrefix($0) }
    }

    private static let developerAppBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.googlecode.iterm2",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.github.atom",
        "org.vim.MacVim",
        "com.panic.Nova",
        "co.zeit.hyper",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    private static let developerBundlePrefixes: [String] = [
        "com.jetbrains.",  // IntelliJ, PyCharm, WebStorm, GoLand, …
    ]

    private static let shellCommands: Set<String> = [
        "git", "npm", "npx", "yarn", "pnpm", "pip", "pip3", "brew", "cd",
        "ls", "sudo", "docker", "kubectl", "cargo", "make", "python",
        "python3", "node", "deno", "bun", "curl", "wget", "ssh", "scp",
        "mkdir", "rm", "cp", "mv", "cat", "echo", "export", "source",
        "chmod", "grep", "sed", "awk", "tar", "unzip", "swift", "go",
        "ruby", "rails", "bundle", "terraform", "gradle", "mvn",
        "xcodebuild",
    ]

    private static let codeSignals: [String] = [
        "};", "=>", "() {", "===", "!==", "</", "/>", "::", "function ",
        "func ", "def ", "const ", "import ", "#include", "console.",
        "printf(",
    ]

    /// A single line that starts with a shebang, a `$ ` prompt, or a known
    /// shell command.
    private static func looksLikeShellCommand(_ text: String) -> Bool {
        guard !text.isEmpty, !text.contains("\n") else { return false }
        if text.hasPrefix("#!/") || text.hasPrefix("$ ") { return true }
        guard let firstWord = text
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        else { return false }
        return shellCommands.contains(firstWord.lowercased())
    }

    /// A conservative heuristic: text counts as code if it contains two or
    /// more distinctive code tokens. Requiring two tokens keeps ordinary
    /// prose (which may incidentally contain one) from being misflagged.
    private static func looksLikeCode(_ text: String) -> Bool {
        let hits = codeSignals.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return hits >= 2
    }
}

/// File items are color-coded by the kind of file they point at, so the
/// list stays scannable even when no thumbnail is available.
enum FileKind: Equatable {
    case pdf, document, image, video, audio, archive, code, folder, generic

    init(fileName: String?) {
        let ext = fileName.map {
            URL(fileURLWithPath: $0).pathExtension.lowercased()
        } ?? ""
        if ext == "pdf" {
            self = .pdf
        } else if FileKind.documentExts.contains(ext) {
            self = .document
        } else if FileKind.imageExts.contains(ext) {
            self = .image
        } else if FileKind.videoExts.contains(ext) {
            self = .video
        } else if FileKind.audioExts.contains(ext) {
            self = .audio
        } else if FileKind.archiveExts.contains(ext) {
            self = .archive
        } else if FileKind.codeExts.contains(ext) {
            self = .code
        } else if ext.isEmpty {
            self = .folder
        } else {
            self = .generic
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.fill"
        case .document: return "doc.text.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .folder: return "folder.fill"
        case .generic: return "doc.fill"
        }
    }

    /// `#RRGGBB` tile color.
    var color: String {
        switch self {
        case .pdf:      return "#E3574D"
        case .document: return "#3D7AD4"
        case .image:    return "#40A86B"
        case .video:    return "#D9578F"
        case .audio:    return "#9C5CD1"
        case .archive:  return "#C98A3D"
        case .code:     return "#1F9E82"
        case .folder:   return "#6E85A8"
        case .generic:  return "#E0A33D"
        }
    }

    private static let documentExts: Set<String> = [
        "doc", "docx", "pages", "rtf", "rtfd", "txt", "md", "markdown",
        "key", "ppt", "pptx", "xls", "xlsx", "numbers", "csv", "tsv",
        "odt", "ods", "odp", "epub",
    ]
    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tiff",
        "tif", "bmp", "svg", "ico", "psd", "ai",
    ]
    private static let videoExts: Set<String> = [
        "mp4", "mov", "avi", "mkv", "webm", "m4v", "mpg", "mpeg",
        "flv", "wmv",
    ]
    private static let audioExts: Set<String> = [
        "mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg",
        "opus", "wma",
    ]
    private static let archiveExts: Set<String> = [
        "zip", "tar", "gz", "tgz", "rar", "7z", "dmg", "bz2", "xz",
        "iso", "pkg",
    ]
    private static let codeExts: Set<String> = [
        "swift", "js", "jsx", "ts", "tsx", "py", "rb", "go", "rs",
        "java", "kt", "c", "cpp", "cc", "h", "hpp", "m", "mm", "cs",
        "php", "json", "yml", "yaml", "xml", "html", "htm", "css",
        "scss", "sh", "bash", "zsh", "sql", "toml", "gradle", "lua",
        "dart",
    ]
}
