import Foundation
import Combine

/// The app-wide color theme the user has chosen in Settings.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// User preferences, backed by `UserDefaults`. A single shared instance is
/// observed by the settings UI and read by the clipboard monitor.
/// See ARCHITECTURE.md §12.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }
    @Published var ignoreConcealedItems: Bool {
        didSet { defaults.set(ignoreConcealedItems, forKey: Key.ignoreConcealedItems) }
    }
    @Published var autoExpireDays: Int {
        didSet { defaults.set(autoExpireDays, forKey: Key.autoExpireDays) }
    }
    @Published var maxCaptureMegabytes: Int {
        didSet { defaults.set(maxCaptureMegabytes, forKey: Key.maxCaptureMegabytes) }
    }
    @Published var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }
    @Published var pausedUntil: Date? {
        didSet {
            if let pausedUntil {
                defaults.set(pausedUntil, forKey: Key.pausedUntil)
            } else {
                defaults.removeObject(forKey: Key.pausedUntil)
            }
        }
    }
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// The capture size limit in bytes (the stored value is in megabytes).
    var maxCaptureBytes: Int { maxCaptureMegabytes * 1024 * 1024 }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // didSet does not fire during init, so these loads do not write back.
        maxItems = (defaults.object(forKey: Key.maxItems) as? Int) ?? 30
        ignoreConcealedItems =
            (defaults.object(forKey: Key.ignoreConcealedItems) as? Bool) ?? true
        autoExpireDays = (defaults.object(forKey: Key.autoExpireDays) as? Int) ?? 0
        maxCaptureMegabytes =
            (defaults.object(forKey: Key.maxCaptureMegabytes) as? Int) ?? 10
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []
        pausedUntil = defaults.object(forKey: Key.pausedUntil) as? Date
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    private enum Key {
        static let maxItems = "maxItems"
        static let ignoreConcealedItems = "ignoreConcealedItems"
        static let autoExpireDays = "autoExpireDays"
        static let maxCaptureMegabytes = "maxCaptureMegabytes"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let pausedUntil = "pausedUntil"
        static let appearance = "appearance"
    }
}
