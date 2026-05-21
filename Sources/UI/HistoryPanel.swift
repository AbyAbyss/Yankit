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

    private var panel: HistoryPanel?
    private var viewModel: HistoryViewModel?
    private var keyMonitor: Any?
    /// The frontmost app captured when the panel opened (paste target).
    private var targetApp: NSRunningApplication?

    private static let panelSize = NSSize(width: 420, height: 520)

    init(repository: ClipboardRepository, blobStore: BlobStore) {
        self.repository = repository
        self.blobStore = blobStore
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
            repository: repository, blobStore: blobStore
        )
        viewModel.reload()
        self.viewModel = viewModel

        let view = HistoryView(viewModel: viewModel) { [weak self] item in
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
    /// event itself to let it reach the search field.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel?.isVisible == true, let viewModel else { return event }
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
        default:
            return event
        }
    }
}
