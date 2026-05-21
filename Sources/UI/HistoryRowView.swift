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

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                symbol("photo")
            }
        case .file:
            Image(nsImage: fileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(2)
        case .text:
            symbol("doc.text")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
    }

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

    private var fileIcon: NSImage {
        let path = item.fileURL.flatMap { URL(string: $0)?.path } ?? ""
        return NSWorkspace.shared.icon(forFile: path)
    }

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
