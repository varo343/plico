import AppKit
import SwiftUI

public enum SettingsPane: String, CaseIterable, Identifiable {
    case general, editor, outlook, data

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .editor: "Editor"
        case .outlook: "Outlook"
        case .data: "Data"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .editor: "textformat"
        case .outlook: "envelope"
        case .data: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Appearance"
        case .editor: "Default font and size"
        case .outlook: "Connect and choose what to show"
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
        ScrollView {
            VStack(alignment: .leading, spacing: SNSpacing.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pane.title).font(SNFont.title).foregroundStyle(SNColor.textPrimary)
                    Text(pane.subtitle).font(.system(size: 13)).foregroundStyle(SNColor.textSecondary)
                }
                switch pane {
                case .general: GeneralSettings(settings: app.settings)
                case .editor: EditorSettings(settings: app.settings)
                case .outlook: OutlookSettings(outlook: app.outlook)
                case .data: DataSettings(app: app)
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
            .padding(.top, SNSpacing.xxs)
            .padding(.bottom, SNSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(pane)
        .transition(.opacity)
    }
}

// MARK: - Building blocks

/// A titled group of settings in a soft rounded container.
private struct SettingsGroup<Content: View>: View {
    let title: String
    var footnote: String?
    var tint: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(SNColor.textSecondary)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(SNSpacing.s)
                .background((tint ?? SNColor.canvas), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SNColor.borderSubtle, lineWidth: 1))
            if let footnote {
                Text(footnote).font(.system(size: 11.5)).foregroundStyle(SNColor.textSecondary).padding(.leading, 4)
            }
        }
    }
}

/// Row with a tinted icon tile, a title, a description and a trailing control.
private struct SettingsRow<Trailing: View>: View {
    let icon: String
    var tint: Color = SNColor.accentMint
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: SNSpacing.s) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SNColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(OrganicBlobShape().fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(SNColor.textPrimary)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(SNColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SNSpacing.s)
            trailing
        }
        .padding(.vertical, 4)
    }
}

/// Selectable tile with hover lift and an animated selection ring.
private struct ChoiceTile<Content: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: SNSpacing.xs) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(SNColor.card, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? SNColor.focusRing : SNColor.borderSubtle, lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(SNColor.focusRing, SNColor.card)
                                .padding(5)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .scaleEffect(isHovered ? 1.03 : 1)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SNColor.textPrimary : SNColor.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TilePressStyle())
        .onHover { isHovered = $0 }
        .snAnimation(SNMotion.snappy, value: isSelected)
        .snAnimation(SNMotion.hover, value: isHovered)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.snPressEffect(configuration.isPressed, scale: 0.96)
    }
}

/// Segmented control with a sliding indicator (concentric: 10 − 3 = 7).
private struct SNSegmented<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular).monospacedDigit())
                        .foregroundStyle(isSelected ? SNColor.textPrimary : SNColor.textSecondary)
                        .frame(minWidth: 40)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7).fill(SNColor.card)
                                    .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "segment", in: indicator)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(TilePressStyle())
                .accessibilityLabel(label(option))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(SNColor.borderSubtle.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .snAnimation(.spring(response: 0.3, dampingFraction: 0.75), value: selection)
    }
}

// MARK: - Panes

struct GeneralSettings: View {
    let settings: SettingsModel

    var body: some View {
        SettingsGroup(title: "Appearance", footnote: "System follows your Mac's light or dark setting.") {
            HStack(spacing: SNSpacing.s) {
                ForEach(AppearancePreference.allCases, id: \.self) { option in
                    ChoiceTile(title: option.title, isSelected: settings.settings.appearance == option,
                               action: { settings.update { $0.appearance = option } }) {
                        ThemePreview(option: option)
                    }
                }
            }
        }
    }
}

/// Miniature window used by the appearance tiles.
private struct ThemePreview: View {
    let option: AppearancePreference

