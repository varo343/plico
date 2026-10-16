import AppKit
import SwiftUI

/// Settings window: appearance, editor defaults, and data (export, location, delete).
/// Outlook settings are omitted until the integration exists.
public struct SettingsView: View {
    private let app: AppModel

    public init(app: AppModel) {
        self.app = app
    }

    public var body: some View {
        TabView {
            GeneralSettings(settings: app.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            EditorSettings(settings: app.settings)
                .tabItem { Label("Editor", systemImage: "textformat") }
            DataSettings(app: app)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 500)
        .scenePadding()
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
            Picker("Font", selection: Binding(
                get: { settings.settings.defaultFontFamily },
                set: { value in settings.update { $0.defaultFontFamily = value } }
            )) {
                ForEach(FontFamilyPreset.allCases, id: \.self) { Text($0.menuTitle).tag($0) }
            }
            Picker("Text size", selection: Binding(
                get: { settings.settings.defaultFontSize },
                set: { value in settings.update { $0.defaultFontSize = value } }
            )) {
                ForEach(FontSizePreset.allCases, id: \.self) { Text("\($0.rawValue) pt").tag($0) }
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
