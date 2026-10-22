import AppKit
import SwiftUI

/// One row in the history list: an icon tile, the (possibly redacted) title,
/// a line with category, label, source and time, a pin toggle, and the ⌘1–9
/// quick-paste hint. See ARCHITECTURE.md §8.2.
struct HistoryRowView: View {
    let presentation: ItemPresentation
    let thumbnail: NSImage?
    let isSelected: Bool
    /// 1–9 for the first nine rows (⌘1–⌘9 paste them), else nil.
    let shortcutNumber: Int?
    var onTogglePin: () -> Void

    @State private var isHovering = false
    @Environment(\.accent) private var accent

    private var item: ClipboardItem { presentation.item }

    var body: some View {
        HStack(spacing: 12) {
            ItemTile(style: presentation.style, thumbnail: thumbnail)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title())
                    .font(.system(
                        size: 13.5, weight: .semibold,
                        design: presentation.isMonospaced ? .monospaced : .default
                    ))
                    .lineLimit(1)
                subtitle
            }
            Spacer(minLength: 4)
            pinButton
                .opacity(showsPin ? 1 : 0)
                .disabled(!showsPin)
            Text(shortcutNumber.map { "⌘\($0)" } ?? "")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 26, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.09 : isHovering ? 0.04 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(isSelected ? 0.1 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    /// "● Notes · Safari · 2 min ago", with the label (if any) in amber.
    private var subtitle: some View {
        HStack(spacing: 5) {
            if let category = presentation.category {
                Circle()
                    .fill(Color(hex: category.color))
                    .frame(width: 6, height: 6)
            }
            if let label = item.label {
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.amber)
                Text("·")
            }
            Text(subtitleText)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var subtitleText: String {
        guard let category = presentation.category else {
            return presentation.sourceAndTime
        }
        return category.name + " · " + presentation.sourceAndTime
    }

    /// The pin is always shown on pinned rows, and on hover or selection
    /// otherwise, so unpinned rows stay uncluttered.
    private var showsPin: Bool { item.pinned || isHovering || isSelected }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: item.pinned ? "pin.fill" : "pin")
                .font(.system(size: 12))
                .foregroundStyle(item.pinned ? accent.tint : Color.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.pinned ? "Unpin" : "Pin")
    }
}