    var body: some View {
        switch option {
        case .light: window(dark: false)
        case .dark: window(dark: true)
        case .system:
            ZStack {
                window(dark: false)
                window(dark: true).mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }

    private func window(dark: Bool) -> some View {
        let background = dark ? Color(red: 0.16, green: 0.15, blue: 0.13) : Color(red: 0.94, green: 0.92, blue: 0.89)
        let card = dark ? Color(red: 0.21, green: 0.2, blue: 0.18) : Color(red: 1, green: 1, blue: 0.98)
        let line = dark ? Color.white.opacity(0.35) : Color.black.opacity(0.25)
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(line).frame(width: 18, height: 3) }
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(line).frame(width: 34, height: 4)
                Capsule().fill(line.opacity(0.6)).frame(width: 44, height: 3)
                Capsule().fill(line.opacity(0.6)).frame(width: 30, height: 3)
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(card, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(5)
        .frame(width: 104, height: 56)
        .background(background, in: RoundedRectangle(cornerRadius: 7))
    }
}

struct EditorSettings: View {
    let settings: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.l) {
            SettingsGroup(title: "Font") {
                HStack(spacing: SNSpacing.s) {
                    ForEach(FontFamilyPreset.allCases, id: \.self) { family in
                        ChoiceTile(title: family.menuTitle, isSelected: settings.settings.defaultFontFamily == family,
                                   action: { settings.update { $0.defaultFontFamily = family } }) {
                            Text("Aa")
                                .font(Font(RichTextAttributes.font(family: family, size: 24, weight: .medium, italic: false)))
                                .foregroundStyle(SNColor.textPrimary)
                        }
                    }
                }
            }
            SettingsGroup(title: "Text size") {
                SNSegmented(
                    options: FontSizePreset.allCases,
                    selection: Binding(get: { settings.settings.defaultFontSize }, set: { value in settings.update { $0.defaultFontSize = value } }),
                    label: { "\($0.rawValue)" }
                )
            }
            SettingsGroup(title: "Preview", footnote: "Applies to text without its own font or size. Formatting you set on text is kept.") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Weekend plans")
                        .font(Font(RichTextAttributes.font(family: settings.settings.defaultFontFamily,
                                                          size: settings.settings.defaultFontSize.points + 4, weight: .semibold, italic: false)))
                    Text("Pick up coffee beans, call the plumber, and write a calm, readable note about it.")
                        .font(Font(RichTextAttributes.font(family: settings.settings.defaultFontFamily,
                                                          size: settings.settings.defaultFontSize.points, weight: .regular, italic: false)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(SNColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SNSpacing.m)
                .background(SNColor.card, in: RoundedRectangle(cornerRadius: 10))
                .snAnimation(SNMotion.snappy, value: settings.settings.defaultFontSize)
            }
        }
    }
}

struct DataSettings: View {
    let app: AppModel
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.l) {
            SettingsGroup(title: "Backup") {
                SettingsRow(icon: "square.and.arrow.up", tint: SNColor.accentMint, title: "Export all notes",
                            subtitle: "A folder with notes.json (complete backup) and a Markdown file per note, Trash included.") {
                    Button("Export…") { app.exportAllNotes() }
                        .buttonStyle(SNCapsuleButtonStyle())
                }
            }
            SettingsGroup(title: "Storage") {
                SettingsRow(icon: "internaldrive", tint: SNColor.accentSun, title: "Stored on this Mac",
                            subtitle: app.dependencies.isInMemory
                                ? "This session uses a temporary in-memory store (sample data)."
                                : "Notes never leave this Mac unless you export them.") {
                    Button("Show in Finder") { app.revealStoreInFinder() }
                        .buttonStyle(SNCapsuleButtonStyle())
                        .disabled(app.dependencies.isInMemory)
                }
            }
            SettingsGroup(title: "Danger zone", tint: SNColor.accentCoral.opacity(0.25)) {
                SettingsRow(icon: "exclamationmark.triangle", tint: SNColor.accentCoral, title: "Delete all local data",
                            subtitle: "Permanently deletes every note, including Trash, and resets settings. Export first if you want a backup.") {
                    Button("Delete All…") { confirmDelete = true }
                        .buttonStyle(SNCapsuleButtonStyle(isDestructive: true))
                }
            }
        }
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

extension AppearancePreference {
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

struct OutlookSettings: View {
    @Bindable var outlook: OutlookModel
    @State private var confirmDisconnect = false

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.l) {
            SettingsGroup(title: "Connection") {
                SettingsRow(icon: "envelope", tint: outlook.account == nil ? SNColor.borderSubtle : SNColor.accentMint,
                            title: outlook.account?.address ?? "Not connected",
                            subtitle: outlook.account == nil
                                ? (outlook.configuration.isComplete ? "Ready to connect." : "Add your app registration below first.")
                                : "Read-only. Smart Notes never sends, deletes or changes email.") {
                    if outlook.account == nil {
                        Button(outlook.status == .connecting ? "Connecting…" : "Connect") { Task { await outlook.connect() } }
                            .buttonStyle(SNCapsuleButtonStyle())
                            .disabled(!outlook.configuration.isComplete || outlook.status == .connecting)
                    } else {
                        Button("Disconnect…") { confirmDisconnect = true }
                            .buttonStyle(SNCapsuleButtonStyle(isDestructive: true))
                    }
                }
            }

            SettingsGroup(title: "Show in Mentions", footnote: outlook.scope == .mentions
                ? "Mentions uses a Microsoft Graph beta feature. If Microsoft changes it, switch to Flagged or All inbox."
                : nil) {
                VStack(alignment: .leading, spacing: SNSpacing.xs) {
                    SNSegmented(options: OutlookImportScope.allCases, selection: $outlook.scope, label: { $0.title })
                    Text(outlook.scope.explanation).font(.system(size: 11.5)).foregroundStyle(SNColor.textSecondary)
                }
            }

            SettingsGroup(title: "App registration", footnote: "Using a work account? Check your company's policy for third-party apps first. Your organization may need to approve access.") {
                VStack(alignment: .leading, spacing: SNSpacing.s) {
                    LabeledField(title: "Application (client) ID", placeholder: "00000000-0000-0000-0000-000000000000",
                                 text: Binding(get: { outlook.configuration.clientID }, set: { outlook.configuration.clientID = $0.trimmingCharacters(in: .whitespaces) }),
                                 isValid: outlook.configuration.clientID.isEmpty || UUID(uuidString: outlook.configuration.clientID) != nil)
                    HStack(alignment: .bottom, spacing: SNSpacing.xs) {
                        LabeledField(title: "Account type or tenant ID", placeholder: "common",
                                     text: Binding(get: { outlook.configuration.tenant }, set: { outlook.configuration.tenant = $0.trimmingCharacters(in: .whitespaces) }),
                                     isValid: !outlook.configuration.tenant.isEmpty)
                        SNDropdown(minWidth: 240) {
                            [("common", "Work and personal accounts"), ("organizations", "Work or school accounts"), ("consumers", "Personal accounts")].map { value, title in
                                .item(SNMenuItem(title: title, isChecked: outlook.configuration.tenant == value, shortcut: value) { outlook.configuration.tenant = value })
                            }
                        } label: {
                            Text("Presets").font(.system(size: 12))
                        }
                    }
                    HStack(spacing: SNSpacing.xs) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Redirect URI").font(.system(size: 11, weight: .semibold)).foregroundStyle(SNColor.textSecondary)
                            Text(OutlookConfiguration.redirectURI).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(SNColor.textPrimary)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(OutlookConfiguration.redirectURI, forType: .string)
                        }
                        .buttonStyle(SNCapsuleButtonStyle())
                    }
                    Rectangle().fill(SNColor.borderSubtle).frame(height: 1)
                    SetupSteps()
                }
            }
        }
        .confirmationDialog("Disconnect Outlook?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button("Disconnect and Remove Saved Emails", role: .destructive) { outlook.disconnect(removeSavedMessages: true) }
            Button("Disconnect, Keep Saved Emails") { outlook.disconnect(removeSavedMessages: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your sign-in is removed from this Mac. Notes you created from emails are kept either way.")
        }
    }
}

