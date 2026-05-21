import Foundation

/// Runs storage housekeeping: a one-time integrity sweep at launch and a
/// recurring daily auto-expire sweep. See ARCHITECTURE.md §7.
final class MaintenanceService {
    private let repository: ClipboardRepository
    private let preferences: Preferences
    private var dailyTimer: Timer?

    init(repository: ClipboardRepository, preferences: Preferences) {
        self.repository = repository
        self.preferences = preferences
    }

    /// Cleans up orphaned data and expires old items, then schedules the
    /// recurring daily auto-expire sweep.
    func start() {
        do {
            try repository.runIntegritySweep()
        } catch {
            NSLog("ipaste: integrity sweep failed: \(error)")
        }
        runAutoExpire()

        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) {
            [weak self] _ in
            self?.runAutoExpire()
        }
        RunLoop.main.add(timer, forMode: .common)
        dailyTimer = timer
    }

    private func runAutoExpire() {
        do {
            try repository.expireItems(
                olderThanDays: preferences.autoExpireDays
            )
        } catch {
            NSLog("ipaste: auto-expire failed: \(error)")
        }
    }
}
