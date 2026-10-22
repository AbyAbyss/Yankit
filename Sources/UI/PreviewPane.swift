import AppKit
import QuickLookThumbnailing
import SwiftUI

/// The right-hand pane of the history panel (beta, off by default): a large
/// preview of the selected item, its details, and its main actions.
/// See ARCHITECTURE.md §8.2.
struct PreviewPane<MoveMenu: View>: View {
    let presentation: ItemPresentation
    let thumbnail: NSImage?
    /// Shows sensitive content in full (Peek button or ⌥ held).
    let isRevealing: Bool
    var loadFullImage: () -> NSImage?
    var onPaste: () -> Void
    var onTogglePin: () -> Void
    var onTogglePeek: () -> Void
    @ViewBuilder var moveMenu: () -> MoveMenu

    @Environment(\.accent) private var accent

    /// The full image, or a file's QuickLook thumbnail, loaded on demand.
    @State private var loadedImage: NSImage?

    private var item: ClipboardItem { presentation.item }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            previewCard
                .frame(maxWidth: .infinity)
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            titleBlock
            details
            Spacer(minLength: 0)
            actions
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .task(id: item.id) { await loadImage() }
    }

    // MARK: - Preview card

    @ViewBuilder
    private var previewCard: some View {
        switch presentation.style {
        case .secret:
            secretCard
        case .terminal:
            VStack(alignment: .leading, spacing: 6) {
                Text(item.sourceAppName ?? "Terminal")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                (Text("➜ ").foregroundColor(Color(hex: "#7CF29A"))
                    + Text(presentation.fullText()).foregroundColor(.white))
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(5)
                Spacer(minLength: 0)
                Text("▍").foregroundStyle(Color(hex: "#7CF29A"))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(hex: "#060807"))
        case .code:
            textCard(
                font: .system(size: 12.5, design: .monospaced),
                color: Color(hex: "#E6E6E6"),
                background: Color(hex: "#0D0F14")
            )
        case .text:
            textCard(
                font: .system(size: 19, design: .serif),
                color: Color(hex: "#E8FFF7"),
                background: Color(hex: "#0F1D1A")
            )
        case .url:
            urlCard
        case .color(let hex):
            colorCard(hex: hex)
        case .image:
            ZStack {
                Color.black
                if let image = loadedImage ?? thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
        case .file:
            ZStack {
                Color(hex: "#2A2620")
                if let image = loadedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(18)
                }
            }
        }
    }

    private func textCard(font: Font, color: Color, background: Color) -> some View {
        ScrollView {
            Text(presentation.fullText())
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(18)
        }
        .background(background)
    }

    private var urlCard: some View {
        let text = presentation.fullText()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(Color(hex: "#FF5F57")).frame(width: 8, height: 8)
                Circle().fill(Color(hex: "#FEBC2E")).frame(width: 8, height: 8)
                Circle().fill(Color(hex: "#28C840")).frame(width: 8, height: 8)
            }
            Spacer(minLength: 0)
            Text(URL(string: text)?.host() ?? text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(hex: "#10141C"))
    }

    /// The color itself, its hex code, and four lighter and darker tints.
    private func colorCard(hex: String) -> some View {
        let base = NSColor(hex: hex)
        let tints: [NSColor] = [
            base.blended(withFraction: 0.6, of: .white),
            base.blended(withFraction: 0.3, of: .white),
            base.blended(withFraction: 0.25, of: .black),
            base.blended(withFraction: 0.55, of: .black),
        ].compactMap { $0 }
        let isLight = (base.usingColorSpace(.sRGB)?.brightnessComponent ?? 0) > 0.6
        return VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text(hex.uppercased())
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(isLight ? Color.black.opacity(0.8) : Color.white)
                .padding(16)
            HStack(spacing: 4) {
                ForEach(tints.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: tints[index]))
                }
            }
            .frame(height: 18)
            .padding([.horizontal, .bottom], 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(nsColor: base))
    }

    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SENSITIVE · \(presentation.category?.name.uppercased() ?? "")")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.amber)
                Spacer()
                Text("Redacted in list and search")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if item.kind == .image {
                // The image is only drawn while revealed, so nothing of it
                // shows otherwise.
                secretBox {
                    if isRevealing, let image = loadedImage ?? thumbnail {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Label("Image hidden", systemImage: "eye.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            } else {
                // Text shows its redacted content; a file its redacted name.
                secretBox {
                    Text(item.kind == .text
                         ? presentation.fullText(revealed: isRevealing)
                         : presentation.title(revealed: isRevealing))
                        .font(.system(
                            size: 17, weight: .semibold,
                            design: item.kind == .text ? .monospaced : .default
                        ))
                        .lineLimit(3)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Button(action: onTogglePeek) {
                    Label(isRevealing ? "Hide" : "Peek",
                          systemImage: isRevealing ? "eye.slash" : "eye")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(Theme.amber.opacity(0.16))
                        )
                }
                .buttonStyle(.plain)
                Text("or hold ⌥")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.04))
    }

    /// The amber-outlined box that holds a sensitive item's content.
    private func secretBox<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.amber.opacity(0.3), lineWidth: 1)
            )
    }

    // MARK: - Title & details

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(presentation.title(revealed: isRevealing))
                .font(.system(
                    size: 15, weight: .semibold,
                    design: presentation.isMonospaced ? .monospaced : .default
                ))
                .lineLimit(1)
            if let label = item.label {
                Label(label, systemImage: "tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                detail("Source", item.sourceAppName ?? "—")
                detail("Copied", presentation.relativeTime)
            }
            GridRow {
                HStack {
                    Text("Category").foregroundStyle(.secondary)
                    Spacer()
                    if let category = presentation.category {
                        Circle().fill(Color(hex: category.color)).frame(width: 6, height: 6)
                        Text(category.name)
                    } else {
                        Text("None")
                    }
                }
                detail("Details", presentation.details)
            }
        }
        .font(.system(size: 12))
    }

    private func detail(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onPaste) {
                HStack(spacing: 8) {
                    Text("Paste")
                    Text("⏎").font(.system(size: 11, design: .monospaced)).opacity(0.65)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent.onFill)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(accent.fill))
            }
            .buttonStyle(.plain)
            Button(action: onTogglePin) {
                secondaryActionLabel(item.pinned ? "Unpin" : "Pin", shortcut: "⌘P")
            }
            .buttonStyle(.plain)
            Menu(content: moveMenu) {
                secondaryActionLabel("Move to…", shortcut: "⌘M")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func secondaryActionLabel(_ title: String, shortcut: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Text(shortcut).font(.system(size: 11, design: .monospaced)).opacity(0.55)
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
    }

    // MARK: - Loading

    /// Loads the full image for image items, or a QuickLook thumbnail for
    /// files (falling back to the file's Finder icon).
    private func loadImage() async {
        loadedImage = nil
        switch item.kind {
        case .image:
            loadedImage = loadFullImage()
        case .file:
            guard let url = item.fileURL.flatMap(URL.init(string:)) else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 240, height: 240),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            if let representation = try? await QLThumbnailGenerator.shared
                .generateBestRepresentation(for: request) {
                loadedImage = representation.nsImage
            } else {
                loadedImage = NSWorkspace.shared.icon(forFile: url.path)
            }
        case .text:
            break
        }
    }
}
