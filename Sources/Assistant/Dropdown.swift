import SwiftUI
import AppKit
import AssistantCore

// MARK: - Knowledge-base spine colours (display only, never stored)

enum KnowledgeSpine {
    /// 雾蓝、鼠尾草、陶土、葡萄紫、石墨、芥黄 — light / dark.
    private static let palette: [(UInt32, UInt32)] = [
        (0x5B7FA6, 0x4E6E92), (0x6E8F7B, 0x5E7C6A), (0xB9785A, 0xA26950),
        (0x7D6B9E, 0x6C5C8A), (0x5E6470, 0x545A66), (0xB89A4E, 0x9F8644)
    ]
    /// Count tag on the book: same hue, lifted in dark mode so 11pt text stays legible.
    private static let tagPalette: [(UInt32, UInt32)] = [
        (0x5B7FA6, 0x8FAACB), (0x6E8F7B, 0x97B5A2), (0xB9785A, 0xD49C82),
        (0x7D6B9E, 0xA796C4), (0x5E6470, 0x9BA1AC), (0xB89A4E, 0xD3B977)
    ]
    /// Stable FNV-1a over the name's UTF-8 bytes (Swift's `hashValue` changes between launches).
    static func index(for name: String) -> Int {
        var hash: UInt32 = 0x811C9DC5
        for byte in name.utf8 { hash ^= UInt32(byte); hash = hash &* 0x01000193 }
        return Int(hash % UInt32(palette.count))
    }
    static func color(for name: String) -> Color { let p = palette[index(for: name)]; return AppTheme.dyn(p.0, p.1) }
    static func tagColor(for name: String) -> Color { let p = tagPalette[index(for: name)]; return AppTheme.dyn(p.0, p.1) }
}

/// Dev screenshots only: `--preview --preview-dropdown <name>` starts with that panel open.
enum DropdownPreview {
    static func isOpen(_ name: String) -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--preview"), let i = args.firstIndex(of: "--preview-dropdown"), i + 1 < args.count else { return false }
        return args[i + 1] == name
    }
}

// MARK: - Dropdown items & panel content

struct DropdownItem: Identifiable {
    enum Kind { case option, checkbox, footer, primaryAction }
    var id: String
    var title: String
    var detail: String? = nil
    var spine: Color? = nil
    var selected = false
    var kind: Kind = .option
    var dividerBefore = false
    var action: () -> Void
    /// Single choice closes the panel; checkboxes and footer actions keep it open.
    var keepsOpen: Bool { kind == .checkbox || kind == .footer }
}

@MainActor final class DropdownKeyState: ObservableObject {
    @Published var highlighted: Int?
}

