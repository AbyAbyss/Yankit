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

/// The accent color for selected chips, primary buttons, and highlights.
/// Its colors live in `Theme.swift`.
enum AppAccent: String, CaseIterable, Identifiable {
    case lime, blue, purple, orange, pink
    case system  // the macOS accent color from System Settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lime: "Lime"
        case .blue: "Blue"
        case .purple: "Purple"
        case .orange: "Orange"
        case .pink: "Pink"
        case .system: "System"
        }
    }
}

/// The history panel's background material.
enum PanelMaterial: String, CaseIterable, Identifiable {
    case clearGlass   // "Liquid Glass": see-through glass, macOS 26+
    case glass        // "Frosted Glass": regular Liquid Glass, macOS 26+
    case translucent  // the classic blurred material
    case solid        // no transparency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clearGlass: "Liquid Glass"
        case .glass: "Frosted Glass"
        case .translucent: "Translucent"
        case .solid: "Solid"
        }
    }

    var isGlass: Bool { self == .clearGlass || self == .glass }

    /// Whether this system can draw the material. Both glass styles need
    /// macOS 26.
    var isAvailable: Bool {
        if #available(macOS 26, *) { return true }
        return !isGlass
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
    @Published var accent: AppAccent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }
    /// When off, the Recent chip leaves pinned items out.
    @Published var showPinnedInRecent: Bool {
        didSet { defaults.set(showPinnedInRecent, forKey: Key.showPinnedInRecent) }
    }
    /// Beta: widens the panel to show a preview of the selected item.
    @Published var showPreviewPane: Bool {
        didSet { defaults.set(showPreviewPane, forKey: Key.showPreviewPane) }
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
            .flatMap { $0.isAvailable ? $0 : nil }
            ?? .translucent
        panelOpacity = (defaults.object(forKey: Key.panelOpacity) as? Double) ?? 0
        accent = defaults.string(forKey: Key.accent)
            .flatMap(AppAccent.init(rawValue:)) ?? .lime
        showPinnedInRecent =
            (defaults.object(forKey: Key.showPinnedInRecent) as? Bool) ?? true
        showPreviewPane =
            (defaults.object(forKey: Key.showPreviewPane) as? Bool) ?? false
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
        static let accent = "accent"
        static let showPinnedInRecent = "showPinnedInRecent"
        static let showPreviewPane = "showPreviewPane"
    }
}
