import AppKit

/// The menu-bar (status bar) presence for Yankit.
///
/// Left-click opens the history panel; right-click (or control-click) opens
/// the menu. See ARCHITECTURE.md §8.1.
final class MenuBarController: NSObject {
    /// Invoked when the user asks to open the history panel.
    var onOpenHistory: (() -> Void)?
    /// Invoked when the user asks to open the Settings window.
    var onOpenSettings: (() -> Void)?
    /// Supplies the pause-related menu items, rebuilt each time the menu
    /// opens so they reflect the current pause state.
    var pauseMenuItemsProvider: (() -> [NSMenuItem])?

    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        super.init()
        configureButton()
    }

    /// Dims the menu-bar icon while capture is paused.
    func setPaused(_ paused: Bool) {
        statusItem.button?.appearsDisabled = paused
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Yankit"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(
            title: "Open History",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        for item in pauseMenuItemsProvider?() ?? [] {
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit Yankit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isSecondaryClick {
            showMenu()
        } else {
            onOpenHistory?()
        }
    }

    @objc private func openHistory() {
        onOpenHistory?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        buildMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.maxY + 4),
            in: button
        )
    }
}
    