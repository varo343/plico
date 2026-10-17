import AppKit
import SwiftUI

/// List column of Mentions: connection status and email cards.
struct MentionsView: View {
    let outlook: OutlookModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if outlook.account != nil || outlook.isShowingSamples {
                ConnectionStatusLine(outlook: outlook)
                    .padding(.horizontal, SNSpacing.m)
                    .padding(.bottom, SNSpacing.s)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if outlook.account == nil && !outlook.isShowingSamples {
            switch outlook.status {
            case .connecting:
                EmptyState(symbol: "envelope", tint: SNColor.accentSun, title: "Waiting for Microsoft sign-in…",
                           message: "Finish signing in in the window that opened.")
            case .failed(let message):
                EmptyState(symbol: "exclamationmark.triangle", tint: SNColor.accentCoral, title: "Couldn't connect", message: message) {
                    Button("Try Again") { Task { await outlook.connect() } }.buttonStyle(SNCapsuleButtonStyle())
                    Button("Outlook Settings", action: openSettings).buttonStyle(SNCapsuleButtonStyle())
                }
            case .disconnected:
                EmptyState(symbol: "envelope", tint: SNColor.accentMint, title: "Connect Outlook",
                           message: "Show emails where someone @mentions you. Read-only. Plico never changes your mailbox.") {
                    Button("Connect Outlook") { Task { await outlook.connect() } }.buttonStyle(SNCapsuleButtonStyle())
                }
            default:
                EmptyState(symbol: "envelope", tint: SNColor.accentCoral, title: "Set up Outlook",
                           message: "Add your Microsoft app registration to connect. Until then you can preview with sample emails.") {
                    VStack(spacing: SNSpacing.xs) {
                        Button("Set Up in Settings", action: openSettings).buttonStyle(SNCapsuleButtonStyle())
                        Button("Preview with Sample Emails") { outlook.showSamples(true) }.buttonStyle(SNCapsuleButtonStyle())
                    }
                }
            }
        } else if outlook.items.isEmpty {
            EmptyState(symbol: outlook.scope == .mentions ? "at" : "tray", tint: SNColor.borderSubtle,
                       title: emptyTitle, message: outlook.scope.explanation)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(outlook.items) { item in
                        MentionCard(item: item, isSelected: item.id == outlook.selectedItemID) { outlook.select(item.id) }
                    }
                }
                .padding(.horizontal, SNSpacing.xs)
                .padding(.bottom, SNSpacing.l)
                .snAnimation(SNMotion.snappy, value: outlook.items.map(\.id))
            }
        }
    }

    private var emptyTitle: String {
        switch outlook.scope {
        case .mentions: "No emails mention you"
        case .flagged: "No flagged emails"
        case .inbox: "Your inbox is empty"
        }
    }
}

/// "From Outlook · updated 2 min ago", with Retry / Reconnect when needed.
struct ConnectionStatusLine: View {
    let outlook: OutlookModel