/// Panel body: white, 1px cardBorder, r12, 4pt inset; rows 32 high r8, hover 4%.
struct DropdownPanelView: View {
    var header: String?
    var empty: String?
    var items: [DropdownItem]
    var width: CGFloat
    var maxVisibleRows = 9
    @ObservedObject var keys: DropdownKeyState
    var activate: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            if items.isEmpty, let empty {
                Text(empty).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 10).frame(height: 32)
            }
            let rows = VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if item.dividerBefore { Rectangle().fill(AppTheme.rowDivider).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 4) }
                    row(item, index: index)
                }
            }
            if items.count > maxVisibleRows {
                ScrollViewReader { reader in
                    ScrollView { rows }
                        .frame(height: CGFloat(maxVisibleRows) * 32)
                        .onChange(of: keys.highlighted) { _, i in if let i, items.indices.contains(i) { reader.scrollTo(items[i].id) } }
                }
            } else { rows }
        }
        .padding(4)
        .frame(width: width, alignment: .leading)
        .background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 9, x: 0, y: 6)   // the one very light float shadow
        .accessibilityElement(children: .contain)
        .accessibilityLabel(header ?? "选项")
    }

    @ViewBuilder private func row(_ item: DropdownItem, index: Int) -> some View {
        let hot = keys.highlighted == index
        if item.kind == .primaryAction {
            Button { activate(index) } label: {
                Label(item.title, systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(ModernPrimaryButtonStyle(cornerRadius: 8, horizontalPadding: 0, verticalPadding: 0))
            .padding(4)
            .id(item.id)
        } else {
        Button { activate(index) } label: {
            HStack(spacing: 8) {
                if item.kind == .checkbox { DropdownCheckbox(on: item.selected) }
                if let spine = item.spine { RoundedRectangle(cornerRadius: 2, style: .continuous).fill(spine).frame(width: 4, height: 20) }
                Text(item.title).font(.system(size: 13, weight: item.kind == .footer ? .medium : .regular))
                    .foregroundStyle(item.kind == .footer ? AppTheme.accent : Color.primary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                if let detail = item.detail { Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textSecondary) }
                if item.kind == .option && item.selected {   // reserve no empty column: unselected rows end 14pt from the panel edge
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.accent)
                        .frame(width: 12).opacity(item.selected ? 1 : 0)
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(hot ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
        .onHover { inside in if inside { keys.highlighted = index } else if keys.highlighted == index { keys.highlighted = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.detail.map { "\(item.title)，\($0)" } ?? item.title)
        .accessibilityAddTraits(item.kind == .checkbox ? [.isToggle, .isButton] : .isButton)
        .accessibilityAddTraits(item.selected && item.kind != .footer ? .isSelected : [])
        .accessibilityValue(item.kind == .checkbox ? (item.selected ? "已选中" : "未选中") : (item.selected ? "已选中" : ""))
        .accessibilityAction { activate(index) }
        }
    }
}

struct DropdownCheckbox: View {
    var on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(on ? AppTheme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(on ? AppTheme.accent : Color.primary.opacity(0.25), lineWidth: 1.5))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) } }
            .frame(width: 16, height: 16)
    }
}

// MARK: - Floating panel host (own window: never clipped by the 364×480 start window)

/// A click outside closes the open panel. If that click lands on the panel's own trigger, its action must not reopen it:
/// triggers call `DropdownGate.toggle`, which ignores the toggle belonging to the dismissing click.
@MainActor enum DropdownGate {
    static var suppressUntilMouseUp = false
    private static var upMonitor: Any?
    static func armMouseUpReset() {
        guard upMonitor == nil else { return }
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { event in
            if suppressUntilMouseUp { DispatchQueue.main.async { suppressUntilMouseUp = false } }
            return event
        }
    }
    static func toggle(_ isOpen: Binding<Bool>) {
        if suppressUntilMouseUp { suppressUntilMouseUp = false; return }
        isOpen.wrappedValue.toggle()
    }
}

final class DropdownPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Attach as `.background(...)` of the trigger: the panel lines up with this view's frame.
struct DropdownPanelAnchor: NSViewRepresentable {
    /// `.side`: attach to the card itself; the panel opens beside it (right, else left), its first row level with the
    /// trigger row whose centre is `rowCenter` pt below the card's top edge. Never overlaps the card.
    enum Edge { case below, above, side(rowCenter: CGFloat) }
    @Binding var isPresented: Bool
    var edge: Edge = .below
    var gap: CGFloat = 4
    /// nil → anchor width (min 200). Extra width can extend to the left (model picker spans its text field).
    var width: CGFloat? = nil
    var leadingExtension: CGFloat = 0
    var header: String? = nil
    var empty: String? = nil
    var items: [DropdownItem]
    /// `.side` only: reports which side the panel ended up on (true = left), so the trigger arrow can point at it.
    var onSide: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let v = NSView(); context.coordinator.anchor = v; return v }
    func updateNSView(_ view: NSView, context: Context) {
        let c = context.coordinator
        c.anchor = view
        c.config = self
        c.setPresented = { [binding = $isPresented] value in binding.wrappedValue = value }
        if isPresented { DispatchQueue.main.async { c.show() } } else { c.hide() }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.hide() }

    @MainActor final class Coordinator {
        weak var anchor: NSView?
        var config: DropdownPanelAnchor?
        var setPresented: (Bool) -> Void = { _ in }
        private var panel: DropdownPanelWindow?
        private var host: InteractiveHostingView<AnyView>?
        private let keys = DropdownKeyState()
        private var monitors: [Any] = []
        private var resignObserver: NSObjectProtocol?
        private let margin: CGFloat = 16   // room for the soft shadow

        private var items: [DropdownItem] { config?.items ?? [] }

        private var attempts = 0
        private var lastLeft: Bool?
        func show() {
            guard let config, config.isPresented, let anchor else { return }
            guard let parent = anchor.window else {   // opened before the trigger reached its window: try again shortly
                attempts += 1
                if attempts < 30 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.show() } }
                return
            }
            attempts = 0
            let rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let width = config.width ?? max(200, rect.width + config.leadingExtension)
            let isNew = panel == nil
            if isNew {
                let p = DropdownPanelWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
                p.isReleasedWhenClosed = false; p.hidesOnDeactivate = false
                p.level = parent.level
                p.setAccessibilitySubrole(.floatingWindow)
                let h = InteractiveHostingView(rootView: AnyView(EmptyView()))
                p.contentView = h
                panel = p; host = h
                let selected = items.firstIndex { $0.selected && $0.kind != .footer }
                keys.highlighted = selected
            }
            guard let panel, let host else { return }
            panel.appearance = parent.effectiveAppearance
            host.rootView = AnyView(
                DropdownPanelView(header: config.header, empty: config.empty, items: items, width: width, keys: keys) { [weak self] i in self?.activate(i) }
                    .padding(margin)
                    .environment(\.colorScheme, parent.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
                    .tint(AppTheme.accent)
            )
            let size = host.fittingSize
            if case .side(let rowCenter) = config.edge {
                let screen = parent.screen?.visibleFrame ?? .infinite
                let inner = CGSize(width: size.width - margin * 2, height: size.height - margin * 2)
                let firstRow = 4 + (config.header != nil ? DropdownSidePlacement.headerHeight : 0) + 16
                let placed = DropdownSidePlacement.frame(card: rect, rowMidY: rect.maxY - rowCenter, panelSize: inner, firstRowCenter: firstRow, screen: screen)
                panel.setFrame(placed.frame.insetBy(dx: -margin, dy: -margin), display: true)
                if placed.left != lastLeft { lastLeft = placed.left; let report = config.onSide; DispatchQueue.main.async { report?(placed.left) } }
                if isNew { parent.addChildWindow(panel, ordered: .above); panel.orderFront(nil); installMonitors(parent: parent) }
                return
            }
            var x = (config.width != nil ? rect.midX - width / 2 : rect.minX - config.leadingExtension) - margin
            if config.width != nil {   // a centred panel near the window edge stays inside the window (8pt inset)
                let lo = parent.frame.minX + 8 - margin, hi = parent.frame.maxX - 8 - width - margin
                if lo <= hi { x = min(max(x, lo), hi) }
            }
            var y: CGFloat
            let screen = parent.screen?.visibleFrame ?? .infinite
            switch config.edge {
            case .below:
                y = rect.minY - config.gap - (size.height - margin * 2) - margin
                if y + margin < screen.minY { y = rect.maxY + config.gap - margin }   // no room: flip up
            case .above:
                y = rect.maxY + config.gap - margin
                if y + size.height - margin > screen.maxY { y = rect.minY - config.gap - (size.height - margin * 2) - margin }
            case .side: return
            }
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
            if isNew {
                parent.addChildWindow(panel, ordered: .above)
                panel.orderFront(nil)
                installMonitors(parent: parent)
            }
        }

        func hide() {
            monitors.forEach(NSEvent.removeMonitor); monitors = []
            if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }; resignObserver = nil
            guard let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.panel = nil; host = nil
        }

        private func close() { setPresented(false); hide() }

        private func activate(_ index: Int) {
            guard items.indices.contains(index) else { return }
            let item = items[index]
            item.action()
            if !item.keepsOpen { close() }
        }

        private func move(_ delta: Int) {
            guard !items.isEmpty else { return }
            let next = keys.highlighted.map { $0 + delta } ?? (delta > 0 ? 0 : items.count - 1)
            keys.highlighted = min(max(next, 0), items.count - 1)
        }

        private func installMonitors(parent: NSWindow) {
            DropdownGate.armMouseUpReset()
            if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
                guard let self, self.panel != nil else { return e }
                switch e.keyCode {
                case 125: self.move(1); return nil                     // ↓
                case 126: self.move(-1); return nil                    // ↑
                case 36, 76, 49:                                       // Return / Enter / Space
                    if let i = self.keys.highlighted { self.activate(i) } else if e.keyCode != 49 { self.close() }
                    return nil
                case 53: self.close(); return nil                      // Esc
                default: return e
                }
            }) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] e in
                guard let self, let panel = self.panel, e.window !== panel else { return e }
                if e.type == .leftMouseDown { DropdownGate.suppressUntilMouseUp = true }
                self.close()
                return e
            }) { monitors.append(m) }
            if PreviewScreen.target == nil, let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
                Task { @MainActor in self?.close() }
            }) { monitors.append(m) }   // offscreen preview: clicks in other apps don't close it
            resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }
    }
}

