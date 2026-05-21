import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global shortcut that opens the history panel. Defaults to ⌘⇧V;
    /// the user can rebind it from Settings (recorder UI lands in Phase 5).
    static let toggleHistory = Self(
        "toggleHistory",
        default: .init(.v, modifiers: [.command, .shift])
    )
}

/// Registers the global hotkey that opens the history panel.
/// See ARCHITECTURE.md §9.
final class HotkeyManager {
    /// Invoked when the user presses the shortcut.
    var onTrigger: (() -> Void)?

    init() {
        KeyboardShortcuts.onKeyDown(for: .toggleHistory) { [weak self] in
            self?.onTrigger?()
        }
    }
}
