import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The history panel content: a search field and a chip bar over a
/// scrolling, keyboard-navigable list. List navigation keys are handled by
/// `HistoryPanelController`; this view handles search, chips, and display.
/// See ARCHITECTURE.md §8.2.
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    @ObservedObject var preferences: Preferences
    var onSelectItem: (ClipboardItem) -> Void

    @FocusState private var searchFocused: Bool
    /// The chip a dragged row is hovering over.
    @State private var dropTarget: HistoryFilter?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            chipBar
            content
        }
        .frame(width: 420, height: 520)
        .background(PanelBackground(
            material: preferences.panelMaterial,
            opacity: preferences.panelOpacity,
            cornerRadius: 12
        ))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
        }
        // Hand focus back to search once an inline edit ends.
        .onChange(of: viewModel.isEditing) { _, isEditing in
            if !isEditing { searchFocused = true }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Chips

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Recent", filter: .recent)
                chip("Pinned", systemImage: "pin.fill", filter: .pinned)
                ForEach(viewModel.categories) { category in
                    if viewModel.renamingCategoryID == category.id {
                        chipField(initialText: category.name) {
                            viewModel.commitRename(category, to: $0)
                        }
                    } else {
                        chip(
                            category.name,
                            systemImage: category.isSensitive ? "lock.fill" : nil,
                            filter: .category(category.id)
                        )
                        .contextMenu { chipMenu(for: category) }
                    }
                }
                if viewModel.isAddingCategory {
                    chipField(initialText: "") {
                        viewModel.commitNewCategory(named: $0)
                    }
                } else {
                    Button {
                        viewModel.isAddingCategory = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 22)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("New Category")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    /// A chip that selects `filter`. Recent and category chips also accept
    /// dropped rows (see `HistoryViewModel.moveDroppedItem`).
    private func chip(
        _ title: String,
        systemImage: String? = nil,
        filter: HistoryFilter
    ) -> some View {
        let isSelected = viewModel.filter == filter
        let acceptsDrop = filter != .pinned
        return Button {
            viewModel.filter = filter
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9))
                }
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background(
                Capsule().fill(isSelected
                               ? Color.accentColor.opacity(0.22)
                               : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(
                    Color.accentColor,
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

    private func chipField(
        initialText: String,
        onCommit: @escaping (String) -> Void
    ) -> some View {
        InlineTextField(
            initialText: initialText,
            placeholder: "Category name",
            onCommit: onCommit
        )
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(width: 130, height: 22)
        .background(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
    }

    @ViewBuilder
    private func chipMenu(for category: ClipboardCategory) -> some View {
        Button("Rename") { viewModel.renamingCategoryID = category.id }
        Toggle("Sensitive", isOn: Binding(
            get: { category.isSensitive },
            set: { _ in viewModel.toggleSensitive(category) }
        ))
        Divider()
        Button("Delete Category") { viewModel.deleteCategory(category) }
    }

    // MARK: - List

    @ViewBuilder
    private var content: some View {
        let items = viewModel.filteredItems
        if items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HistoryRowView(
                                item: item,
                                thumbnail: viewModel.thumbnails[item.id],
                                isSelected: index == viewModel.selectedIndex,
                                isSensitive: viewModel.isSensitive(item),
                                isEditingLabel: viewModel.editingLabelItemID == item.id,
                                onTogglePin: { viewModel.togglePin(item) },
                                onDelete: { viewModel.delete(item) },
                                onCommitLabel: { viewModel.commitLabel($0, for: item) }
                            )
                            .onTapGesture { onSelectItem(item) }
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
                    }
                    .padding(6)
                }
                .onPreferenceChange(SelectedRowFrameKey.self) { frame in
                    viewModel.selectedRowFrame = frame
                }
                .onChange(of: viewModel.selectedIndex) { _, _ in
                    guard let id = viewModel.selectedItem?.id else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(for item: ClipboardItem) -> some View {
        Button(item.pinned ? "Unpin" : "Pin") { viewModel.togglePin(item) }
        Button(item.label == nil ? "Add Label" : "Edit Label") {
            viewModel.editingLabelItemID = item.id
        }
        Menu("Move to Category") {
            ForEach(viewModel.categories) { category in
                Toggle(category.name, isOn: Binding(
                    get: { item.categoryID == category.id },
                    set: { viewModel.setCategory($0 ? category.id : nil, for: item) }
                ))
            }
        }
        .disabled(viewModel.categories.isEmpty)
        Divider()
        Button("Remove from History") { viewModel.delete(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: viewModel.searchText.isEmpty
                  ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        guard viewModel.searchText.isEmpty else { return "No matches" }
        switch viewModel.filter {
        case .recent: return "No clipboard history yet"
        case .pinned: return "No pinned items"
        case .category: return "Right-click an item to move it here"
        }
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

/// A plain text field for inline edits inside the panel. Edits stay
/// inline because a popover or alert would take key focus from the
/// non-activating panel, which dismisses it. Return commits; Escape is
/// handled by `HistoryPanelController`.
struct InlineTextField: View {
    let placeholder: String
    var onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var focused: Bool

    init(
        initialText: String,
        placeholder: String,
        onCommit: @escaping (String) -> Void
    ) {
        self.placeholder = placeholder
        self.onCommit = onCommit
        _text = State(initialValue: initialText)
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { onCommit(text) }
            .onAppear {
                DispatchQueue.main.async { focused = true }
            }
    }
}

/// The panel background: the chosen material, with the window background
/// color layered on top at the user's opacity (0 = material only,
/// 1 = solid).
private struct PanelBackground: View {
    var material: PanelMaterial
    var opacity: Double
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            effect
            Color(nsColor: .windowBackgroundColor).opacity(opacity)
        }
    }

    @ViewBuilder
    private var effect: some View {
        if #available(macOS 26, *), material != .translucent {
            GlassEffectBackground(
                style: material == .clearGlass ? .clear : .regular,
                cornerRadius: cornerRadius
            )
        } else {
            VisualEffectBackground(material: .hudWindow, cornerRadius: cornerRadius)
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
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
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
        view.layer?.cornerRadius = cornerRadius
    }
}
