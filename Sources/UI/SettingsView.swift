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
        .frame(width: 700, height: 600)
        .tint(preferences.accent.tint)
        .environment(\.accent, preferences.accent)
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
                                  ? Color.primary.opacity(0.1)
                                  : Color.clear)
                    )
                    .foregroundStyle(
                        selection == tab ? preferences.accent.tint : Color.primary
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
        case .appearance:
            AppearanceSettingsTab(preferences: preferences)
        case .categories:
            CategoriesSettingsTab(repository: repository)
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
    case general, appearance, categories, excludedApps, privacy, storage, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .categories: "Categories"
        case .excludedApps: "Excluded Apps"
        case .privacy: "Privacy"
        case .storage: "Storage"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .categories: "tag"
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
    @Environment(\.accent) private var accent

    var body: some View {
        Form {
            Section("When the panel opens") {
                Toggle(isOn: $preferences.rememberHistoryFilter) {
                    Text("Remember last view")
                    Text(preferences.rememberHistoryFilter
                         ? "Yankit reopens on whichever tab you used last."
                         : "Off by default. Yankit always opens on Recent, so the latest copy is the first row.")
                }
                HStack(spacing: 12) {
                    viewCard(
                        title: "OFF · DEFAULT", selectedChip: "Recent",
                        text: "Every open lands on your newest copy. Press ⇥ to reach Pinned.",
                        isCurrent: !preferences.rememberHistoryFilter
                    )
                    viewCard(
                        title: "ON", selectedChip: "Pinned",
                        text: "Reopens on the tab you closed it from, Pinned or any category.",
                        isCurrent: preferences.rememberHistoryFilter
                    )
                }
            }
            Section("Pinned items") {
                Toggle(isOn: $preferences.showPinnedInRecent) {
                    Text("Also show pinned items in Recent")
                    Text("They stay in time order with a pin badge, never stacked at the top.")
                }
            }
            Section("Preview pane") {
                Toggle(isOn: $preferences.showPreviewPane) {
                    HStack(spacing: 6) {
                        Text("Show preview pane")
                        Text("BETA")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(accent.onFill)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(accent.fill))
                    }
                    Text("Widens the panel with a large preview of the selected item, its details and actions.")
                }
            }
            Section("General") {
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
                LabeledContent("Open Yankit") {
                    KeyboardShortcuts.Recorder(for: .toggleHistory)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// One of the two cards that show what "Remember last view" does.
    private func viewCard(
        title: String,
        selectedChip: String,
        text: String,
        isCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(["Recent", "Pinned"], id: \.self) { chip in
                    let isSelected = chip == selectedChip
                    Text(chip)
                        .font(.system(size: 10.5, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? accent.onFill : Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(
                            isSelected ? accent.fill : Color.primary.opacity(0.08)
                        ))
                }
            }
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(
                isCurrent ? accent.tint : Color.primary.opacity(0.06),
                lineWidth: isCurrent ? 1.5 : 1
            )
        )
    }
}

// MARK: - Appearance

private struct AppearanceSettingsTab: View {
    @ObservedObject var preferences: Preferences
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group("Theme") {
                        Picker("Theme", selection: $preferences.appearance) {
                            ForEach(AppAppearance.allCases) { appearance in
                                Text(appearance.title).tag(appearance)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    group("Accent") { accentPicker }
                    group("Material") {
                        VStack(spacing: 6) {
                            ForEach(PanelMaterial.allCases) { materialCard($0) }
                        }
                    }
                    group("Opacity") { opacity }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("If Reduce Transparency is on in System Settings, macOS draws the panel solid automatically.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(groupBackground)
                }
            }
            .frame(width: 340)
            group("Preview") { AppearancePreview(preferences: preferences) }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }

    private var groupBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    /// One chip per accent, wrapped over two rows.
    private var accentPicker: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(AppAccent.allCases) { choice in
                let isSelected = preferences.accent == choice
                Button {
                    preferences.accent = choice
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(choice.fill)
                            .frame(width: 12, height: 12)
                        Text(choice.title)
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .background(
                        Capsule().fill(Color.primary.opacity(isSelected ? 0.1 : 0.045))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isSelected ? choice.tint : Color.primary.opacity(0.07),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func materialCard(_ material: PanelMaterial) -> some View {
        let isSelected = preferences.panelMaterial == material
        return Button {
            preferences.panelMaterial = material
        } label: {
            HStack(spacing: 12) {
                PanelBackground(
                    material: material,
                    opacity: 0,
                    cornerRadius: 10,
                    blendingMode: .withinWindow
                )
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(material.title)
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(material.isGlass ? "macOS 26+" : "All versions")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                    }
                    Text(description(of: material))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Circle()
                    .strokeBorder(
                        isSelected ? accent.tint : Color.secondary.opacity(0.5),
                        lineWidth: isSelected ? 5 : 1.5
                    )
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    isSelected ? accent.tint : Color.primary.opacity(0.07),
                    lineWidth: isSelected ? 1.5 : 1
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!material.isAvailable)
        .opacity(material.isAvailable ? 1 : 0.55)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func description(of material: PanelMaterial) -> String {
        guard material.isAvailable else {
            return "Needs macOS 26. This Mac uses Translucent instead."
        }
        switch material {
        case .clearGlass:
            return "Clear, refractive glass that picks up color from behind."
        case .glass:
            return "Liquid Glass with a frosted finish, easier to read over busy backgrounds."
        case .translucent:
            return "Classic macOS vibrancy with a frosted blur."
        case .solid:
            return "No transparency. Best for screen sharing."
        }
    }

    private var opacity: some View {
        let isSolid = preferences.panelMaterial == .solid
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Slider(value: $preferences.panelOpacity, in: 0...1) {
                    Text("Panel opacity")
                } minimumValueLabel: {
                    Text("Clear").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("Opaque").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .labelsHidden()
                Text("\(Int((preferences.panelOpacity * 100).rounded()))%")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 38, alignment: .trailing)
            }
            Text("Sets the tint over the system material. Blur strength comes from macOS and can't be changed.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(groupBackground)
        .disabled(isSolid)
        .opacity(isSolid ? 0.45 : 1)
    }
}

/// A small mock of the panel over a colorful backdrop, drawn with the
/// selected material and opacity so changes show up immediately.
private struct AppearancePreview: View {
    @ObservedObject var preferences: Preferences
    @Environment(\.accent) private var accent

    private static let rows: [(text: String, style: ItemStyle)] = [
        ("github.com/AbyAbyss/Yankit", .url),
        ("#FF6B4A", .color(hex: "#FF6B4A")),
        ("git push origin main", .terminal),
        ("sk-exa••••••••••", .secret),
    ]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            mockPanel
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var label: String {
        let material = preferences.panelMaterial
        guard material != .solid else { return material.title }
        return "\(material.title) · \(Int((preferences.panelOpacity * 100).rounded()))%"
    }

    private var backdrop: some View {
        ZStack {
            Color(hex: "#14101F")
            RadialGradient(colors: [Color(hex: "#6A45D8"), .clear],
                           center: UnitPoint(x: 0.2, y: 0.2), startRadius: 0, endRadius: 170)
            RadialGradient(colors: [Color(hex: "#13A3B8"), .clear],
                           center: UnitPoint(x: 0.85, y: 0.3), startRadius: 0, endRadius: 150)
            RadialGradient(colors: [Color(hex: "#E0477F"), .clear],
                           center: UnitPoint(x: 0.6, y: 0.95), startRadius: 0, endRadius: 170)
            Circle()
                .fill(Color(hex: "#FFD166"))
                .frame(width: 70, height: 70)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 30)
                .padding(.top, 40)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#FF5D8F"))
                .frame(width: 90, height: 40)
                .rotationEffect(.degrees(-12))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 20)
                .padding(.top, 120)
        }
    }

    private var mockPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Search clipboard")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)))
            HStack(spacing: 4) {
                ForEach(["Recent", "Pinned", "Work"], id: \.self) { chip in
                    let isSelected = chip == "Recent"
                    Text(chip)
                        .font(.system(size: 9.5, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? accent.onFill : Color.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(
                            isSelected ? accent.fill : Color.primary.opacity(0.1)
                        ))
                }
            }
            ForEach(Self.rows.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    ItemTile(style: Self.rows[index].style, thumbnail: nil)
                        .scaleEffect(0.5)
                        .frame(width: 22, height: 22)
                    Text(Self.rows[index].text)
                        .font(.system(
                            size: 10.5, weight: .semibold,
                            design: index == 0 ? .default : .monospaced
                        ))
                        .lineLimit(1)
                }
                .padding(5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(
                    Color.primary.opacity(index == 0 ? 0.1 : 0)
                ))
            }
        }
        .padding(10)
        .background(PanelBackground(
            material: preferences.panelMaterial,
            opacity: preferences.panelOpacity,
            cornerRadius: 16,
            blendingMode: .withinWindow
        ))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.45), radius: 20, y: 18)
    }
}

// MARK: - Categories

private struct CategoriesSettingsTab: View {
    let repository: ClipboardRepository
    @Environment(\.accent) private var accent

    @State private var categories: [ClipboardCategory] = []
    @State private var counts: [String: Int] = [:]
    @State private var pinnedCount = 0
    @State private var editor: EditorTarget?

    /// The category the editor sheet is open for; `nil` creates one.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let category: ClipboardCategory?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chips in the panel")
                        .font(.system(size: 15, weight: .bold))
                    Text("Drag to reorder. The order here is the order of chips and of ⇥.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editor = EditorTarget(category: nil)
                } label: {
                    Label("New category", systemImage: "plus")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(accent.onFill)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 9).fill(accent.fill))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 0) {
                columnHeader("BUILT IN", trailing: "ALWAYS FIRST")
                builtInRow(
                    icon: Circle().fill(Color.secondary).frame(width: 10, height: 10),
                    name: "Recent",
                    detail: Text("Opens here by default")
                )
                builtInRow(
                    icon: Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(accent.tint),
                    name: "Pinned",
                    detail: Text("\(pinnedCount) items").font(.system(size: 12, design: .monospaced))
                )
            }
            .background(groupBackground)

            VStack(spacing: 0) {
                columnHeader("YOUR CATEGORIES", trailing: "ITEMS")
                if categories.isEmpty {
                    Text("No categories yet")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    List {
                        ForEach(categories) { category in
                            categoryRow(category)
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(groupBackground)

            Text("Deleting a category keeps its items in Recent. Items in a sensitive category stay redacted everywhere in the panel, including search results.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .onAppear { reload() }
        .sheet(item: $editor) { target in
            CategoryEditor(
                category: target.category,
                onSave: { save($0, isNew: target.category == nil) },
                onCancel: { editor = nil }
            )
            .frame(width: 460)
        }
    }

    private var groupBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    private func columnHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(trailing)
        }
        .font(.system(size: 11, weight: .bold))
        .tracking(0.8)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func builtInRow<Icon: View>(icon: Icon, name: String, detail: Text) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 14)
            Text(name).font(.system(size: 13.5, weight: .semibold))
            Spacer()
            detail
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func categoryRow(_ category: ClipboardCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
            Circle()
                .fill(Color(hex: category.color))
                .frame(width: 10, height: 10)
            Text(category.name)
                .font(.system(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            typeBadge(category)
                .frame(width: 150, alignment: .leading)
            Text("\(counts[category.id] ?? 0)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            HStack(spacing: 2) {
                iconButton("pencil", label: "Edit \(category.name)") {
                    editor = EditorTarget(category: category)
                }
                iconButton("trash", label: "Delete \(category.name)") {
                    delete(category)
                }
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(
            category.isSensitive ? Theme.amber.opacity(0.06) : Color.clear
        )
    }

    @ViewBuilder
    private func typeBadge(_ category: ClipboardCategory) -> some View {
        if category.isSensitive {
            HStack(spacing: 6) {
                Label("Sensitive", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.amber.opacity(0.16)))
                Text("first \(category.visibleCharacters)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Standard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
    }

    private func iconButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func reload() {
        categories = (try? repository.allCategories()) ?? []
        counts = (try? repository.categoryItemCounts()) ?? [:]
        pinnedCount = (try? repository.pinnedCount()) ?? 0
    }

    private func save(_ category: ClipboardCategory, isNew: Bool) {
        if isNew {
            try? repository.addCategory(category)
        } else {
            try? repository.saveCategory(category)
        }
        editor = nil
        reload()
    }

    private func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        try? repository.reorderCategories(categories.map(\.id))
    }

    /// Deletes a category; its items return to the normal history.
    private func delete(_ category: ClipboardCategory) {
        try? repository.deleteCategory(id: category.id)
        reload()
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
