import SwiftUI
import AssistantCore

struct SettingsView: View {
    @ObservedObject var store: Store
    private var page: String { store.settingsPage }
    @State private var petSearch = ""
    @State private var document: UUID?
    
    /// Collapsed sidebar (72pt, icons only) is remembered across launches; never collapses on its own.
    @AppStorage("settings.sidebarCollapsed") private var collapsed = false
    
    private let menus: [(String, String)] = [
        ("形象与风格", "person.crop.circle"),
        ("助教能力", "wand.and.stars"),
        ("知识库", "books.vertical"),
        ("教室", "studentdesk")
        // 连接与模型 (network): icon button next to the theme switch at the sidebar bottom
    ]
    
    var body: some View {
        HStack(spacing: 0) {
            // Modern macOS Sidebar: 200pt, or 72pt icons-only (the traffic lights still fit above).
            VStack(alignment: collapsed ? .center : .leading, spacing: 6) {
                // App Brand Header
                Group {
                    if collapsed {
                        VStack(spacing: 12) { logo; sidebarToggle }
                            .frame(maxWidth: .infinity)
                    } else {
                        HStack(spacing: 12) {
                            logo
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text("小保助教")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text("智能直播助教")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textHint)
                            }
                            .fixedSize()
                            Spacer(minLength: 0)
                            sidebarToggle
                        }
                        .padding(.leading, 10).padding(.trailing, 2)
                    }
                }
                .padding(.top, 36)
                .padding(.bottom, 14)
                // The whole brand strip (incl. the 36pt under the traffic lights) acts like a titlebar:
                // double-click = desktop maximize ⇄ restore. Buttons inside (sidebar toggle) keep their own clicks.
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    let w = (NSApp.currentEvent?.window ?? NSApp.keyWindow) as? SettingsWindow
                    w?.toggleMaximize()
                }
                