private struct LabeledField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isValid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(SNColor.textSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(SNColor.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isValid ? SNColor.borderSubtle : SNColor.accentCoral, lineWidth: isValid ? 1 : 1.5))
        }
    }
}

private struct SetupSteps: View {
    private let steps = [
        "Open Microsoft Entra ▸ App registrations ▸ New registration. Name it \"Smart Notes\".",
        "Supported account types: pick what you use (work, personal, or both).",
        "Redirect URI: platform \"Public client/native (mobile & desktop)\", value smartnotes://auth.",
        "API permissions ▸ Microsoft Graph ▸ Delegated: User.Read, Mail.Read, offline_access.",
        "Copy the Application (client) ID here, then press Connect.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            HStack {
                Text("How to set up (5 minutes)").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(SNColor.textPrimary)
                Spacer()
                Button {
                    if let url = URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) { MotionIcon(symbol: "square.and.arrow.up", size: 11, weight: .semibold); Text("Open Entra") }
                }
                .buttonStyle(SNCapsuleButtonStyle())
            }
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: SNSpacing.xs) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .frame(width: 18, height: 18)
                        .background(WobblyCapsuleShape(variant: index, amplitude: 1.6).fill(SNColor.accentSun))
                    Text(step).font(.system(size: 12)).foregroundStyle(SNColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
