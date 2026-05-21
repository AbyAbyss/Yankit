import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts

/// The Settings window content: a top tab bar over the selected tab's view.
/// A hand-rolled tab bar is used instead of `TabView` so all tabs stay
/// visible in the window. See ARCHITECTURE.md §8.3.
struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    let repository: ClipboardRepository

    @State private var selection: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 440)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16))
                        Text(tab.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selection == tab
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.clear)
                    )
                    .foregroundStyle(
                        selection == tab ? Color.accentColor : Color.primary
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            GeneralSettingsTab(preferences: preferences, repository: repository)
        case .excludedApps:
            ExcludedAppsTab(preferences: preferences)
        case .privacy:
            PrivacySettingsTab(preferences: preferences)
        case .storage:
            StorageSettingsTab(repository: repository)
        case .about:
            AboutTab()
        }
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general, excludedApps, privacy, storage, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .excludedApps: "Excluded Apps"
        case .privacy: "Privacy"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .excludedApps: "nosign"
        case .privacy: "hand.raised"
        case .storage: "internaldrive"
        case .about: "info.circle"
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @ObservedObject var preferences: Preferences
    let repository: ClipboardRepository

    var body: some View {
        Form {
            Toggle("Launch Yankit at login", isOn: Binding(
                get: { LoginItemManager.isEnabled },
                set: { LoginItemManager.setEnabled($0) }
            ))
            Stepper(
                "History limit: \(preferences.maxItems) items",
                value: $preferences.maxItems,
                in: 1...100
            )
            .onChange(of: preferences.maxItems) { _, newValue in
                try? repository.enforceLimit(maxItems: newValue)
            }
            LabeledContent("Open history shortcut") {
                KeyboardShortcuts.Recorder(for: .toggleHistory)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Excluded Apps

private struct ExcludedAppsTab: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copies made in these apps are not saved. "
                 + "By default Yankit captures everything.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            List {
                if preferences.excludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundStyle(.tertiary)
                }
                ForEach(preferences.excludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Image(nsImage: appIcon(for: bundleID))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(appName(for: bundleID))
                        Spacer()
                        Button {
                            preferences.excludedBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Button("Add App…") { addApp() }
        }
        .padding()
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              !preferences.excludedBundleIDs.contains(bundleID)
        else { return }
        preferences.excludedBundleIDs.append(bundleID)
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func appName(for bundleID: String) -> String {
        guard let url = appURL(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func appIcon(for bundleID: String) -> NSImage {
        guard let url = appURL(for: bundleID) else {
            return NSImage(
                systemSymbolName: "app.dashed", accessibilityDescription: nil
            ) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

// MARK: - Privacy

private struct PrivacySettingsTab: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Toggle(
                "Ignore passwords and transient clipboard content",
                isOn: $preferences.ignoreConcealedItems
            )
            Stepper(autoExpireLabel, value: $preferences.autoExpireDays, in: 0...365)
            Stepper(
                "Skip items larger than \(preferences.maxCaptureMegabytes) MB",
                value: $preferences.maxCaptureMegabytes,
                in: 1...500
            )
        }
        .formStyle(.grouped)
    }

    private var autoExpireLabel: String {
        preferences.autoExpireDays == 0
            ? "Auto-delete old items: Off"
            : "Auto-delete items older than \(preferences.autoExpireDays) days"
    }
}

// MARK: - Storage

private struct StorageSettingsTab: View {
    let repository: ClipboardRepository
    @State private var itemCount = 0
    @State private var diskUsage = "—"

    var body: some View {
        Form {
            LabeledContent("Items stored", value: "\(itemCount)")
            LabeledContent("Disk usage", value: diskUsage)
            Button("Clear History…", role: .destructive) { clearHistory() }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private func refresh() {
        itemCount = (try? repository.count()) ?? 0
        diskUsage = Self.formattedDiskUsage()
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText =
            "This permanently deletes every saved item, including pinned ones."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            try? repository.deleteAll()
            refresh()
        }
    }

    private static func formattedDiskUsage() -> String {
        guard let directory = try? AppDatabase.supportDirectory() else {
            return "—"
        }
        let bytes = directorySize(directory)
        return ByteCountFormatter.string(
            fromByteCount: Int64(bytes), countStyle: .file
        )
    }

    private static func directorySize(_ url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += values?.fileSize ?? 0
        }
        return total
    }
}

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Yankit")
                .font(.system(size: 20, weight: .semibold))
            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)
            Text("A free, open-source clipboard manager for macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("MIT Licensed")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.0"
    }
}
