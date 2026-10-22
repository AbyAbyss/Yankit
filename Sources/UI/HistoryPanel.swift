import AppKit
import SwiftUI

/// A borderless, non-activating panel. It can take keyboard focus for search
/// and navigation without activating the app, so the app you copied from
/// keeps its focus for the paste flow. See ARCHITECTURE.md §8.2.
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Creates, positions, shows, and dismisses the history panel.
final class HistoryPanelController: NSObject, NSWindowDelegate {
    /// Invoked with the chosen item and the app that was frontmost when the
    /// panel opened, so the paste flow can return focus there.
    var onSelect: ((ClipboardItem, NSRunningApplication?) -> Void)?
    /// Invoked when the panel's settings button is clicked.
    var onOpenSettings: (() -> Void)?

    private let repository: ClipboardRepository
    private let blobStore: BlobStore
    private let preferences: Preferences

    private var panel: HistoryPanel?
    private var viewModel: HistoryViewModel?
    private var keyMonitor: Any?
    private var modifierMonitor: Any?
    /// The frontmost app captured when the panel opened (paste target).
    private var targetApp: NSRunningApplication?

    init(
        repository: ClipboardRepository,
        blobStore: BlobStore,
        preferences: Preferences
    ) {
        self.repository = repository
        self.blobStore = blobStore
        self.preferences = preferences
        super.init()
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Record the paste target before the panel takes key focus.
        targetApp = NSWorkspace.shared.frontmostApplication

        let viewModel = HistoryViewModel(
            repository: repository, blobStore: blobStore, preferences: preferences
        )
        viewModel.reload()
        self.viewModel = viewModel

        let view = HistoryView(
            viewModel: viewModel,
            preferences: preferences,
            onSelectItem: { [weak self] item in self?.select(item) },
            onOpenSettings: { [weak self] in
                self?.hide()
                self?.onOpenSettings?()
            }
        )

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: view)

        positionPanel(panel)
        installKeyMonitor()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// Dismiss when the user clicks away from the panel.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Private

    private func select(_ item: ClipboardItem) {
        let app = targetApp
        hide()
        onSelect?(item, app)
    }

    private func makePanel() -> HistoryPanel {
        let panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: HistoryView.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = preferences.showPreviewPane
            ? HistoryView.wideSize : HistoryView.compactSize
        panel.setFrame(
            NSRect(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    /// Opens the "Move to Category" menu beside the selected row: the
    /// categories with their colors (choosing the checked one takes the item
    /// out of it, matching the row's context menu), then "New Category…".
    private func showMoveMenu() {
        guard let viewModel,
              let item = viewModel.selectedItem,
              let rowFrame = viewModel.selectedRowFrame,
              let view = panel?.contentView
        else { return }

        let menu = NSMenu(title: "Move to Category")
        if !viewModel.categories.isEmpty {
            menu.addItem(.sectionHeader(title: "Move To"))
        }
        for category in viewModel.categories {
            let menuItem = NSMenuItem(
                title: category.name,
                action: #selector(moveSelectedItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = category.id
            menuItem.state = item.categoryID == category.id ? .on : .off
            menuItem.image = NSImage(
                systemSymbolName: "circle.fill", accessibilityDescription: nil
            )?.withSymbolConfiguration(
                .init(pointSize: 8, weight: .regular)
                    .applying(.init(paletteColors: [NSColor(hex: category.color)]))
            )
            menu.addItem(menuItem)
        }
        if !viewModel.categories.isEmpty { menu.addItem(.separator()) }
        let newCategory = NSMenuItem(
            title: "New Category…",
            action: #selector(newCategoryForSelectedItem),
            keyEquivalent: ""
        )
        newCategory.target = self
        menu.addItem(newCategory)

        // The frame is in SwiftUI's top-left-origin window coordinates.
        let y = view.isFlipped
            ? rowFrame.maxY
            : view.bounds.height - rowFrame.maxY
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: rowFrame.minX + 50, y: y),
            in: view
        )
    }

    @objc private func moveSelectedItem(_ sender: NSMenuItem) {
        guard let viewModel,
              let item = viewModel.selectedItem,
              let categoryID = sender.representedObject as? String
        else { return }
        viewModel.setCategory(
            item.categoryID == categoryID ? nil : categoryID, for: item
        )
    }

    @objc private func newCategoryForSelectedItem() {
        guard let viewModel, let item = viewModel.selectedItem else { return }
        viewModel.overlay = .categoryEditor(nil, moveItemID: item.id)
    }

    /// Installs the key monitor, and a modifier monitor so holding ⌥
    /// reveals sensitive content in the preview pane.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.viewModel?.isOptionHeld = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let modifierMonitor {
            NSEvent.removeMonitor(modifierMonitor)
            self.modifierMonitor = nil
        }
    }

    /// Handles the panel's keys. Returns nil to consume the event, or the
    /// event itself to let it reach the search field. While a card is open
    /// every key goes to it, except Escape, which closes it.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel?.isVisible == true, let viewModel else { return event }
        if viewModel.isEditing {
            guard event.keyCode == 53 else { return event }
            viewModel.overlay = nil
            return nil
        }
        let command = event.modifierFlags.contains(.command)
        // ⌘1–⌘9 paste the Nth visible item.
        if command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
           (1...9).contains(digit) {
            let items = viewModel.filteredItems
            if items.indices.contains(digit - 1) {
                select(items[digit - 1])
            }
            return nil
        }
        switch event.keyCode {
        case 125:                       // down arrow
            viewModel.moveSelection(1)
        case 126:                       // up arrow
            viewModel.moveSelection(-1)
        case 48:                        // tab, shift-tab: switch chip
            viewModel.cycleFilter(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 53:                        // escape
            hide()
        case 36, 76:                    // return, keypad enter
            if let item = viewModel.selectedItem {
                select(item)
            }
        case 51 where command:          // ⌘⌫
            if let item = viewModel.selectedItem {
                viewModel.delete(item)
            }
        case 46 where command:          // ⌘M
            showMoveMenu()
        case 35 where command:          // ⌘P
            if let item = viewModel.selectedItem {
                viewModel.togglePin(item)
            }
        case 37 where command:          // ⌘L
            if let item = viewModel.selectedItem {
                viewModel.overlay = .label(itemID: item.id)
            }
        case 45 where command:          // ⌘N
            viewModel.overlay = .categoryEditor(nil, moveItemID: nil)
        case 40 where command:          // ⌘K
            viewModel.requestSearchFocus()
        default:
            return event
        }
        return nil
    }
}
