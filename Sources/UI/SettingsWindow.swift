import AppKit
import SwiftUI

/// Manages the Settings window. ipaste is a menu-bar agent, so this is a
/// normal window created and shown on demand rather than a SwiftUI `Settings`
/// scene — which keeps dependency injection straightforward.
final class SettingsWindowController {
    private let preferences: Preferences
    private let repository: ClipboardRepository
    private var window: NSWindow?

    init(preferences: Preferences, repository: ClipboardRepository) {
        self.preferences = preferences
        self.repository = repository
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = SettingsView(preferences: preferences, repository: repository)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ipaste Settings"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        return window
    }
}
