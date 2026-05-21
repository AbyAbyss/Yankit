import AppKit
import Combine

/// Owns the app's long-lived objects and wires them together at launch.
///
/// With `LSUIElement` set in Info.plist the process runs as a menu-bar
/// agent: no Dock icon, no main window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var preferences: Preferences?
    private var repository: ClipboardRepository?
    private var clipboardMonitor: ClipboardMonitor?
    private var pasteService: PasteService?
    private var menuBarController: MenuBarController?
    private var historyPanelController: HistoryPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var pauseController: PauseController?
    private var hotkeyManager: HotkeyManager?
    private var maintenanceService: MaintenanceService?
    private var appearanceObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        startServices()
    }

    private func startServices() {
        do {
            let preferences = Preferences.shared
            // Apply the saved theme now, and reapply whenever it changes.
            // A @Published publisher emits its current value on subscribe,
            // so this also covers the initial launch state.
            appearanceObserver = preferences.$appearance.sink { [weak self] in
                self?.applyAppearance($0)
            }
            let queue = try AppDatabase.openHistoryDatabase()
            let blobStore = try BlobStore(
                directory: AppDatabase.blobsDirectory()
            )
            let repository = ClipboardRepository(
                queue: queue, blobStore: blobStore
            )

            let maintenance = MaintenanceService(
                repository: repository, preferences: preferences
            )
            maintenance.start()

            let monitor = ClipboardMonitor(
                repository: repository,
                blobStore: blobStore,
                preferences: preferences
            )
            monitor.start()

            let pasteService = PasteService(
                blobStore: blobStore, monitor: monitor
            )

            let panelController = HistoryPanelController(
                repository: repository, blobStore: blobStore
            )
            panelController.onSelect = { [weak pasteService] item, targetApp in
                pasteService?.paste(item, into: targetApp)
            }

            let settingsController = SettingsWindowController(
                preferences: preferences, repository: repository
            )

            let menuBar = MenuBarController()
            menuBar.onOpenHistory = { [weak panelController] in
                panelController?.toggle()
            }
            menuBar.onOpenSettings = { [weak settingsController] in
                settingsController?.show()
            }

            let pauseController = PauseController(preferences: preferences)
            pauseController.onPauseStateChanged = { [weak menuBar] paused in
                menuBar?.setPaused(paused)
            }
            menuBar.pauseMenuItemsProvider = { [weak pauseController] in
                pauseController?.makeMenuItems() ?? []
            }
            menuBar.setPaused(pauseController.isPaused)

            let hotkeyManager = HotkeyManager()
            hotkeyManager.onTrigger = { [weak panelController] in
                panelController?.toggle()
            }

            self.preferences = preferences
            self.repository = repository
            self.clipboardMonitor = monitor
            self.pasteService = pasteService
            self.historyPanelController = panelController
            self.settingsWindowController = settingsController
            self.menuBarController = menuBar
            self.pauseController = pauseController
            self.hotkeyManager = hotkeyManager
            self.maintenanceService = maintenance
        } catch {
            NSLog("Yankit: failed to start: \(error)")
        }
    }

    /// Forces the app's appearance, or follows the system when `.system`.
    /// Setting `NSApp.appearance` cascades to every window — the history
    /// panel, the settings window, and the menu-bar menu.
    private func applyAppearance(_ appearance: AppAppearance) {
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
