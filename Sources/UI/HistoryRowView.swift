import AppKit
import SwiftUI

/// One row in the history list: a per-kind preview, a pin toggle, and a
/// delete control. See ARCHITECTURE.md §8.2.
struct HistoryRowView: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isSelected: Bool
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                Text(secondaryText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                deleteButton
                    .opacity(showsDelete ? 1 : 0)
                    .disabled(!showsDelete)
                pinButton
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    /// The delete control is revealed on hover or when the row is selected,
    /// so the row stays uncluttered but the action is always reachable.
    private var showsDelete: Bool { isHovering || isSelected }

    // MARK: - Icon

    /// Images show their real thumbnail; everything else — and images whose
    /// thumbnail could not be generated — shows a colored type badge.
    @ViewBuilder
    private var icon: some View {
        if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            TypeBadge(style: badgeStyle)
        }
    }

    /// Picks the badge to draw for an item that has no visual preview.
    private var badgeStyle: BadgeStyle {
        switch item.kind {
        case .image:
            return .image
        case .file:
            return .file(FileKind(fileName: item.fileName))
        case .text:
            return isCodeText ? .code : .text
        }
    }

    // MARK: - Code detection

    /// A text item is treated as code when it was copied from a developer
    /// app, or when its content looks like code or a shell command.
    private var isCodeText: Bool {
        guard item.kind == .text else { return false }
        if isDeveloperSourceApp { return true }
        return Self.looksLikeCode(item.previewText ?? item.textContent ?? "")
    }

    private var isDeveloperSourceApp: Bool {
        guard let id = item.sourceBundleID else { return false }
        if Self.developerAppBundleIDs.contains(id) { return true }
        return Self.developerBundlePrefixes.contains { id.hasPrefix($0) }
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

    /// A conservative heuristic: text counts as code if it starts with a
    /// shebang, its first word is a known shell command, or it contains two
    /// or more distinctive code tokens. Requiring two tokens keeps ordinary
    /// prose (which may incidentally contain one) from being misflagged.
    private static func looksLikeCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("#!/") { return true }
        let firstLine = trimmed.prefix { $0 != "\n" }
        if let firstWord = firstLine
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
           shellCommands.contains(firstWord.lowercased()) {
            return true
        }
        let hits = codeSignals.reduce(0) {
            $0 + (trimmed.contains($1) ? 1 : 0)
        }
        return hits >= 2
    }

    // MARK: - Controls

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: item.pinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(item.pinned ? "Unpin" : "Pin")
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Remove from history")
    }

    // MARK: - Text

    private var primaryText: String {
        switch item.kind {
        case .text:
            let raw = item.previewText ?? item.textContent ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            if let width = item.pixelWidth, let height = item.pixelHeight {
                return "Image · \(width) × \(height)"
            }
            return "Image"
        case .file:
            return item.fileName ?? "File"
        }
    }

    private var secondaryText: String {
        var parts: [String] = []
        if let app = item.sourceAppName, !app.isEmpty {
            parts.append(app)
        }
        parts.append(item.copiedAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: " · ")
    }
}

// MARK: - Type badge

/// A colored, rounded-square icon shown for clipboard items that have no
/// visual preview of their own — text, code, files, and images whose
/// thumbnail could not be generated.
private struct TypeBadge: View {
    let style: BadgeStyle

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(style.fill)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: style.symbolSize, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// The visual treatment of a `TypeBadge`.
private enum BadgeStyle {
    case text
    case code
    case image
    case file(FileKind)

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo.fill"
        case .file(let kind): return kind.symbol
        }
    }

    var symbolSize: CGFloat {
        switch self {
        case .code: return 14
        case .file(.code): return 14
        default: return 17
        }
    }

    var fill: AnyShapeStyle {
        switch self {
        case .text:
            return AnyShapeStyle(Color(red: 0.36, green: 0.44, blue: 0.88))
        case .code:
            return AnyShapeStyle(Color(red: 0.12, green: 0.62, blue: 0.51))
        case .image:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.49, blue: 0.78),
                    Color(red: 0.43, green: 0.36, blue: 0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .file(let kind):
            return AnyShapeStyle(kind.color)
        }
    }
}

/// File items are color-coded by the kind of file they point at, so the
/// list stays scannable even when no thumbnail is available.
private enum FileKind {
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

    var color: Color {
        switch self {
        case .pdf:      return Color(red: 0.89, green: 0.34, blue: 0.30)
        case .document: return Color(red: 0.24, green: 0.48, blue: 0.83)
        case .image:    return Color(red: 0.25, green: 0.66, blue: 0.42)
        case .video:    return Color(red: 0.85, green: 0.34, blue: 0.56)
        case .audio:    return Color(red: 0.61, green: 0.36, blue: 0.82)
        case .archive:  return Color(red: 0.79, green: 0.54, blue: 0.24)
        case .code:     return Color(red: 0.12, green: 0.62, blue: 0.51)
        case .folder:   return Color(red: 0.43, green: 0.52, blue: 0.66)
        case .generic:  return Color(red: 0.88, green: 0.64, blue: 0.24)
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
