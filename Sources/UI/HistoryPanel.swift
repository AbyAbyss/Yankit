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

    private let repository: ClipboardRepository
    private let blobStore: BlobStore
    private let preferences: Preferences

    private var panel: HistoryPanel?
    private var viewModel: HistoryViewModel?
    private var keyMonitor: Any?
    /// The frontmost app captured when the panel opened (paste target).
    private var targetApp: NSRunningApplication?

    private static let panelSize = NSSize(width: 420, height: 520)

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
            viewModel: viewModel, preferences: preferences
        ) { [weak self] item in
            self?.select(item)
        }

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
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
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
        let size = Self.panelSize
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

    /// Opens the "Move to Category" menu beside the selected row. Choosing
    /// the checked category takes the item out of it, matching the row's
    /// context menu.
    private func showMoveMenu() {
        guard let viewModel,
              let item = viewModel.selectedItem,
              let rowFrame = viewModel.selectedRowFrame,
              let view = panel?.contentView,
              !viewModel.categories.isEmpty
        else { return }

        let menu = NSMenu(title: "Move to Category")
        for category in viewModel.categories {
            let menuItem = NSMenuItem(
                title: category.name,
                action: #selector(moveSelectedItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = category.id
            menuItem.state = item.categoryID == category.id ? .on : .off
            menu.addItem(menuItem)
        }
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

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Handles list-navigation keys. Returns nil to consume the event, or the
    /// event itself to let it reach the search field. During an inline edit
    /// every key goes to the edit field, except Escape, which cancels it.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel?.isVisible == true, let viewModel else { return event }
        if viewModel.isEditing {
            guard event.keyCode == 53 else { return event }
            viewModel.cancelEditing()
            return nil
        }
        switch event.keyCode {
        case 125:                       // down arrow
            viewModel.moveSelection(1)
            return nil
        case 126:                       // up arrow
            viewModel.moveSelection(-1)
            return nil
        case 53:                        // escape
            hide()
            return nil
        case 36, 76:                    // return, keypad enter
            if let item = viewModel.selectedItem {
                select(item)
            }
            return nil
        case 51 where event.modifierFlags.contains(.command):  // ⌘⌫
            if let item = viewModel.selectedItem {
                viewModel.delete(item)
            }
            return nil
        case 46 where event.modifierFlags.contains(.command):  // ⌘M
            showMoveMenu()
            return nil
        default:
            return event
        }
    }
}
