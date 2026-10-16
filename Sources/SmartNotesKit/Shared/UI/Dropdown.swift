import AppKit
import SwiftUI

// MARK: - Floating panel

/// Borderless child window used for dropdowns and the slash menu. A real
/// window (not a SwiftUI overlay) so it is never clipped or covered by other columns.
final class FloatingPanel: NSPanel {
    private let acceptsKey: Bool

    init(acceptsKey: Bool) {
        self.acceptsKey = acceptsKey
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

/// Shows SwiftUI content in a `FloatingPanel` anchored to a screen rect.
@MainActor
final class FloatingPanelController {
    /// Transparent margin around the content, leaving room for its shadow.
    static let margin: CGFloat = 10

    private var panel: FloatingPanel?
    private weak var parent: NSWindow?
    private var anchor: NSRect = .zero
    private var centered = false
    private var preferAbove = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    var onClose: (() -> Void)?

    var isShown: Bool { panel != nil }
    /// Frame of the open panel in screen coordinates (for tests).
    var panelFrame: NSRect? { panel?.frame }

    /// - acceptsKey: true for menus navigated with the keyboard; false when typing
    ///   must stay in the editor (slash menu).
    /// - centered: center horizontally on the anchor (tooltips) instead of aligning leading edges.
    /// - preferAbove: open above the anchor when there is room.
    /// - passesClicksThrough: the panel ignores the mouse (tooltips).
    func show<Content: View>(_ content: Content, below anchor: NSRect, in parent: NSWindow, acceptsKey: Bool,
                             centered: Bool = false, preferAbove: Bool = false, passesClicksThrough: Bool = false) {
        close()
        self.centered = centered
        self.preferAbove = preferAbove
        let panel = FloatingPanel(acceptsKey: acceptsKey)
        panel.ignoresMouseEvents = passesClicksThrough
        // The window follows the content's size (e.g. a filtering slash menu).
        let host = NSHostingController(rootView: content.padding(Self.margin))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        self.anchor = anchor
        self.parent = parent
        position(panel)

        parent.addChildWindow(panel, ordered: .above)
        if acceptsKey { panel.makeKey() } else { panel.orderFront(nil) }
        self.panel = panel

        // Dismiss on any click outside the panel.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }) { monitors.append(monitor) }
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification, NSWindow.didMiniaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: parent, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
        // Keep the top edge pinned to the anchor when the content resizes.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                self.position(panel)
            }
        })
    }

    /// Moves an open panel (e.g. the slash menu following the caret).
    func move(below anchor: NSRect) {
        self.anchor = anchor
        if let panel { position(panel) }
    }

    /// Below the anchor (or above when preferred); flips when there's no room.
    private func position(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = parent?.screen?.visibleFrame ?? panel.screen?.visibleFrame ?? .infinite
        let below = anchor.minY - size.height + Self.margin - 4
        let above = anchor.maxY - Self.margin + 4
        var y = preferAbove ? above : below
        if preferAbove, y + size.height > screen.maxY { y = below }
        if !preferAbove, y < screen.minY { y = above }
        var x = centered ? anchor.midX - size.width / 2 : anchor.minX - Self.margin
        x = min(max(x, screen.minX), screen.maxX - size.width)
        let origin = NSPoint(x: x, y: y)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard let panel else { return }
        let wasKey = panel.isKeyWindow
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        if wasKey { parent?.makeKey() }
        onClose?()
    }
}

// MARK: - Menu content

struct SNMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var icon: String?
    /// Custom leading content (e.g. a badge) instead of icon + title.
    var badge: AnyView?
    var isChecked = false
    var isDestructive = false
    var shortcut: String?
    var action: () -> Void
}

enum SNMenuEntry: Identifiable {
    case item(SNMenuItem)
    case header(String)
    case divider(id: UUID = UUID())

    var id: String {
        switch self {
        case .item(let item): item.id.uuidString
        case .header(let title): "header-" + title
        case .divider(let id): "divider-" + id.uuidString
        }
    }
}

/// Visual container shared by every floating surface (menus, calendar, slash
/// menu): quiet card, hairline border, soft shadow. Inner items use radius
/// `radius - padding`, so the corners are concentric.
struct SNFloatingSurface<Content: View>: View {
    static var radius: CGFloat { 12 }
    static var padding: CGFloat { 4 }
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Self.padding)
            .background(SNColor.card, in: RoundedRectangle(cornerRadius: Self.radius))
            .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(SNColor.borderSubtle, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.14), radius: 14, y: 8)
    }
}

/// Keyboard-navigable menu list (↑/↓, Return, Esc) with hover highlights.
struct SNMenuList: View {
    let entries: [SNMenuEntry]
    var minWidth: CGFloat = 200
    let dismiss: () -> Void
    @State private var highlighted: UUID?
    @FocusState private var focused: Bool

