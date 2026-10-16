import AppKit
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable {
    case general, editor, data

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .editor: "Editor"
        case .data: "Data"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .editor: "textformat"
        case .data: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Appearance"
        case .editor: "Default font and size"
        case .data: "Export, storage, delete"
        }
    }
}

/// Settings categories, shown in the list column like any other section.
struct SettingsPaneList: View {
    @Binding var selection: SettingsPane
    @State private var hovered: SettingsPane?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings").font(.system(size: 22, weight: .bold)).foregroundStyle(SNColor.textPrimary)
                .padding(.horizontal, SNSpacing.m)
                .padding(.top, SNSpacing.xs)
                .padding(.bottom, SNSpacing.s)
            ForEach(SettingsPane.allCases) { pane in
                Button { selection = pane } label: {
                    HStack(spacing: SNSpacing.s) {
                        Image(systemName: pane.symbol).font(.system(size: 14)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pane.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(SNColor.textPrimary)
                            Text(pane.subtitle).font(.system(size: 11.5)).foregroundStyle(SNColor.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, SNSpacing.s)
                    .padding(.vertical, 9)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: SNRadius.standard)
                        if selection == pane {
                            shape.fill(SNColor.card)
                                .overlay(shape.strokeBorder(SNColor.borderSubtle, lineWidth: 1))
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        } else if hovered == pane {
                            shape.fill(SNColor.borderSubtle.opacity(0.45))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { hovered = pane } else if hovered == pane { hovered = nil } }
                .accessibilityAddTraits(selection == pane ? .isSelected : [])
            }
            .padding(.horizontal, SNSpacing.xs)
            Spacer()
        }
    }
}

/// The selected settings pane, shown in the note card.
struct SettingsPaneView: View {
    let app: AppModel
    let pane: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pane.title)
                .font(SNFont.title)
                .foregroundStyle(SNColor.textPrimary)
                .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
                .padding(.top, 44)
            Group {
                switch pane {
                case .general: GeneralSettings(settings: app.settings)
                case .editor: EditorSettings(settings: app.settings)
                case .data: DataSettings(app: app)
                }
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, SNSpacing.l)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GeneralSettings: View {
    let settings: SettingsModel

    var body: some View {
        Form {
            Picker("Appearance", selection: Binding(
                get: { settings.settings.appearance },
                set: { value in settings.update { $0.appearance = value } }
            )) {
                Text("System").tag(AppearancePreference.system)
                Text("Light").tag(AppearancePreference.light)
                Text("Dark").tag(AppearancePreference.dark)
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }
}

struct EditorSettings: View {
    let settings: SettingsModel

    var body: some View {
        Form {
            LabeledContent("Font") {
                SNDropdown(minWidth: 180) {
                    FontFamilyPreset.allCases.map { family in
                        .item(SNMenuItem(title: family.menuTitle, icon: family.symbol,
                                         isChecked: settings.settings.defaultFontFamily == family) {
                            settings.update { $0.defaultFontFamily = family }
                        })
                    }
                } label: {
                    Text(settings.settings.defaultFontFamily.menuTitle).font(.system(size: 13))
                }
            }
            LabeledContent("Text size") {
                SNDropdown(minWidth: 140) {
                    FontSizePreset.allCases.map { size in
                        .item(SNMenuItem(title: "\(size.rawValue) pt", isChecked: settings.settings.defaultFontSize == size) {
                            settings.update { $0.defaultFontSize = size }
                        })
                    }
                } label: {
                    Text("\(settings.settings.defaultFontSize.rawValue) pt").font(.system(size: 13))
                }
            }
            Section("Preview") {
                Text("The quick brown fox writes a calm, readable note.")
                    .font(Font(RichTextAttributes.font(
                        family: settings.settings.defaultFontFamily,
                        size: settings.settings.defaultFontSize.points,
                        weight: .regular, italic: false
                    )))
                    .padding(.vertical, SNSpacing.xxs)
            }
            Text("Applies to text without its own font or size. Formatting you set on text is kept.")
                .font(SNFont.secondary)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct DataSettings: View {
    let app: AppModel
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Backup") {
                LabeledContent("Export all notes") {
                    Button("Export…") { app.exportAllNotes() }
                }
                Text("Creates a folder with notes.json (a complete backup) and a Markdown file for each note, including Trash.")
                    .font(SNFont.secondary)
                    .foregroundStyle(.secondary)
            }
            Section("Storage") {
                LabeledContent("Notes are stored on this Mac") {
                    Button("Show in Finder") { app.revealStoreInFinder() }
                        .disabled(app.dependencies.isInMemory)
                }
                if app.dependencies.isInMemory {
                    Text("This session uses a temporary in-memory store (sample data).")
                        .font(SNFont.secondary).foregroundStyle(.secondary)
                }
            }
            Section("Danger zone") {
                LabeledContent("Delete all local data") {
                    Button("Delete All…", role: .destructive) { confirmDelete = true }
                }
                Text("Permanently deletes every note, including Trash, and resets settings. Export first if you want a backup.")
                    .font(SNFont.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmDestructiveAction(
            "Delete all notes and data?",
            isPresented: $confirmDelete,
            message: "All \(app.notes.activeNotes.count + app.notes.trashed.count) notes, including Trash, will be permanently deleted. This can't be undone.",
            actionTitle: "Delete Everything"
        ) {
            app.deleteAllData()
        }
    }
}