                // Navigation Items
                ForEach(menus, id: \.0) { item in
                    let isSelected = page == item.0
                    Button {
                        store.settingsPage = item.0
                        store.error = ""
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.1)
                                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                .frame(width: 20)
                                .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                            
                            if !collapsed {
                                Text(item.0)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                                    .fixedSize()
                                
                                Spacer()
                            }
                        }
                        .padding(.horizontal, collapsed ? 0 : 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: collapsed ? 40 : .infinity, minHeight: 40, alignment: collapsed ? .center : .leading)
                        .contentShape(Rectangle())
                        .background(
                            isSelected ? AppTheme.dyn(0x000000, 0xFFFFFF, 0.05, 0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(collapsed ? item.0 : "")
                    .accessibilityLabel(item.0)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                
                Spacer()
                SettingsFooter(store: store, vertical: collapsed)
                    .padding(.horizontal, 2).padding(.bottom, 2)
            }
            .padding(10)
            .frame(width: collapsed ? 72 : 200)
            .clipped()
            .background(AppTheme.sidebarFill)
            
            Rectangle().fill(AppTheme.columnLine).frame(width: 0.5)
            
            // Content Pane
            VStack(alignment: .leading, spacing: 0) {
                // Page Content
                if page == "形象与风格" {
                    assistant
                } else if page == "助教能力" {
                    CapabilitiesSettingsView(store: store)
                } else if page == "知识库" {
                    KnowledgeSettingsView(store: store)
                } else if page == "教室" {
                    CourseSettingsView(store: store)
                } else {
                    ModelSettingsView(store: store)
                }
                
                // Errors are posted into the bubble message stream (no banner here).
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppTheme.pageBackground)
        }
        .frame(minWidth: 840, minHeight: 620)
        .tint(AppTheme.accent)
        .onChange(of: store.saved.preferences.nickname) { _, _ in store.persist() }
        .onChange(of: store.saved.preferences.pet) { _, _ in store.persist() }
        .onChange(of: store.saved.preferences.style) { _, _ in store.persist() }
        .onChange(of: store.saved.preferences.appearance) { _, _ in store.persist(); store.applyAppearance() }
    }
    
    private var logo: some View {
        Group {
            if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1.5)
                    .accessibilityLabel("小保助教 Logo")
            }
        }
    }
    
    private var sidebarToggle: some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() } } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverSquareButtonStyle())
        .help(collapsed ? "展开侧栏" : "收起侧栏")
        .accessibilityLabel(collapsed ? "展开侧栏" : "收起侧栏")
    }
    
    // MARK: - 形象与风格 Tab
    
    private var assistant: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 形象选择
                VStack(alignment: .leading, spacing: 12) {
                    GroupTitle(text: "形象选择")
                    
                    ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(PetAppearance.all.filter { Bundle.module.url(forResource: $0.id, withExtension: "png") != nil }) { pet in
                            let isSelected = store.saved.preferences.pet == pet.id
                            Button { store.saved.preferences.pet = pet.id } label: {
                                VStack(spacing: 8) {
                                    ZStack(alignment: .topTrailing) {
                                        SpriteView(character: pet.id, action: .idle, animated: false)
                                            .frame(width: 120, height: 124)
                                        
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 15, weight: .bold))
                                                .foregroundStyle(AppTheme.accent)
                                                .background(Circle().fill(.white).padding(1))
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                                    
                                    VStack(spacing: 3) {
                                        Text(pet.name)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                                            .lineLimit(1)
                                        Text(pet.style)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 10)
                                .padding(.bottom, 12)
                                .frame(width: 148)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isSelected ? AppTheme.brand50 : AppTheme.cardFill)
                                )
                                .overlay {
                                    if isSelected { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.accent, lineWidth: 2) }
                                }
                                .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 1)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(pet.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 2).padding(.vertical, 6)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.trailing, 60, for: .scrollContent)
                    .modifier(WheelScrollsHorizontally())   // only while hovered: vertical wheel → horizontal
                    .onAppear { DispatchQueue.main.async { reader.scrollTo(store.saved.preferences.pet, anchor: .leading) } }
                    }
                }

                // 人设配置 Card
                VStack(alignment: .leading, spacing: 8) {
                GroupTitle(text: "助教人设")
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("助教昵称")
                            .font(.system(size: 13, weight: .medium))
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textHint)
                            TextField("如：小保", text: $store.saved.preferences.nickname)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("在直播间回复学员提问时展示的昵称")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textHint)
                    }
                    
                    RowDivider(leading: 0)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("助教风格").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(store.saved.preferences.style.count)/2000")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(AppTheme.textHint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.04), in: Capsule())
                        }
                        // Multi-line editor: ~5 lines visible, grows to ~10 then scrolls; up to 2000 characters.
                        TextEditor(text: Binding(get: { store.saved.preferences.style },
                                                 set: { store.saved.preferences.style = String($0.prefix(2000)) }))
                            .font(.system(size: 13)).scrollContentBackground(.hidden).padding(8)
                            .frame(minHeight: 96, maxHeight: 190)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.inputFill))
                        
                        // 预设快捷标签
                        HStack(spacing: 8) {
                            Text("预设风格：")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textHint)
                            ForEach([
                                ("简洁清晰", "回答尽量一两句，用短句，不铺垫。", "bolt.fill"),
                                ("亲和热情", "语气温和，可以先接住对方的问题再回答，但不堆语气词和感叹号。", "heart.fill"),
                                ("启发引导", "遇到学员提问，先给一个提示或反问引导思考，再给答案。", "lightbulb.fill")
                            ], id: \.0) { style in
                                Button {
                                    store.saved.preferences.style = style.1
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: style.2)
                                            .font(.system(size: 11))
                                        Text(style.0)
                                            .font(.system(size: 11))
                                    }
                                }
                                .buttonStyle(PromptCapsuleStyle(fontSize: 11, horizontalPadding: 9, height: 24))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .settingsCard()
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    private var general: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("外观", systemImage: "circle.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.textSecondary)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("主题").font(.system(size: 13, weight: .medium))
                        Text("适用于桌宠形象、悬浮卡片和设置窗口").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $store.saved.preferences.appearance) {
                        Text("跟随系统").tag("system")
                        Text("亮色").tag("light")
                        Text("暗色").tag("dark")
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 240)
                }
                .settingsCard()
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 32)
        }
    }
}