    private var items: [SNMenuItem] {
        entries.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    var body: some View {
        SNFloatingSurface {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(entries) { entry in
                    switch entry {
                    case .header(let title):
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(SNColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    case .divider:
                        Rectangle().fill(SNColor.borderSubtle).frame(height: 1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                    case .item(let item):
                        row(item)
                    }
                }
            }
            .frame(minWidth: minWidth, alignment: .leading)
        }
        .fixedSize()
        .modifier(PopIn())
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear {
            focused = true
            highlighted = items.first(where: \.isChecked)?.id ?? items.first?.id
        }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.return) { activate(items.first { $0.id == highlighted }); return .handled }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .accessibilityElement(children: .contain)
    }

    private func row(_ item: SNMenuItem) -> some View {
        let isHighlighted = highlighted == item.id
        let innerRadius = SNFloatingSurface<EmptyView>.radius - SNFloatingSurface<EmptyView>.padding
        return Button { activate(item) } label: {
            HStack(spacing: SNSpacing.xs) {
                if let badge = item.badge {
                    badge
                } else {
                    if let icon = item.icon {
                        Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 18)
                            .iconMotion(for: icon, on: isHighlighted)
                    }
                    Text(item.title).font(.system(size: 13, weight: .medium))
                }
                Spacer(minLength: SNSpacing.m)
                if let shortcut = item.shortcut {
                    Text(shortcut).font(.system(size: 11)).foregroundStyle(SNColor.textSecondary)
                }
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(item.isChecked ? 1 : 0)
            }
            .foregroundStyle(item.isDestructive ? Color(nsColor: .systemRed) : SNColor.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHighlighted ? SNColor.borderSubtle.opacity(0.85) : .clear,
                        in: RoundedRectangle(cornerRadius: innerRadius))
            .contentShape(RoundedRectangle(cornerRadius: innerRadius))
            .snAnimation(SNMotion.hover, value: isHighlighted)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = item.id } }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }

    private func step(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == highlighted } ?? (delta > 0 ? -1 : items.count)
        highlighted = items[(index + delta + items.count) % items.count].id
    }

    private func activate(_ item: SNMenuItem?) {
        guard let item else { return }
        dismiss()
        item.action()
    }
}

// MARK: - Trigger

/// Product-styled dropdown: any label as the trigger, `SNMenuList` as the menu.
struct SNDropdown<Label: View>: View {
    var minWidth: CGFloat = 200
    var shape: SNHighlightShape = .rounded(8)
    /// Text triggers show a chevron; icon-only triggers usually don't.
    var showsChevron = true
    var onOpenChange: (Bool) -> Void = { _ in }
    let entries: () -> [SNMenuEntry]
    @ViewBuilder let label: () -> Label
    @State private var controller = FloatingPanelController()
    @State private var anchor = AnchorBox()
    @State private var isOpen = false

    var body: some View {
        Button { isOpen ? controller.close() : open() } label: {
            HStack(spacing: 3) {
                label()
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(SNColor.textSecondary)
                }
            }
            .padding(.horizontal, showsChevron ? 6 : 0)
        }
        .buttonStyle(SNIconButtonStyle(isActive: isOpen, shape: shape))
        .background(AnchorReader(box: anchor))
        .onDisappear { controller.close() }
    }

    private func open() {
        guard let window = anchor.view?.window, let rect = anchor.screenRect else { return }
        controller.onClose = { isOpen = false; onOpenChange(false) }
        controller.show(SNMenuList(entries: entries(), minWidth: minWidth) { controller.close() },
                        below: rect, in: window, acceptsKey: true)
        isOpen = true
        onOpenChange(true)
    }
}

/// Dropdown whose panel holds arbitrary content (e.g. a calendar).
struct SNPopoverButton<Label: View, Panel: View>: View {
    var isSet = true
    @ViewBuilder let label: () -> Label
    @ViewBuilder let panel: (_ dismiss: @escaping () -> Void) -> Panel
    @State private var controller = FloatingPanelController()
    @State private var anchor = AnchorBox()
    @State private var isOpen = false

    var body: some View {
        Button { isOpen ? controller.close() : open() } label: { label() }
            .buttonStyle(SNIconButtonStyle(isActive: isOpen, shape: .capsule, size: CGSize(width: 0, height: 24)))
            .background(AnchorReader(box: anchor))
            .onDisappear { controller.close() }
    }

    private func open() {
        guard let window = anchor.view?.window, let rect = anchor.screenRect else { return }
        controller.onClose = { isOpen = false }
        controller.show(SNFloatingSurface { panel { controller.close() } }.fixedSize().modifier(PopIn()), below: rect, in: window, acceptsKey: true)
        isOpen = true
    }
}

// MARK: - Anchoring

/// Holds the AppKit view behind a SwiftUI control. Positions come from AppKit
/// (view → window → screen), which is correct no matter how many hosting
/// views or split-view columns sit in between. (SwiftUI's `.global` space is
/// per hosting view, which put menus in the wrong place.)
@MainActor
final class AnchorBox {
    weak var view: NSView?

    var screenRect: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct AnchorReader: NSViewRepresentable {
    let box: AnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }
}