    var body: some View {
        VStack(alignment: .leading, spacing: SNSpacing.xs) {
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(statusText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SNColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            switch outlook.status {
            case .needsReconnect(let message):
                banner(message, action: "Reconnect") { Task { await outlook.connect() } }
            case .failed(let message):
                banner(message, action: "Retry") { Task { await outlook.refresh() } }
            default:
                EmptyView()
            }
        }
    }

    private var statusText: String {
        if outlook.isShowingSamples { return "Sample emails · not connected" }
        let account = outlook.account?.address ?? "Outlook"
        switch outlook.status {
        case .syncing: return "Updating from \(account)…"
        case .offline:
            return "Offline · showing saved emails" + (outlook.lastSyncAt.map { " from \($0.formatted(.relative(presentation: .named)))" } ?? "")
        default:
            guard let lastSync = outlook.lastSyncAt else { return "From \(account) · not updated yet" }
            return "From \(account) · updated \(lastSync.formatted(.relative(presentation: .named)))"
        }
    }

    private var dotColor: Color {
        switch outlook.status {
        case .ready: SNColor.accentMint
        case .syncing, .connecting: SNColor.accentSun
        case .offline: SNColor.borderSubtle
        default: outlook.isShowingSamples ? SNColor.borderSubtle : SNColor.accentCoral
        }
    }

    private func banner(_ message: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: SNSpacing.xs) {
            Text(message).font(.system(size: 11.5)).foregroundStyle(SNColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action, action: perform).buttonStyle(SNCapsuleButtonStyle())
        }
        .padding(SNSpacing.xs)
        .background(SNColor.accentCoral.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MentionCard: View {
    let item: ExternalItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.senderName ?? item.senderAddress ?? "Unknown sender")
                        .font(.system(size: 13, weight: item.isSeenLocally ? .medium : .bold))
                        .foregroundStyle(SNColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.receivedAt, format: .relative(presentation: .named))
                        .font(.system(size: 11))
                        .foregroundStyle(SNColor.textSecondary)
                        .lineLimit(1)
                }
                Text(item.subject)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SNColor.textPrimary)
                    .lineLimit(1)
                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(SNColor.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SNSpacing.s)
            .padding(.vertical, 10)
            .background {
                let shape = RoundedRectangle(cornerRadius: SNRadius.standard)
                if isSelected {
                    shape.fill(SNColor.card).overlay(shape.strokeBorder(SNColor.borderSubtle, lineWidth: 1))
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                } else if isHovered {
                    shape.fill(SNColor.borderSubtle.opacity(0.45))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SNRadius.standard))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .snAnimation(SNMotion.hover, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Mentions header controls: filter and refresh.
struct MentionsHeaderControls: View {
    let outlook: OutlookModel
    @State private var spins = 0

    var body: some View {
        HStack(spacing: 2) {
            SNDropdown(minWidth: 230, showsChevron: false) {
                [.header("Show")] + OutlookImportScope.allCases.map { scope in
                    .item(SNMenuItem(title: scope.title, icon: scope.symbol, isChecked: outlook.scope == scope) { outlook.scope = scope })
                }
            } label: {
                MotionIcon(symbol: outlook.scope.symbol, size: 12, weight: .semibold)
            }
            .foregroundStyle(SNColor.textPrimary)
            .hoverLabel("Showing: \(outlook.scope.title)")

            Button {
                spins += 1
                Task { await outlook.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(outlook.status == .syncing ? 360 : 0))
                    .iconMotion(for: "clock.arrow.circlepath", on: spins)
            }
            .buttonStyle(SNIconButtonStyle())
            .foregroundStyle(SNColor.textPrimary)
            .disabled(outlook.account == nil || outlook.status == .syncing)
            .hoverLabel("Refresh from Outlook")
            .accessibilityLabel("Refresh")
        }
    }
}

extension OutlookImportScope {
    var symbol: String {
        switch self {
        case .mentions: "at"
        case .flagged: "flag"
        case .inbox: "tray"
        }
    }
}

/// The selected email in the note card.
struct MentionDetailView: View {
    let outlook: OutlookModel
    let createNote: (ExternalItem) -> Void

    var body: some View {
        if let item = outlook.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: SNSpacing.m) {
                    Text(item.subject).font(SNFont.title).foregroundStyle(SNColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: SNSpacing.xs) {
                        SNBadge(text: tag(for: item), tone: item.importRule == OutlookImportScope.mentions.rawValue ? .sun : .neutral)
                        Text(senderLine(item)).font(.system(size: 12.5)).foregroundStyle(SNColor.textSecondary)
                    }
                    if !item.preview.isEmpty {
                        HStack(alignment: .top, spacing: SNSpacing.s) {
                            RoundedRectangle(cornerRadius: 1.5).fill(SNColor.borderSubtle).frame(width: 3)
                            Text(item.preview).font(SNFont.body).foregroundStyle(SNColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Preview only — the full email stays in Outlook.")
                            .font(.system(size: 11)).foregroundStyle(SNColor.textSecondary)
                    }
                    HStack(spacing: SNSpacing.xs) {
                        Button { createNote(item) } label: {
                            HStack(spacing: 4) { MotionIcon(symbol: "square.and.pencil", size: 11, weight: .semibold); Text("Create Note") }
                        }
                        .buttonStyle(SNCapsuleButtonStyle())
                        if let url = item.webUrl {
                            Button { NSWorkspace.shared.open(url) } label: {
                                HStack(spacing: 4) { MotionIcon(symbol: "envelope", size: 11, weight: .semibold); Text("Open in Outlook") }
                            }
                            .buttonStyle(SNCapsuleButtonStyle())
                        }
                        Button { outlook.dismiss(item.id) } label: {
                            HStack(spacing: 4) { MotionIcon(symbol: "xmark.circle", size: 11, weight: .semibold); Text("Dismiss") }
                        }
                        .buttonStyle(SNCapsuleButtonStyle())
                        .hoverLabel("Hides it here only. Outlook isn't changed.")
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, SNSpacing.xl + SNSpacing.xs)
                .padding(.top, SNSpacing.xxs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(item.id)
            .transition(.opacity)
        } else {
            EmptyState(symbol: "envelope.open", tint: SNColor.borderSubtle, title: "Select an email",
                       message: outlook.items.isEmpty ? "" : "Turn it into a note with one click.")
        }
    }

    private func tag(for item: ExternalItem) -> String {
        OutlookImportScope(rawValue: item.importRule)?.tag ?? "Outlook"
    }

    private func senderLine(_ item: ExternalItem) -> String {
        let sender = [item.senderName, item.senderAddress].compactMap { $0 }.joined(separator: " · ")
        return "\(sender) — \(item.receivedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension OutlookImportScope {
    var tag: String {
        switch self {
        case .mentions: "Mentions you"
        case .flagged: "Flagged"
        case .inbox: "Inbox"
        }
    }
}