/// 「存入知识库」 (P1-9): compact dropdown instead of a system menu. Rows: each knowledge base (spine + 「N 份资料」),
/// then 「新建教室知识库」 under a divider. `save(nil)` = new classroom knowledge base, same as the old menu.
struct SaveToKnowledgeDropdown: View {
    @ObservedObject var store: Store
    var saved: Bool
    var save: (UUID?) -> Void
    @State private var open = false
    var body: some View {
        DropdownField(value: saved ? "已存入知识库" : "存入知识库", accessibilityName: "存入知识库", isOpen: open, compact: true) { DropdownGate.toggle($open) }
            .background(DropdownPanelAnchor(isPresented: $open, width: 240, items: items))
            .fixedSize()
    }
    private var items: [DropdownItem] {
        store.saved.libraries.map { library in
            DropdownItem(id: library.id.uuidString, title: library.name, detail: "\(library.documents.count) 份资料", spine: KnowledgeSpine.color(for: library.name)) { save(library.id) }
        } + [DropdownItem(id: "new-room-library", title: "新建教室知识库", dividerBefore: !store.saved.libraries.isEmpty) { save(nil) }]
    }
}

/// Side placement for card dropdowns (开始上课): pure geometry in screen coordinates (y up), unit-tested.
enum DropdownSidePlacement {
    /// Panel header 「检索知识库（可多选）」: 11pt line + 6 top + 4 bottom.
    static let headerHeight: CGFloat = 23
    /// - card: the card's frame. rowMidY: centre of the trigger row. firstRowCenter: panel top → centre of its first row.
    /// - Returns the panel frame (without shadow margin) and whether it sits on the left.
    /// Right by default; left when the right side would leave the visible frame; if neither fits, the roomier side
    /// (still outside the card). Vertically: first row level with the trigger, then shifted inward to stay visible.
    static func frame(card: CGRect, rowMidY: CGFloat, panelSize: CGSize, firstRowCenter: CGFloat, gap: CGFloat = 8, screen: CGRect) -> (frame: CGRect, left: Bool) {
        let rightX = card.maxX + gap, leftX = card.minX - gap - panelSize.width
        let left: Bool
        if screen.isInfinite || rightX + panelSize.width <= screen.maxX { left = false }
        else if leftX >= screen.minX { left = true }
        else { left = (card.minX - screen.minX) > (screen.maxX - card.maxX) }
        var top = rowMidY + firstRowCenter
        if !screen.isInfinite {
            if top - panelSize.height < screen.minY { top = screen.minY + panelSize.height }
            if top > screen.maxY { top = screen.maxY }
        }
        return (CGRect(x: left ? leftX : rightX, y: top - panelSize.height, width: panelSize.width, height: panelSize.height), left)
    }
}

