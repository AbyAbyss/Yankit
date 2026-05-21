import AppKit
import ApplicationServices
import CoreGraphics

/// Writes a chosen history item back to the pasteboard and pastes it into the
/// app the user came from. See ARCHITECTURE.md §9.
final class PasteService {
    private let blobStore: BlobStore
    private let monitor: ClipboardMonitor
    private var didPromptForAccessibility = false

    init(blobStore: BlobStore, monitor: ClipboardMonitor) {
        self.blobStore = blobStore
        self.monitor = monitor
    }

    /// Places `item` on the pasteboard and, if permitted, pastes it into
    /// `targetApp` by synthesizing ⌘V. Without Accessibility permission the
    /// item is left on the pasteboard for the user to paste manually.
    func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) {
        writeToPasteboard(item)
        // Tell the monitor to ignore the pasteboard change we just caused,
        // so the app does not re-capture its own paste (ARCHITECTURE.md §6).
        monitor.ignoreChangeCount(NSPasteboard.general.changeCount)

        guard AXIsProcessTrusted() else {
            promptForAccessibilityOnce()
            return
        }
        _ = targetApp?.activate()
        // Let the target app regain key focus after the panel closed, then
        // synthesize the paste keystroke.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Self.postPasteKeystroke()
        }
    }

    // MARK: - Pasteboard

    private func writeToPasteboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let path = item.blobPath,
               let data = try? blobStore.data(forRelativePath: path) {
                pasteboard.setData(data, forType: .png)
            }
        case .file:
            if let urlString = item.fileURL,
               let url = URL(string: urlString) {
                pasteboard.writeObjects([url as NSURL])
            }
        }
    }

    // MARK: - Keystroke

    private static func postPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9        // ANSI 'v'
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKeyCode, keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: vKeyCode, keyDown: false
            )
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Accessibility

    private func promptForAccessibilityOnce() {
        guard !didPromptForAccessibility else { return }
        didPromptForAccessibility = true

        let alert = NSAlert()
        alert.messageText = "Enable Accessibility for one-touch paste"
        alert.informativeText = """
            Your selection is on the clipboard — press ⌘V to paste it.

            To let ipaste paste automatically, allow it under System \
            Settings → Privacy & Security → Accessibility.
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = "x-apple.systempreferences:"
                + "com.apple.preference.security?Privacy_Accessibility"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
