import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The history panel content: a search header and a chip bar over the
/// keyboard-navigable list, an optional preview pane (beta), and a footer
/// of shortcuts. List navigation keys are handled by
/// `HistoryPanelController`; this view handles search, chips, display, and
/// the in-panel cards. See ARCHITECTURE.md §8.2.
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var preferences: Preferences
    var onSelectItem: (ClipboardItem) -> Void
    var onOpenSettings: () -> Void

    /// The panel's size without and with the preview pane.
    static let compactSize = CGSize(width: 440, height: 560)
    static let wideSize = CGSize(width: 880, height: 560)

    @FocusState private var searchFocused: Bool
    /// The chip a dragged row is hovering over.
    @State private var dropTarget: HistoryFilter?

    private var isWide: Bool { preferences.showPreviewPane }
    private var accent: AppAccent { preferences.accent }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                chipBar
                Divider()
                HStack(spacing: 0) {
                    list
                        .frame(width: isWide ? 404 : nil)
                    if isWide {
                        Divider()
                        preview
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
            overlayCard
        }
        .frame(
            width: isWide ? Self.wideSize.width : Self.compactSize.width,
            height: Self.compactSize.height
        )
        .background(PanelBackground(
            material: preferences.panelMaterial,
            opacity: preferences.panelOpacity,
            cornerRadius: 24
        ))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .environment(\.accent, preferences.accent)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        // Hand focus back to search once a card closes, or on ⌘K.
        .onChange(of: viewModel.isEditing) { _, isEditing in
            if !isEditing { searchFocused = true }
        }
        .onChange(of: viewModel.searchFocusRequest) { _, _ in
            searchFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard, or type a category", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($searchFocused)
            Keycap("⌘K")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .frame(height: 58)
    }

    // MARK: - Chips

    private var chipBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(filter: .recent) { Text("Recent") }
                    chip(filter: .pinned) {
                        Image(systemName: "pin.fill").font(.system(size: 9))
                        Text("Pinned")
                        Text("\(viewModel.pinnedCount)").fontWeight(.medium).opacity(0.7)
                    }
                    if !viewModel.categories.isEmpty {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 1, height: 18)
                            .padding(.horizontal, 4)
                    }
                    ForEach(viewModel.categories) { category in
                        chip(filter: .category(category.id)) {
                            Circle()
                                .fill(Color(hex: category.color))
                                .frame(width: 7, height: 7)
                            Text(category.name)
                            if category.isSensitive {
                                Image(systemName: "lock.fill").font(.system(size: 9))
                            }
                            Text("\(viewModel.itemCount(in: category))")
                                .fontWeight(.medium)
                                .opacity(0.65)
                        }
                        .contextMenu { chipMenu(for: category) }
                    }
                    Button {
                        viewModel.overlay = .categoryEditor(nil, moveItemID: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("New Category (⌘N)")
                }
                .padding(.horizontal, 16)
            }
            if isWide {
                HStack(spacing: 6) {
                    Keycap("⇥")
                    Text("switch")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.trailing, 16)
            }
        }
        .frame(height: 44)
    }

    /// A chip that selects `filter`. Recent and category chips also accept
    /// dropped rows (see `HistoryViewModel.moveDroppedItem`).
    private func chip<Label: View>(
        filter: HistoryFilter,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let isSelected = viewModel.filter == filter
        let acceptsDrop = filter != .pinned
        return Button {
            viewModel.filter = filter
        } label: {
            HStack(spacing: 6) { label() }
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .foregroundStyle(isSelected ? accent.onFill : Color.primary)
                .background(
                    Capsule().fill(isSelected ? accent.fill : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule().strokeBorder(
                        accent.tint,
                        lineWidth: dropTarget == filter ? 1.5 : 0
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dropDestination(for: DraggedHistoryItem.self) { dropped, _ in
            guard acceptsDrop, let id = dropped.first?.id else { return false }
            return viewModel.moveDroppedItem(id: id, to: filter)
        } isTargeted: { isTargeted in
            if isTargeted, acceptsDrop {
                dropTarget = filter
            } else if dropTarget == filter {
                dropTarget = nil
            }
        }
    }

    @ViewBuilder
    private func chipMenu(for category: ClipboardCategory) -> some View {
        Button("Edit Category…") {
            viewModel.overlay = .categoryEditor(category, moveItemID: nil)
        }
        Divider()
        Button("Delete Category") { viewModel.deleteCategory(category) }
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        let items = viewModel.filteredItems
        if items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, index: index)
                        }
                    }
                    .padding(8)
                }
                .onPreferenceChange(SelectedRowFrameKey.self) { frame in
                    viewModel.selectedRowFrame = frame
                }
                // Scroll only as far as needed to keep the row visible.
                .onChange(of: viewModel.keyboardScrollRequest) { _, _ in
                    guard let id = viewModel.selectedItem?.id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }

    /// One row. A click selects it; a double-click pastes it.
    private func row(_ item: ClipboardItem, index: Int) -> some View {
        HistoryRowView(
            presentation: viewModel.presentation(of: item),
            thumbnail: viewModel.thumbnails[item.id],
            isSelected: index == viewModel.selectedIndex,
            shortcutNumber: index < 9 ? index + 1 : nil,
            onTogglePin: { viewModel.togglePin(item) }
        )
        .onTapGesture(count: 2) { onSelectItem(item) }
        .simultaneousGesture(TapGesture().onEnded { viewModel.selectedIndex = index })
        .contextMenu { rowMenu(for: item) }
        .draggable(DraggedHistoryItem(id: item.id))
        .background {
            if index == viewModel.selectedIndex {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SelectedRowFrameKey.self,
                        value: geometry.frame(in: .global)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for item: ClipboardItem) -> some View {
        Button("Paste") { onSelectItem(item) }
            .keyboardShortcut(.return, modifiers: [])
        Button(item.pinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
            .keyboardShortcut("p")
        Menu("Move to Category") { moveMenu(for: item) }
        Button(item.label == nil ? "Add Label…" : "Edit Label…") {
            viewModel.overlay = .label(itemID: item.id)
        }
        .keyboardShortcut("l")
        Divider()
        Button("Delete") { viewModel.delete(item) }
            .keyboardShortcut(.delete)
    }

    /// The categories, with the item's current one checked (choosing it
    /// again takes the item out), then "New Category…".
    @ViewBuilder
    private func moveMenu(for item: ClipboardItem) -> some View {
        ForEach(viewModel.categories) { category in
            Toggle(category.name, isOn: Binding(
                get: { item.categoryID == category.id },
                set: { viewModel.setCategory($0 ? category.id : nil, for: item) }
            ))
        }
        if !viewModel.categories.isEmpty { Divider() }
        Button("New Category…") {
            viewModel.overlay = .categoryEditor(nil, moveItemID: item.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptySymbol)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            emptyMessage
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySymbol: String {
        guard viewModel.searchText.isEmpty else { return "magnifyingglass" }
        return viewModel.filter == .pinned ? "pin" : "doc.on.clipboard"
    }

    private var emptyMessage: Text {
        guard viewModel.searchText.isEmpty else { return Text("No matches") }
        switch viewModel.filter {
        case .recent:
            return Text("No clipboard history yet")
        case .pinned:
            return Text("Nothing pinned yet.\nSelect any item and press ⌘P")
        case .category:
            return Text("Nothing here yet.\nDrag an item onto this tab, or press ⌘M")
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let item = viewModel.selectedItem {
            PreviewPane(
                presentation: viewModel.presentation(of: item),
                thumbnail: viewModel.thumbnails[item.id],
                isRevealing: viewModel.isRevealing,
                loadFullImage: { viewModel.fullImage(for: item) },
                onPaste: { onSelectItem(item) },
                onTogglePin: { viewModel.togglePin(item) },
                onTogglePeek: { viewModel.isPeekToggled.toggle() },
                moveMenu: { moveMenu(for: item) }
            )
            .id(item.id)
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: isWide ? 14 : 10) {
            hint("move", keys: "↑", "↓")
            hint("paste", keys: "⏎")
            hint("pin", keys: "⌘P")
            hint("move", keys: "⌘M")
            hint("delete", keys: "⌘⌫")
            Spacer(minLength: 0)
            if isWide {
                HStack(spacing: 7) {
                    Text("Y")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(accent.onFill)
                        .frame(width: 14, height: 14)
                        .background(RoundedRectangle(cornerRadius: 4).fill(accent.fill))
                    Text("Yankit").fontWeight(.semibold)
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, isWide ? 18 : 14)
        .frame(height: 40)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Divider() }
    }

    private func hint(_ title: String, keys: String...) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { Keycap($0) }
            Text(title)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 2)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private var overlayCard: some View {
        switch viewModel.overlay {
        case .label(let itemID):
            if let item = viewModel.items.first(where: { $0.id == itemID }) {
                LabelCard(
                    initialText: item.label ?? "",
                    suggestions: viewModel.labelSuggestions(excluding: item.label),
                    onCommit: { viewModel.commitLabel($0, forItemID: itemID) }
                )
                .frame(width: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 20)
                .padding(.bottom, 52)
            }
        case .categoryEditor(let category, let moveItemID):
            ZStack(alignment: .top) {
                Color.black.opacity(0.35)
                    .onTapGesture { viewModel.overlay = nil }
                ScrollView {
                    CategoryEditor(
                        category: category,
                        onSave: {
                            viewModel.saveCategory(
                                $0, isNew: category == nil, moveItemID: moveItemID
                            )
                        },
                        onCancel: { viewModel.overlay = nil }
                    )
                    .background(CardBackground(cornerRadius: 20))
                    .padding(16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        case nil:
            EmptyView()
        }
    }
}

/// The "Label this item" card: a text field, labels already in use as
/// suggestions, and a note. Return saves; Escape is handled by
/// `HistoryPanelController`.
private struct LabelCard: View {
    let suggestions: [String]
    var onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.accent) private var accent

    init(initialText: String, suggestions: [String], onCommit: @escaping (String) -> Void) {
        self.suggestions = suggestions
        self.onCommit = onCommit
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Label this item", systemImage: "tag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.amber)
            TextField("Label", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($focused)
                .onSubmit { onCommit(text) }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 9).strokeBorder(accent.tint, lineWidth: 1.5)
                )
            if !suggestions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { onCommit(suggestion) } label: {
                            Text(suggestion)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Labels show alongside redacted items, and are searchable.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CardBackground(cornerRadius: 14))
        .onAppear {
            DispatchQueue.main.async { focused = true }
        }
    }
}

/// A raised card surface for content drawn over the panel.
struct CardBackground: View {
    var cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

/// A key glyph, as in the footer: "⌘P".
struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// A history row being dragged onto a chip. It carries only the item id,
/// under a private type so other apps ignore the drop.
struct DraggedHistoryItem: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .yankitHistoryItem)
    }
}

extension UTType {
    /// Declared in Info.plist (`UTExportedTypeDeclarations`).
    static let yankitHistoryItem = UTType(exportedAs: "com.yankit.app.history-item")
}

/// Reports the selected row's frame up to the list.
private struct SelectedRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// The panel background: the chosen material, with the window background
/// color layered on top at the user's opacity (0 = material only,
/// 1 = solid). `blendingMode` is `.withinWindow` for the preview in
/// Settings, which sits over a drawn backdrop rather than the desktop.
struct PanelBackground: View {
    var material: PanelMaterial
    var opacity: Double
    var cornerRadius: CGFloat
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        switch material {
        case .solid:
            Color(nsColor: .windowBackgroundColor)
        case .clearGlass, .glass, .translucent:
            ZStack {
                effect
                Color(nsColor: .windowBackgroundColor).opacity(opacity)
            }
        }
    }

    @ViewBuilder
    private var effect: some View {
        if #available(macOS 26, *), material.isGlass {
            GlassEffectBackground(
                style: material == .clearGlass ? .clear : .regular,
                cornerRadius: cornerRadius
            )
        } else {
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: blendingMode,
                cornerRadius: cornerRadius
            )
        }
    }
}

/// Bridges `NSGlassEffectView` (Liquid Glass, macOS 26+) into SwiftUI.
@available(macOS 26, *)
private struct GlassEffectBackground: NSViewRepresentable {
    var style: NSGlassEffectView.Style
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = style
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.style = style
        view.cornerRadius = cornerRadius
    }
}

/// Bridges `NSVisualEffectView` into SwiftUI. SwiftUI's `Material` blurs
/// look milky; an `NSVisualEffectView` with behind-window blending gives
/// the panel the deeper, glassier translucency of Spotlight.
private struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // .active keeps the glass on even though the panel is a
        // non-activating panel that never becomes the main window.
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.layer?.cornerRadius = cornerRadius
    }
}