/// Destructive confirm alerts put Return on 「取消」 (`.keyboardShortcut(.defaultAction)`), which takes Esc away from
/// the system sheet. This restores it: Esc in the sheet attached to this view's window cancels (same as 「取消」).
struct AlertEscapeCancels: NSViewRepresentable {
    var active: Bool
    var cancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let v = NSView(); context.coordinator.view = v; return v }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.cancel = cancel
        if active { context.coordinator.install() } else { context.coordinator.remove() }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var cancel: () -> Void = {}
        private var monitor: Any?
        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, let self, let sheet = self.view?.window?.attachedSheet, event.window === sheet else { return event }
                self.cancel()
                return nil
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

/// Trigger arrow for side panels: › or ‹, pointing at the side the panel opens on.
struct SideChevron: View {
    var left: Bool
    var color: Color = AppTheme.textSecondary
    var body: some View {
        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).hidden()   // same width as the old ⌃ chevron
            .overlay(Image(systemName: left ? "chevron.left" : "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(color))
            .accessibilityHidden(true)
    }
}

// MARK: - Trigger (settings): 32 high, r8, 1px border

struct DropdownField: View {
    /// Compact triggers show a secondary prefix (「类型」) and hug their content.
    var prefix: String? = nil
    var value: String
    var accessibilityName: String
    var isOpen: Bool
    var compact = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                if let prefix { Text(prefix).foregroundStyle(AppTheme.textSecondary) }
                Text(value).foregroundStyle(Color.primary).lineLimit(1).truncationMode(.tail)
                if !compact { Spacer(minLength: 0) }
                DropdownChevron(open: isOpen)
            }
            .font(.system(size: 13))
            .padding(.leading, compact ? 10 : 12).padding(.trailing, compact ? 8 : 10)
            .frame(height: 32)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .background(AppTheme.cardFill, in: shape)
            .overlay(shape.strokeBorder(isOpen ? AppTheme.accent : hovered && isEnabled ? Color.primary.opacity(0.25) : AppTheme.cardBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.easeOut(duration: 0.15), value: isOpen)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(value)
        .accessibilityHint("弹出选项列表")
    }
}

/// 11pt chevron.down in secondary ink; turns 180° while its panel is open.
struct DropdownChevron: View {
    var open: Bool
    var up = false
    var color: Color = AppTheme.textSecondary
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .rotationEffect(.degrees((open ? 180 : 0) + (up ? 180 : 0)))
            .animation(.easeOut(duration: 0.15), value: open)
            .accessibilityHidden(true)
    }
}
