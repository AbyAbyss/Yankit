import AppKit
import SwiftUI

/// The history panel content: a search field over a scrolling,
/// keyboard-navigable list. List navigation keys are handled by
/// `HistoryPanelController`; this view handles search and display.
/// See ARCHITECTURE.md §8.2.
struct HistoryView: View {
    @ObservedObject var viewModel: HistoryViewModel
    var onSelectItem: (ClipboardItem) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        .frame(width: 420, height: 520)
        .background(VisualEffectBackground(material: .hudWindow, cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
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
                                onTogglePin: { viewModel.togglePin(item) },
                                onDelete: { viewModel.delete(item) }
                            )
                            .onTapGesture { onSelectItem(item) }
                        }
                    }
                    .padding(6)
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

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: viewModel.searchText.isEmpty
                  ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(viewModel.searchText.isEmpty
                 ? "No clipboard history yet"
                 : "No matches")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
