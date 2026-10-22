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

/// The history panel's background material.
enum PanelMaterial: String, CaseIterable, Identifiable {
    case glass        // Liquid Glass, macOS 26+
    case clearGlass   // the more transparent Liquid Glass variant, macOS 26+
    case translucent  // the classic blurred material

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .clearGlass: "Clear Glass"
        case .translucent: "Translucent"
        }
    }

    /// The materials this system can draw. Liquid Glass needs macOS 26.
    static var available: [PanelMaterial] {
        if #available(macOS 26, *) { return allCases }
        return [.translucent]
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
    /// When on, the history panel reopens on the last selected chip;
    /// when off, it always opens on Recent.
    @Published var rememberHistoryFilter: Bool {
        didSet { defaults.set(rememberHistoryFilter, forKey: Key.rememberHistoryFilter) }
    }
    /// The last selected chip, as `HistoryFilter.storageValue`.
    @Published var lastHistoryFilter: String {
        didSet { defaults.set(lastHistoryFilter, forKey: Key.lastHistoryFilter) }
    }
    @Published var panelMaterial: PanelMaterial {
        didSet { defaults.set(panelMaterial.rawValue, forKey: Key.panelMaterial) }
    }
    /// How strongly the panel is tinted with the window background color:
    /// 0 shows the material as-is, 1 is fully solid.
    @Published var panelOpacity: Double {
        didSet { defaults.set(panelOpacity, forKey: Key.panelOpacity) }
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
        rememberHistoryFilter =
            (defaults.object(forKey: Key.rememberHistoryFilter) as? Bool) ?? false
        lastHistoryFilter = defaults.string(forKey: Key.lastHistoryFilter) ?? ""
        panelMaterial = defaults.string(forKey: Key.panelMaterial)
            .flatMap(PanelMaterial.init(rawValue:))
            .flatMap { PanelMaterial.available.contains($0) ? $0 : nil }
            ?? .translucent
        panelOpacity = (defaults.object(forKey: Key.panelOpacity) as? Double) ?? 0
    }

    private enum Key {
        static let maxItems = "maxItems"
        static let ignoreConcealedItems = "ignoreConcealedItems"
        static let autoExpireDays = "autoExpireDays"
        static let maxCaptureMegabytes = "maxCaptureMegabytes"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let pausedUntil = "pausedUntil"
        static let appearance = "appearance"
        static let rememberHistoryFilter = "rememberHistoryFilter"
        static let lastHistoryFilter = "lastHistoryFilter"
        static let panelMaterial = "panelMaterial"
        static let panelOpacity = "panelOpacity"
    }
}
