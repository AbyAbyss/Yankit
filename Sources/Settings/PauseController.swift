import AppKit

/// Manages the "pause capture" state: the menu-bar menu items, the dimmed
/// status icon, and auto-resume when a timed pause expires.
/// See ARCHITECTURE.md §8.1.
final class PauseController: NSObject {
    /// Called with the new paused state so the menu-bar icon can dim/undim.
    var onPauseStateChanged: ((Bool) -> Void)?

    private let preferences: Preferences
    private var expiryTimer: Timer?

    init(preferences: Preferences) {
        self.preferences = preferences
        super.init()
        restoreState()
    }

    var isPaused: Bool {
        guard let until = preferences.pausedUntil else { return false }
        return until > Date()
    }

    /// Menu items for the menu-bar menu: a "Resume Capture" item while
    /// paused, or a "Pause Capture" item with timed options otherwise.
    func makeMenuItems() -> [NSMenuItem] {
        if isPaused {
            let resume = NSMenuItem(
                title: "Resume Capture",
                action: #selector(resume),
                keyEquivalent: ""
            )
            resume.target = self
            return [resume]
        }

        let pause = NSMenuItem(
            title: "Pause Capture", action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        submenu.addItem(
            pauseItem("For 1 Hour", until: Date(timeIntervalSinceNow: 3600))
        )
        submenu.addItem(
            pauseItem("Until Tomorrow", until: Self.tomorrowMorning())
        )
        submenu.addItem(
            pauseItem("Until I Resume", until: .distantFuture)
        )
        pause.submenu = submenu
        return [pause]
    }

    // MARK: - Actions

    private func pauseItem(_ title: String, until date: Date) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(pauseSelected(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = date
        return item
    }

    @objc private func pauseSelected(_ sender: NSMenuItem) {
        guard let date = sender.representedObject as? Date else { return }
        preferences.pausedUntil = date
        scheduleExpiry(at: date)
        onPauseStateChanged?(true)
    }

    @objc private func resume() {
        preferences.pausedUntil = nil
        cancelExpiry()
        onPauseStateChanged?(false)
    }

    // MARK: - Expiry

    /// Re-arms or clears a pause that was persisted across a relaunch.
    private func restoreState() {
        guard let until = preferences.pausedUntil else { return }
        if until > Date() {
            scheduleExpiry(at: until)
        } else {
            preferences.pausedUntil = nil
        }
    }

    private func scheduleExpiry(at date: Date) {
        cancelExpiry()
        let interval = date.timeIntervalSinceNow
        // An "Until I Resume" pause uses the distant future — no timer.
        guard interval > 0, interval < 60 * 60 * 24 * 30 else { return }
        expiryTimer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: false
        ) { [weak self] _ in
            self?.handleExpiry()
        }
    }

    private func cancelExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    private func handleExpiry() {
        preferences.pausedUntil = nil
        onPauseStateChanged?(false)
    }

    private static func tomorrowMorning() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(
            byAdding: .day, value: 1, to: Date()
        ) ?? Date()
        return calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}
