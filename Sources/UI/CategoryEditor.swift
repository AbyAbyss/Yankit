import SwiftUI

/// Creates or edits a category: its name, color, whether it is sensitive,
/// and how many characters of a sensitive item stay visible. Shown as a card
/// in the history panel and as a sheet in Settings; the caller supplies the
/// background.
struct CategoryEditor: View {
    var onSave: (ClipboardCategory) -> Void
    var onCancel: () -> Void

    @Environment(\.accent) private var accent
    private let isNew: Bool
    @State private var draft: ClipboardCategory
    @FocusState private var nameFocused: Bool

    /// Example text for the redaction preview.
    private static let sample = "sk-example-4f9a2c71d8e3b6a0"

    init(
        category: ClipboardCategory?,
        onSave: @escaping (ClipboardCategory) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onCancel = onCancel
        isNew = category == nil
        _draft = State(initialValue: category ?? ClipboardCategory(name: ""))
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            section("Name") {
                TextField("Category name", text: $draft.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($nameFocused)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(accent.tint, lineWidth: 1.5)
                    )
            }
            section("Color") { colorPicker }
            section("Type") { typePicker }
            if draft.isSensitive { visibleCharacters }
            buttons
        }
        .padding(22)
        .frame(maxWidth: 460)
        .onAppear {
            DispatchQueue.main.async { nameFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: draft.isSensitive ? "lock.fill" : "folder.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: "#111111"))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: draft.color)))
            Text(isNew ? "New category" : "Edit category")
                .font(.system(size: 17, weight: .bold))
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(Theme.categoryColors, id: \.hex) { swatch in
                let isSelected = draft.color == swatch.hex
                Button {
                    draft.color = swatch.hex
                } label: {
                    Circle()
                        .fill(Color(hex: swatch.hex))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: 2)
                                .padding(-4)
                                .opacity(isSelected ? 1 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.leading, 4)
    }

    private var typePicker: some View {
        HStack(spacing: 8) {
            typeCard(
                sensitive: false,
                title: Text("Standard"),
                detail: "Full text shown in the list and preview."
            )
            typeCard(
                sensitive: true,
                title: Text("Sensitive \(Image(systemName: "lock.fill"))")
                    .foregroundColor(Theme.amber),
                detail: "Only the first characters show. The rest is redacted."
            )
        }
    }

    private func typeCard(sensitive: Bool, title: Text, detail: String) -> some View {
        let isSelected = draft.isSensitive == sensitive
        return Button {
            draft.isSensitive = sensitive
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                title.font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(sensitive ? Theme.amber.opacity(0.08) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? accent.tint : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var visibleCharacters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Visible characters").font(.system(size: 13))
                Spacer()
                HStack(spacing: 0) {
                    stepButton("minus", label: "Fewer characters") {
                        draft.visibleCharacters = max(0, draft.visibleCharacters - 1)
                    }
                    Text("\(draft.visibleCharacters)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 30)
                    stepButton("plus", label: "More characters") {
                        draft.visibleCharacters = min(12, draft.visibleCharacters + 1)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("PREVIEW")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                (Text(Self.sample.prefix(draft.visibleCharacters))
                    + Text(String(repeating: "•", count: 18 - draft.visibleCharacters))
                        .foregroundColor(Theme.amber.opacity(0.6)))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.amber.opacity(0.08)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Theme.amber.opacity(0.22), lineWidth: 1)
                    )
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.05)))
    }

    private func stepButton(
        _ symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Button {
                var saved = draft
                saved.name = trimmedName
                onSave(saved)
            } label: {
                Text(isNew ? "Create category" : "Save")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent.onFill)
                    .padding(.horizontal, 18)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(accent.fill))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.5 : 1)
        }
    }
}