/// While the pointer is over the modified view, a mostly-vertical scroll-wheel event is rewritten as a horizontal one,
/// so a plain mouse wheel scrolls a horizontal row. Trackpad horizontal swipes (|dx| ≥ |dy|) pass through untouched;
/// outside the view nothing changes, so the window scrolls vertically as usual.
struct WheelScrollsHorizontally: ViewModifier {
    @State private var monitor: Any?
    @State private var dragMonitor: Any?
    func body(content: Content) -> some View {
        content
            .onHover { inside in if inside { install(); installDrag() } else { remove() } }
            .onDisappear { remove() }
    }
    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let cg = event.cgEvent?.copy() else { return event }
            for (v, h) in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventDeltaAxis2),
                           (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
                           (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2)] {
                cg.setDoubleValueField(h, value: cg.getDoubleValueField(v))
                cg.setDoubleValueField(v, value: 0)
            }
            return NSEvent(cgEvent: cg) ?? event
        }
    }
    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if let dragMonitor, !DragScroll.shared.active { NSEvent.removeMonitor(dragMonitor); self.dragMonitor = nil }
    }
    /// Click-and-drag scrolling: past a 4pt threshold the row scrolls with the pointer and the click is cancelled;
    /// a short click without movement reaches the avatar button as usual.
    private func installDrag() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            DragScroll.shared.handle(event)
        }
    }

}

@MainActor final class DragScroll {
    static let shared = DragScroll()
    private var origin: NSPoint?, startX: CGFloat = 0
    private weak var scroll: NSScrollView?
    private(set) var active = false
    func handle(_ e: NSEvent) -> NSEvent? {
        switch e.type {
        case .leftMouseDown:
            guard let view = e.window?.contentView?.hitTest(e.locationInWindow) else { return e }
            var v: NSView? = view; var found: NSScrollView?
            while let cur = v { if let sv = cur as? NSScrollView, sv.documentView.map({ $0.frame.width > sv.contentSize.width + 1 }) == true { found = sv; break }; v = cur.superview }
            scroll = found; origin = found == nil ? nil : e.locationInWindow; startX = found?.contentView.bounds.origin.x ?? 0; active = false
            return e
        case .leftMouseDragged:
            guard let origin, let scroll else { return e }
            let dx = e.locationInWindow.x - origin.x
            if !active && abs(dx) < 4 { return e }
            active = true
            let maxX = max(0, (scroll.documentView?.frame.width ?? 0) - scroll.contentSize.width)
            scroll.contentView.scroll(to: NSPoint(x: min(maxX, max(0, startX - dx)), y: scroll.contentView.bounds.origin.y))
            scroll.reflectScrolledClipView(scroll.contentView)
            return nil
        case .leftMouseUp:
            defer { origin = nil; scroll = nil; active = false }
            guard active else { return e }
            // Cancel the pending button click: release far outside any control.
            return NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: e.modifierFlags,
                                      timestamp: e.timestamp, windowNumber: e.windowNumber, context: nil, eventNumber: e.eventNumber, clickCount: 1, pressure: 0)
        default: return e
        }
    }
}


/// Sidebar toggle: transparent at rest, 4% on hover, 8% pressed (r8).
struct HoverSquareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }
    private struct Label: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(configuration.isPressed ? 0.08 : hovered ? 0.04 : 0)))
                .onHover { hovered = $0 }
        }
    }
}
