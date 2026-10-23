import SwiftUI
import AppKit
import AssistantCore

let accent = AppTheme.accent

struct BubbleGlass: ViewModifier {
    func body(content: Content) -> some View {
        content.glassCard(cornerRadius: 18)
    }
}

struct SpriteView: NSViewRepresentable {
    var character: String
    var action: PetAction
    var animated = true
    var draggable = false
    var onClick: (() -> Void)?
    var menuItems: (() -> [PetMenuItem])? = nil
    func makeNSView(context: Context) -> SpriteCanvas { SpriteCanvas() }
    func updateNSView(_ view: SpriteCanvas, context: Context) {
        view.animated = animated
        view.draggable = draggable
        view.onClick = onClick
        view.menuItems = menuItems
        view.set(character: character, action: action)
    }
}
final class SpriteCanvas: NSView {
    private static var frameCache: [String: [[NSImage]]] = [:]
    private var frames: [[NSImage]] = []
    private var previewImage: NSImage?
    var animated = true
    private var character = ""
    private var row = 0
    private var frameIndex = 0
    private var blinkFrame = 2
    private var tick = 0
    private var timer: Timer?
    var draggable = false
    var onClick: (() -> Void)?
    private var dragAnchor: NSPoint?
    private var windowAnchor: NSPoint?
    private var isDragging = false
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { draggable }
    override func resetCursorRects() {
        if draggable { addCursorRect(bounds, cursor: .openHand) }
    }
    // Pet panel is non-key, so cursor rects alone don't fire: an always-active tracking area sets the hand cursor.
    private var hoverArea: NSTrackingArea?
    private var hovering = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        guard draggable else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; if dragAnchor == nil { NSCursor.openHand.set() } }
    override func mouseMoved(with event: NSEvent) { if dragAnchor == nil { NSCursor.openHand.set() } }
    override func cursorUpdate(with event: NSEvent) { if draggable { (dragAnchor == nil ? NSCursor.openHand : NSCursor.closedHand).set() } else { super.cursorUpdate(with: event) } }
    override func mouseExited(with event: NSEvent) { hovering = false; if dragAnchor == nil { NSCursor.arrow.set() } }
    var menuItems: (() -> [PetMenuItem])?
    /// Right-click on the sprite: native NSMenu (left-click/drag handling above is untouched).
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let items = menuItems?(), !items.isEmpty else { return super.menu(for: event) }
        return PetMenuItem.menu(items)
    }
    override func mouseDown(with event: NSEvent) {
        guard draggable, let window else { super.mouseDown(with: event); return }
        dragAnchor = window.convertPoint(toScreen: event.locationInWindow)
        windowAnchor = window.frame.origin
        isDragging = false
        NSCursor.closedHand.set()
    }
    override func mouseDragged(with event: NSEvent) {
        guard draggable, let window, let dragAnchor, let windowAnchor else { return }
        let pointer = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(x: pointer.x - dragAnchor.x, y: pointer.y - dragAnchor.y)
        guard isDragging || hypot(delta.x, delta.y) >= 4 else { return }
        isDragging = true
        NSCursor.closedHand.set()
        window.setFrameOrigin(NSPoint(x: windowAnchor.x + delta.x, y: windowAnchor.y + delta.y))
    }
    override func mouseUp(with event: NSEvent) {
        guard draggable, dragAnchor != nil else { return }
        let clicked = !isDragging
        dragAnchor = nil; windowAnchor = nil; isDragging = false
        (hovering ? NSCursor.openHand : NSCursor.arrow).set()
        if clicked { onClick?() }
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self, self.animated, !self.isDragging else { return }
            self.tick += 1
            let next: Int
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { next = self.row == 0 ? 0 : 1 }
            else {
                switch self.row {
                case 0: next = self.tick % 24 == 20 ? self.blinkFrame : 0
                case 1: next = self.tick % 18 == 16 ? 2 : 1
                case 2: next = self.tick % 22 == 19 ? 3 : 1
                case 3: next = [0, 1, 2, 1][(self.tick / 2) % 4]
                case 4: next = [1, 1, 2, 3][(self.tick / 4) % 4]
                case 5: next = self.tick < 10 ? [1, 2][(self.tick / 3) % 2] : 0
                case 6: next = self.tick < 10 ? [1, 2][(self.tick / 3) % 2] : 0
                case 7: next = self.tick < 10 ? 3 : 0
                default: next = 0
                }
            }
            if next != self.frameIndex { self.frameIndex = next; self.needsDisplay = true }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }
    func set(character: String, action: PetAction) {
        if self.character != character {
            self.character = character
            blinkFrame = PetAppearance.all.first { $0.id == character }?.blinkFrame ?? 2
            if !animated, let url = Bundle.module.url(forResource: character, withExtension: "png"), let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let first = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width / 4, height: cg.height / 8)) {
                // Centre by opaque content: sheets have uneven transparent padding, so translate the
                // alpha bounding box to the middle of the square (scale unchanged, so sizes stay comparable).
                let side: CGFloat = 224, scale = side / CGFloat(max(first.width, first.height))
                let box = Self.opaqueBounds(first)
                let drawW = CGFloat(first.width) * scale, drawH = CGFloat(first.height) * scale
                let dx = side / 2 - (box.midX * scale), dy = side / 2 - ((CGFloat(first.height) - box.midY) * scale)
                let thumbnail = NSImage(size: NSSize(width: side, height: side))
                thumbnail.lockFocus()
                NSImage(cgImage: first, size: NSSize(width: drawW, height: drawH)).draw(in: NSRect(x: dx, y: dy, width: drawW, height: drawH))
                thumbnail.unlockFocus()
                previewImage = thumbnail
            } else if let cached = Self.frameCache[character] { frames = cached }
            else if let url = Bundle.module.url(forResource: character, withExtension: "png"), let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                frames = Self.slice(cg); if Self.frameCache.count >= 3 { Self.frameCache.removeAll() }; Self.frameCache[character] = frames
            }
        }
        if row != action.rawValue { row = action.rawValue; tick = 0; frameIndex = row == 0 ? 0 : 1 }; needsDisplay = true
    }
    /// Bounding box (image pixel coords, origin top-left) of pixels with alpha > 24.
    static func opaqueBounds(_ img: CGImage) -> CGRect {
        let w = img.width, h = img.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h { for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 24 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: w, height: h) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
    // Frames remain original pixels. Drawing aligns feet, avoiding sprite-sheet registration jitter.
    /// Row boundaries snapped to the emptiest scanline near each nominal grid line, so heads that poke above a cell aren't cut off.
    private static func rowCuts(_ sheet: CGImage) -> [Int] {
        let w = sheet.width, h = sheet.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(sheet, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var ink = [Int](repeating: 0, count: h)
        for py in 0..<h { var sum = 0; var px = 0; while px < w { if bytes[(py * w + px) * 4 + 3] > 24 { sum += 1 }; px += 2 }; ink[py] = sum }
        let cell = Double(h) / 8, reach = Int(cell * 0.18)
        var cuts = [0]
        for i in 1..<8 {
            let nominal = Int((Double(i) * cell).rounded())
            var best = nominal
            for py in max(1, nominal - reach)...min(h - 2, nominal + reach) where ink[py] < ink[best] || (ink[py] == ink[best] && abs(py - nominal) < abs(best - nominal)) { best = py }
            cuts.append(best)
        }
        cuts.append(h)
        return cuts
    }
    private static func slice(_ sheet: CGImage) -> [[NSImage]] {
        let cuts = rowCuts(sheet)
        return (0..<8).map { row in (0..<4).map { column in
            let x = Int((Double(column) * Double(sheet.width) / 4).rounded())
            let right = Int((Double(column + 1) * Double(sheet.width) / 4).rounded())
            let y = cuts[row]
            let bottom = cuts[row + 1]
            guard let crop = sheet.cropping(to: CGRect(x: x, y: y, width: right - x, height: bottom - y)) else { return NSImage() }
            let width = crop.width, height = crop.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            var left = width, last = 0, foot = 0, top = height
            bytes.withUnsafeMutableBytes { pointer in
                guard let context = CGContext(data: pointer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            for py in 0..<height {
                for px in (width / 4)..<(width * 3 / 4) where bytes[(py * width + px) * 4 + 3] > 210 {
                    top = min(top, py); foot = max(foot, py)
                    if py > height * 4 / 5 { left = min(left, px); last = max(last, px) }
                }
            }
            let center = left < last ? Double(left + last) / 2 : Double(width) / 2
            let scale = 204.0 / Double(max(1, foot - top))
            let canvas = NSImage(size: NSSize(width: 224, height: 224))
            canvas.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            NSImage(cgImage: crop, size: NSSize(width: width, height: height)).draw(in: NSRect(x: 112 - center * scale, y: 10 - Double(height - 1 - foot) * scale, width: Double(width) * scale, height: Double(height) * scale), from: .zero, operation: .sourceOver, fraction: 1)
            canvas.unlockFocus()
            return canvas
        } }
    }
    override func draw(_ dirtyRect: NSRect) {
        if !animated, let previewImage { previewImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1); return }
        guard frames.count == 8 else { return }
        frames[row][frameIndex].draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

struct PetView: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    var settings: () -> Void
    var courses: () -> Void
    var start: () -> Void
    var command: () -> Void
    /// Once per app launch (in memory only, not persisted).
    @Environment(\.colorScheme) private var scheme
    var dark: Bool { scheme == .dark }
    static let controlHeight: CGFloat = 32
    static let windowWidth: CGFloat = 290
    static let windowInset: CGFloat = (windowWidth - 190) / 2
    /// Set to false to end class with one click (no confirmation).
    static let confirmEndClass = true
    @State private var hoverLabel: String?
    @State private var hoverTask: Task<Void, Never>?
    @State private var badgePop: CGFloat = 1
    @Namespace var toolbarSpace
    @State var startHovered = false
    var inClass: Bool { store.connected || (store.demo && !CommandLine.arguments.contains("--preview-before-class")) }   // dev flag: screenshot the pre-class toolbar
    var connecting: Bool { store.status == "连接中" && !store.connected }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                SpriteView(character: store.saved.preferences.pet, action: voice.active ? .listening : store.action, draggable: true, menuItems: { menuItems })
                    .frame(width: 164, height: 164)
                    .help("按住人物拖动")
            }
            toolbar
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 6)
        }
        .frame(width: Self.windowWidth, height: 216)
        .contentShape(Rectangle())
        // Right-click anywhere on the pet or capsule: the same NSMenu, built at click time.
        .overlay(RightClickMenuArea(items: { menuItems }))
        .tint(accent)
    }

    /// Custom hover label above the icon, shown after 0.3s (no system tooltip).
    func hover(_ on: Bool, _ id: String) {
        hoverTask?.cancel()
        guard on else { if hoverLabel == id { withAnimation(.easeOut(duration: 0.12)) { hoverLabel = nil } }; return }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { hoverLabel = id }
        }
    }
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    var messagesExpanded: Bool { store.detailExpanded || (!store.messagesHidden && !store.messages.isEmpty) }
    /// Same count the old collapsed 「待处理 N」 bubble showed (store.messages.count), now on this button.
    var badgeCount: Int { messagesExpanded ? 0 : store.badgeCount }

    /// State-dependent toolbar. Before class: one 「开始上课」 accent capsule. In class: the same capsule
    /// springs into a glass 「对助教说」 capsule (no 下课 here; it lives top-right of the bubble / big card).
    var toolbar: some View {
        Group {
            if inClass { talkCapsule } else { startCapsule }
        }
        .animation(Self.spring, value: inClass)
        .animation(Self.spring, value: voice.active)
    }
    /// Before class: frosted-glass "water drop" capsule with a travelling specular rim and a soft glow underneath.
    var startCapsule: some View {
        Button { start() } label: {
            HStack(spacing: 6) {
                if connecting { ProgressView().controlSize(.small) } else { Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)) }
                Text(connecting ? "连接中…" : "开始上课").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(AppTheme.dyn(0x2469F3, 0x7AA7FA))
            .padding(.horizontal, 22).frame(height: 44)
            .modifier(WaterDropGlass(hovered: startHovered))
            .matchedGeometryEffect(id: "toolbarCapsule", in: toolbarSpace)
            .contentShape(Capsule())
        }
        .buttonStyle(WaterDropPress())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { startHovered = h } }
        .disabled(connecting)
        .help("开始上课")
    }
    var talkCapsule: some View {
        let holding = voice.active
        if !store.hasModel {   // no model: guide to 设置 › 连接与模型 instead of greying out
            return AnyView(Button { store.settingsPage = "连接与模型"; settings() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.accent)
                    Text("先配置模型").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
                }
                .padding(.horizontal, 22).frame(height: 44)
                .modifier(WaterDropGlass(animated: false))
                .matchedGeometryEffect(id: "toolbarCapsule", in: toolbarSpace)
                .contentShape(Capsule())
            }.buttonStyle(WaterDropPress()).help("先配置模型"))
        }
        return AnyView(Button { command() } label: {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.accent)
                if holding { WaveformVisualizer(active: voice.phase == "正在录音", barCount: 3, color: AppTheme.accent).frame(width: 14, height: 12) }
                Text(holding ? (voice.phase == "正在录音" ? "正在听" : voice.phase) : "对助教说").font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary)
            }
            .padding(.horizontal, 22).frame(height: 44)
            .background(Capsule().fill(AppTheme.accent.opacity(holding ? 0.12 : 0)))
            .modifier(WaterDropGlass(animated: false))
            .matchedGeometryEffect(id: "toolbarCapsule", in: toolbarSpace)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.busy || !store.canTalkToAssistant || (holding && voice.phase != "正在录音"))
        .help("对助教说"))
    }
    func iconButton(_ symbol: String, id: String, size: CGFloat = 13, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(selected ? Color.primary : Color.secondary)
                .shadow(color: .black.opacity(0.12), radius: 1)
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background(
                    Circle().fill(
                        selected ? Color.white.opacity(dark ? 0.22 : 0.6) :
                        (hoverLabel == id ? Color.white.opacity(dark ? 0.14 : 0.3) : Color.clear)
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        selected ? Color.white.opacity(0.3) : Color.clear,
                        lineWidth: 0.75
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover($0, id) }
        .overlay(alignment: .top) { hoverTip(id) }
    }
    @ViewBuilder func hoverTip(_ id: String) -> some View {
        if hoverLabel == id {
            Text(id)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dark ? Color.white : Color.primary)
                .padding(.horizontal, 9).padding(.vertical, 4.5)
                .background(Capsule().fill(DetailBoard.tint))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .fixedSize()
                .offset(y: -36)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
    /// 对助教说 (voice): mic icon; widens into 「正在听」 while listening.
    @ViewBuilder var talkButton: some View {
        if voice.active {
            Button { command() } label: {
                HStack(spacing: 6) {
                    WaveformVisualizer(active: voice.phase == "正在录音", barCount: 3, color: .white)
                    Text(voice.phase == "正在录音" ? "正在听" : voice.phase)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .frame(height: Self.controlHeight)
                .background(Capsule().fill(Color.red))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.busy || voice.phase != "正在录音")
            .transition(.opacity)
        } else {
            iconButton("mic.fill", id: store.canTalkToAssistant ? "对助教说" : "请先上课", action: command)
                .disabled(store.busy || !store.canTalkToAssistant)
                .help(store.canTalkToAssistant ? "对助教说" : "请先上课")
                .opacity(store.canTalkToAssistant ? 1 : 0.35)
        }
    }
    /// Neutral liquid glass control; the stop symbol alone carries the in-class warning color.
    var classButton: some View {
        Button {
            if inClass {
                endClass()
            } else {
                start()
            }
        } label: {
            Group {
                if connecting {
                    ProgressView().controlSize(.small).tint(.secondary)
                } else if inClass {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(inClass ? AppTheme.stopRed : Color.primary)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(inClass ? Color.red : Color.primary)
                        .offset(x: 1)
                }
            }
            .frame(width: Self.controlHeight, height: Self.controlHeight)
            .modifier(PetGlass(shape: Circle()))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(connecting && !inClass)
        .onHover { hover($0, inClass ? "结束上课" : connecting ? "连接中…" : "开始上课") }
        .overlay(alignment: .top) { hoverTip(hoverLabel == "结束上课" || hoverLabel == "连接中…" || hoverLabel == "开始上课" ? hoverLabel! : "") }
    }
    func endClass() {
        hoverTask?.cancel(); hoverLabel = nil
        LiveSessionControl.confirmEndClass(store: store)
    }
    /// Always HH:MM:SS.
    static func elapsed(from start: Date, to now: Date) -> String {
        let t = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
    }
    /// Built when the menu opens, so the Option key state is read at that moment.
    var menuItems: [PetMenuItem] {
        PetMenuItem.items(settings: settings, quit: { NSApp.terminate(nil) })
    }
}

/// Shared helper to confirm and end class from cards or pet toolbar.
enum LiveSessionControl {
    @MainActor
    static func confirmEndClass(store: Store) {
        if PetView.confirmEndClass {
            let alert = endClassAlert()
            let cancel = alert.buttons[0]
            let esc = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.window === alert.window else { return event }
                cancel.performClick(nil); return nil
            }
            let response = alert.runModal()
            if let esc { NSEvent.removeMonitor(esc) }
            guard response == .alertSecondButtonReturn else { return }
        }
        store.stop()
    }
    /// 「下课」 confirmation. Every caller sits on an always-dark surface (pet, bubble, 工作台 card),
    /// so the alert is forced dark too — no white box over the dark bubble, whatever the theme setting.
    @MainActor
    static func endClassAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "结束这节课？"
        alert.informativeText = "结束上课后将保存本节课记录并停止监听直播间消息。"
        // D8: 取消 is the default (Return) and Esc cancels; 结束上课 is red and has no key equivalent.
        let cancel = alert.addButton(withTitle: "取消")
        let end = alert.addButton(withTitle: "结束上课")
        cancel.keyEquivalent = "\r"
        end.keyEquivalent = ""
        end.hasDestructiveAction = true
        alert.alertStyle = .warning
        alert.window.appearance = NSAppearance(named: .darkAqua)
        return alert
    }
}

/// Live streaming red timer pill with pulsing dot, elapsed time, and quick "下课" button.
/// Positioned at the top of floating cards (CollapsedPendingBubble & DetailBoard).
struct LiveTimerPill: View {
    @ObservedObject var store: Store
    @State private var breathe = false
    @State private var hovering = false
    
    var body: some View {
        Button {
            LiveSessionControl.confirmEndClass(store: store)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .opacity(breathe ? 0.35 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: breathe)
                
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(PetView.elapsed(from: store.liveStart ?? context.date, to: context.date))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                
                Rectangle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 0.75, height: 8.5)
                    .padding(.horizontal, 1)
                
                Text("下课")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            .padding(.horizontal, 6.5)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: hovering
                                ? [AppTheme.liveEndTopHover, AppTheme.liveEndBottomHover]
                                : [AppTheme.liveEndTop, AppTheme.liveEndBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.75)
            )
            .shadow(color: Color.red.opacity(hovering ? 0.32 : 0.18), radius: hovering ? 4 : 2.5, y: 1)
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onAppear { breathe = true }
        .help("点击结束本节课")
        .fixedSize()
    }
}

/// Transparent layer that only claims right-clicks / control-clicks, so left-click and drag
/// still reach the sprite and the 对助教说 button underneath.
struct RightClickMenuArea: NSViewRepresentable {
    var items: () -> [PetMenuItem]
    func makeNSView(context: Context) -> RightClickView { RightClickView() }
    func updateNSView(_ view: RightClickView, context: Context) { view.items = items }
}
final class RightClickView: NSView {
    var items: (() -> [PetMenuItem])?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        let right = event.type == .rightMouseDown || event.type == .rightMouseUp
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        return right ? super.hitTest(point) : nil
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let items = items?(), !items.isEmpty else { return nil }
        return PetMenuItem.menu(items)
    }
    override func mouseDown(with event: NSEvent) {   // control-click
        if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

/// Play circle ⇄ red timer capsule share one glass identity so the system morphs them (macOS 26);
/// matchedGeometryEffect + material on older systems.
struct ClassMorph: ViewModifier {
    var color: Color
    var namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Solid fill under clear glass: the accent/red stays saturated even when the app isn't active.
            content.background(Capsule().fill(color)).glassEffect(.clear.interactive(), in: Capsule()).glassEffectID("classButton", in: namespace)
        } else {
            content.background(Capsule().fill(color)).matchedGeometryEffect(id: "classButton", in: namespace)
        }
    }
}

struct PetMenuItem {
    var title: String; var action: (() -> Void)?
    init(_ title: String, _ action: @escaping () -> Void) { self.title = title; self.action = action }
    private init() { title = ""; action = nil }
    static let separator = PetMenuItem()
    /// (1) 开始上课 or 结束上课, never both; 交互预览 only with Option held. (2) 设置, 课程沉淀. (3) 退出.
    static func items(settings: @escaping () -> Void = {}, quit: @escaping () -> Void) -> [PetMenuItem] {
        [.init("设置", settings), .init("退出", quit)]
    }
    var isSeparator: Bool { action == nil }
    static func menu(_ items: [PetMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)   // the pet is always dark, so is its right-click menu
        for item in items {
            guard let action = item.action else { menu.addItem(.separator()); continue }
            let entry = ClosureMenuItem(title: item.title, action: action)
            menu.addItem(entry)
        }
        return menu
    }
}
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// Pet controls: lighter, clearer glass than the cards (no window-background tint, which
/// rendered as an opaque gray slab over dark wallpapers).
/// Opaque, appearance-following fill: clear glass over the transparent pet window rendered as a black block in captures.
struct PetGlass<S: Shape>: ViewModifier {
    var shape: S
    func body(content: Content) -> some View {
        content.background(shape.fill(AppTheme.dyn(0x000000, 0xFFFFFF, 0.05, 0.10)))
    }
}

/// Toolbar capsule: clear "watery" glass, gradient highlight rim, layered depth shadow.
struct ToolbarGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(AppTheme.dyn(0xFFFFFF, 0x2C2C2E, 0.94, 0.94)))
            .overlay(Capsule().strokeBorder(AppTheme.dyn(0x000000, 0xFFFFFF, 0.06, 0.08), lineWidth: 0.5).allowsHitTesting(false))
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
    }
}

struct BubblesView: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    @Namespace private var glassSpace
    /// Lags `store.detailExpanded` by one runloop turn on expand, so the window has already grown (bottom-right fixed)
    /// before the card grows inside it; on collapse it flips first and the window shrinks after the animation.
    @State private var boardShown = false
    @State private var bubbleContent: Double = 1
    @State private var boardContent: Double = 1
    static let expandAnimation = Animation.easeOut(duration: 0.25)
    /// Content never overlaps: the leaving card's content fades out in the first 0.1s, the arriving one fades in over the next 0.15s.
    static let contentOut = Animation.easeOut(duration: 0.1)
    static let contentIn = Animation.easeOut(duration: 0.15)   // arriving content starts fading in immediately (blank start ≤ 2 frames)
    /// The bubble only appears once the shrinking card has finished, so the two surfaces never overlap.
    static let bubbleArrive = Animation.easeOut(duration: 0.04).delay(0.25)
    private func setBoard(_ on: Bool) {
        guard on != boardShown else { return }
        if on {
            boardContent = 0
            withAnimation(Self.contentOut) { bubbleContent = 0 }
            withAnimation(Self.expandAnimation) { boardShown = true }
            withAnimation(Self.contentIn) { boardContent = 1 }
        } else {
            bubbleContent = 0
            withAnimation(Self.contentOut) { boardContent = 0 }
            withAnimation(Self.expandAnimation) { boardShown = false }
            withAnimation(Self.contentIn) { bubbleContent = 1 }
        }
    }
    @ViewBuilder private var noticeBubble: some View {
        if !store.notice.isEmpty {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent.opacity(0.15))
                        .frame(width: 20, height: 20)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.accent)
                }
                Text(store.notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.primary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 5)
            .background(Capsule().fill(DetailBoard.tint))
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
            )
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
            .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {

            GlassGroup(spacing: 20) {
                if store.showLessonCards && boardShown {
                    DetailBoard(store: store, glassSpace: glassSpace).environment(\.cardContentOpacity, boardContent).modifier(BubbleGrowTransition(width: store.detailBoardWidth))
                }
                else if store.showLessonCards {
                    CollapsedPendingBubble(store: store, glassSpace: glassSpace).environment(\.cardContentOpacity, bubbleContent)
                        // One shape at a time: on expand the bubble leaves at once (the card grows from its tail tip);
                        // on collapse it appears only after the card has shrunk back.
                        .transition(.asymmetric(insertion: .opacity.animation(Self.bubbleArrive), removal: .identity))
                }
            }
            
            // 对助教说 lives inside the bubble / big card (one card only).
        }
        .padding(22)
        .sheet(item: $store.viewedMessage) { message in
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(alignment: .center, spacing: 8) {
                    CategoryBadge(kind: message.kind)
                    Text(message.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(PendingBoard.hm.string(from: message.time))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(AppTheme.textHint)
                    Button {
                        store.viewedMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("关闭 (Esc)")
                }
                
                // People who asked (if any)
                if !message.people.isEmpty {
                    let names = message.people.sorted()
                    HStack(spacing: 6) {
                        HStack(spacing: -6) {
                            ForEach(Array(names.prefix(4)), id: \.self) { n in
                                ViewerAvatar(name: n, url: store.avatars[n])
                            }
                        }
                        Text(names.prefix(4).joined(separator: "、") + (names.count > 4 ? " 等 \(names.count) 人" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 2)
                }
                
                // Question / Content Box
                ScrollView {
                    Text(message.question)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.cardBorder, lineWidth: 0.75)
                )
                
                // AI Draft (if any)
                if !message.draft.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("参考回复：")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Ink.accent)
                            Text(message.draft)
                                .font(.system(size: 13))
                                .foregroundStyle(Ink.secondary)
                                .lineLimit(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                
                // Footer
                HStack {
                    Spacer()
                    if message.responseType == .reply {
                        Button("回复") {
                            let id = message.id
                            store.viewedMessage = nil
                            store.open(id)
                        }
                        .buttonStyle(ModernPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 6))
                    }
                    Button("关闭") {
                        store.viewedMessage = nil
                    }
                    .buttonStyle(ModernSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 6))
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(18)
            .frame(width: 420, height: 320)
        }
        .onHover { store.cardsHovered = $0 }
        .frame(width: boardShown ? nil : 324)
        .frame(maxWidth: boardShown ? .infinity : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)   // grows from the bottom-right (the tail corner)
        .tint(accent)
        .environment(\.assistantPet, store.saved.preferences.pet)
        .onAppear { boardShown = store.detailExpanded }
        .onChange(of: store.detailExpanded) { _, on in
            if on { DispatchQueue.main.async { setBoard(store.detailExpanded) } }   // after the window has grown
            else { setBoard(false) }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.pendingCollapsed)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.messages.map(\.id))
    }
}

struct ActionCard: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    var close: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let id = store.selected, let index = store.messages.firstIndex(where: { $0.id == id }) {
                let message = store.messages[index]
                contentView(id: id, message: message)
            } else {
                completedView
            }
        }
        .padding(22)
        .frame(width: 410)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DetailBoard.tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        // The panel has the system window shadow (follows the r18 alpha edge); a SwiftUI shadow here doubled it and was clipped at the panel edge.
        .tint(accent)
        .onExitCommand(perform: close)
    }
    
    @ViewBuilder
    private func contentView(id: UUID, message: PendingMessage) -> some View {
        headerView(message: message)
        questionCalloutView(message: message)
        
        if let attachment = message.attachment {
            attachmentPreview(attachment: attachment)
        }
        
        if message.kind != .risk && message.kind != .material {
            draftEditor(id: id, message: message)
        }
        
        if voice.active {
            voiceBanner
        }
        
        errorSection(message: message)
        bottomToolbar(id: id, message: message)
    }
    
    @ViewBuilder
    private func headerView(message: PendingMessage) -> some View {
        HStack(alignment: .center) {
            CategoryBadge(kind: message.kind)
            if !message.people.isEmpty {
                Text(message.people.sorted().joined(separator: "、"))
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("收起卡片 (Esc)")
        }
    }
    
    @ViewBuilder
    private func questionCalloutView(message: PendingMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.question)
                .font(.system(size: 15, weight: .medium))
                .lineSpacing(3.5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Ink.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.color(for: message.kind).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppTheme.color(for: message.kind).opacity(0.22), lineWidth: 0.75)
        )
    }
    
    @ViewBuilder
    private func attachmentPreview(attachment: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(attachment.lastPathComponent, systemImage: "doc.richtext")
                .font(.system(size: 13, weight: .medium))
            if let image = NSImage(contentsOf: attachment) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
            }
            Button("打开预览") {
                NSWorkspace.shared.open(attachment)
            }
            .controlSize(.small)
        }
        .padding(12)
    }
    
    @ViewBuilder
    private func draftEditor(id: UUID, message: PendingMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(get: {
                    store.messages.first { $0.id == id }?.draft ?? ""
                }, set: { value in
                    if let i = store.messages.firstIndex(where: { $0.id == id }) {
                        store.messages[i].draft = value
                    }
                }))
                .font(.system(size: 13))
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 120)
                
                if message.draft.isEmpty {
                    Text("输入回答，或点击左下方麦克风口述…")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textHint)
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(AppTheme.cardBorder, lineWidth: 0.75)
            )
            
            if !message.source.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "text.book.closed.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.accent)
                    Text("参考资料：\(message.source)")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }
    
    @ViewBuilder
    private var voiceBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                WaveformVisualizer(active: true, barCount: 4, color: AppTheme.accent)
                Text(voice.phase)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                Spacer()
                Button("取消") {
                    store.cancelCommandVoice()
                }
                .buttonStyle(ModernSecondaryButtonStyle(horizontalPadding: 10, verticalPadding: 4))
            }
            if !voice.transcript.isEmpty {
                Text(voice.transcript)
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.secondary)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(AppTheme.accent.opacity(0.2), lineWidth: 0.75)
        )
    }
    
    @ViewBuilder
    private func errorSection(message: PendingMessage) -> some View {
        if !message.error.isEmpty {
            Text(message.error)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
                .textSelection(.enabled)
        }
        if !store.error.isEmpty {
            Text(store.error)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.danger)
        }
    }
    
    @ViewBuilder
    private func bottomToolbar(id: UUID, message: PendingMessage) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if message.kind != .risk && message.kind != .material {
                Button {
                    store.startVoice(question: id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: voice.active ? "stop.fill" : "mic.fill")
                            .font(.system(size: 11))
                        Text(voice.active ? "停止" : "口述")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(QuietFillButtonStyle())
                .disabled(message.busy || (voice.active && voice.phase != "正在录音"))
            }
            
            Spacer()
            
            if !store.demo && store.connected {
                Text("频道 \(store.channel)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textHint)
            }
            
            Button("忽略") {
                store.ignore(id)
                close()
            }
            .buttonStyle(QuietFillButtonStyle())
            .disabled(message.busy)
            
            if message.kind != .risk {
                Button {
                    store.send(id)
                } label: {
                    HStack(spacing: 5) {
                        if message.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                        }
                        Text(message.busy ? "发送中…" : "发送")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(ModernPrimaryButtonStyle(horizontalPadding: 16, verticalPadding: 6))
                .disabled(message.busy || (message.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.attachment == nil) || voice.active)
            }
        }
    }
    
    @ViewBuilder
    private var completedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.success)
            Text("已处理完成")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Ink.secondary)
            Button("关闭", action: close)
                .buttonStyle(ModernSecondaryButtonStyle(horizontalPadding: 14, verticalPadding: 6))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

struct StartCard: View {
    static let radius: CGFloat = 16
    /// Settings-group rows top to bottom (立品 2026-10-20): 知识库 is row 2, 开播方式 last. Rows 44pt, 0.5pt dividers between rows only.
    static let rowOrder = ["课程", "知识库", "开播方式"]
    static let rowHeight: CGFloat = 44, dividerHeight: CGFloat = 0.5
    /// Centre of a row measured from the group's top edge (the side panel's first row is levelled with this).
    static func rowCenter(_ title: String) -> CGFloat? {
        guard let i = rowOrder.firstIndex(of: title) else { return nil }
        return CGFloat(i) * (rowHeight + dividerHeight) + rowHeight / 2
    }
    static let fieldFill = AppTheme.dyn(0x000000, 0xFFFFFF, 0.04, 0.06)
    @ObservedObject var store: Store
    var settings: () -> Void
    var close: () -> Void = {}
    @State private var pickLibrary = CommandLine.arguments.contains("--preview-libs")
    @State private var pickCourse = CommandLine.arguments.contains("--preview-courses")
    @State private var destination: BroadcastDestination = .client
    /// Side dropdowns: trigger row centres below the card top, and the side each panel opened on.
    @State private var courseRowCenter: CGFloat = 0
    @State private var libraryRowCenter: CGFloat = 0
    @State private var courseLeft = false
    @State private var libraryLeft = false
    /// Keyboard focus on the two triggers: drawn inside the shape (strokeBorder) instead of the system ring, which got clipped.
    @FocusState private var courseFocused: Bool
    @FocusState private var libraryFocused: Bool
    @State private var hoverCourse = false
    @State private var hoverLibrary = false
    private var selectedCourseTitle: String? { availablePreparations.first(where:{$0.1.id == store.selectedPreparationID})?.1.title }

    /// Settings group (spec 2026-10-20): liveCardFill r12 (same as the 进行中 cards, keeps the dark window's blue tone), 44pt rows, 64pt title column, value right-aligned + ›.
    private var settingsGroup: some View {
        VStack(spacing: 0) {
            courseRow
            StartRowDivider()
            libraryRow
            StartRowDivider()
            modeRow
        }
        .background(AppTheme.liveCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private var courseRow: some View {
        // The course carries its channel; no separate channel entry is required.
        let title: String? = selectedCourseTitle
        let valueColor: AnyShapeStyle = title == nil ? AnyShapeStyle(AppTheme.textHint) : AnyShapeStyle(Ink.primary)
        let active: Bool = pickCourse || courseFocused
        return Button { NSApp.keyWindow?.makeFirstResponder(nil); DropdownGate.toggle($pickCourse) } label: {   // drop channel focus: no inactive grey fill
            StartRow(title: "课程", hovered: hoverCourse, active: active) {
                Text(title ?? "选择课程").font(.system(size: 13)).foregroundStyle(valueColor).lineLimit(1).truncationMode(.tail)
                SideChevron(left: courseLeft, color: AppTheme.textHint)
            }
        }
        .buttonStyle(.plain)
        .focused($courseFocused).focusEffectDisabled()   // still keyboard-focusable; focus draws the inner accent border
        .onHover { hoverCourse = $0 }
        .accessibilityLabel("课程")
        .accessibilityValue(title ?? "选择课程")
        .accessibilityHint("弹出选项列表")
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("start-card")).midY } action: { courseRowCenter = $0 }
        .disabled(store.broadcastLaunching)
    }
    private var modeRow: some View {
        StartRow(title: "开播方式", hovered: false, active: false) {
            SegmentedTabs(items: [(BroadcastDestination.client, "客户端"), (BroadcastDestination.web, "网页")], selection: $destination, height: 28, fontSize: 12)
                .frame(width: 168)
        }.disabled(store.broadcastLaunching)
    }
    private var libraryRow: some View {
        let active: Bool = pickLibrary || libraryFocused
        return Button { NSApp.keyWindow?.makeFirstResponder(nil); DropdownGate.toggle($pickLibrary) } label: {
            StartRow(title: "知识库", hovered: hoverLibrary, active: active) {
                Text(store.libraryLabel).font(.system(size: 13)).foregroundStyle(Ink.primary)
                    .lineLimit(1).truncationMode(.tail)
                SideChevron(left: libraryLeft, color: AppTheme.textHint)
            }
        }
        .buttonStyle(.plain)
        .focused($libraryFocused).focusEffectDisabled()
        .onHover { hoverLibrary = $0 }
        .accessibilityLabel("公共知识库")
        .accessibilityValue(store.libraryLabel)
        .accessibilityHint("弹出多选列表")
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("start-card")).midY } action: { libraryRowCenter = $0 }
    }
    /// The assistant's name is the user-set 「助教昵称」.
    var petName: String { store.assistantName }
    private var availablePreparations: [(String,LessonPreparation)] {
        return store.saved.rooms.flatMap { room in
            (room.preparations ?? []).filter { $0.usedByCourseID == nil }.map { (room.channel,$0) }
        }
    }
    var ready: Bool { store.selectedPreparationID != nil && !store.busy && !store.broadcastLaunching }
    /// Selecting an existing course also selects its classroom channel.
    private var courseItems: [DropdownItem] {
        guard !availablePreparations.isEmpty else {
            return [DropdownItem(id: "new-course", title: "新建", kind: .primaryAction, action: openCourseList)]
        }
        return availablePreparations.map { item in
            DropdownItem(id: item.1.id.uuidString, title: item.1.title, detail: store.classroomTitle(item.0), selected: store.selectedPreparationID == item.1.id) {
                store.channel = item.0; store.selectedPreparationID = item.1.id
            }
        }
    }
    private func openCourseList() {
        pickCourse = false; pickLibrary = false
        close()
        store.requestCourseListFromStart()
        settings()
    }
    private func start() {
        guard ready, let lessonID = store.selectedPreparationID,
              let item = availablePreparations.first(where: { $0.1.id == lessonID }) else { return }
        store.error = ""
        Task { @MainActor in
            do { try await store.launchBroadcast(channel: item.0, lessonID: lessonID, destination: destination) }
            catch { store.error = error.localizedDescription }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button(action: settings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(HoverCircleButtonStyle())
                .help("设置")
                
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Ink.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(HoverCircleButtonStyle())
                .help("关闭")
            }
            
            SpriteView(character: store.saved.preferences.pet, action: .idle, draggable: false, onClick: {})
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            
            VStack(spacing: 4) {
                Text(petName.isEmpty ? "助教已就绪" : "\(petName) 已就绪")
                    .font(.system(size: 15, weight: .semibold))
            }
            
            settingsGroup

            if !store.error.isEmpty {
                Text(store.error)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.danger)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: start) {
                HStack(spacing: 6) {
                    if store.busy || store.broadcastLaunching { ProgressView().controlSize(.small) }
                    Text(store.busy || store.broadcastLaunching ? "正在开课…" : "开始上课")
                }
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .buttonStyle(ModernPrimaryButtonStyle(cornerRadius: 12, horizontalPadding: 0, verticalPadding: 0, disabledLook: !ready))
            .disabled(!ready)
        }
        .padding(20)
        .frame(width: 320)
        // Window == card: no SwiftUI shadow or shadow margin; the system window shadow follows the r16 alpha edge.
        .modifier(CardSurface(shape: RoundedRectangle(cornerRadius: StartCard.radius, style: .continuous), shadow: false, stroke: false))
        .overlay(StartCardEdge())
        .coordinateSpace(name: "start-card")
        // Both pickers open beside the card (8pt out, first row level with their trigger), never over it.
        .background(DropdownPanelAnchor(isPresented: $pickLibrary, edge: .side(rowCenter: libraryRowCenter), gap: 8, width: 280,
            header: "检索知识库（可多选）", empty: "暂无知识库，可在设置中新建",
            items: LibraryChecklist.items(store: store), onSide: { libraryLeft = $0 }))
        .background(DropdownPanelAnchor(isPresented: $pickCourse, edge: .side(rowCenter: courseRowCenter), gap: 8, width: 280,
            items: courseItems, onSide: { courseLeft = $0 }))
        .onChange(of: store.connected) { _, connected in if connected && !store.broadcastLaunching { close() } }
        .onAppear {   // dev screenshots: --preview --preview-channel <号> pre-fills the channel so its courses list
            let args = CommandLine.arguments
            if args.contains("--preview"), let i = args.firstIndex(of: "--preview-channel"), i + 1 < args.count { store.channel = args[i + 1] }
        }
    }
}

/// 公共知识库 multi-select: one checkbox row per library plus the existing 全选 / 取消全选.
enum LibraryChecklist {
    @MainActor static func items(store: Store) -> [DropdownItem] {
        var items = store.saved.libraries.map { lib in
            DropdownItem(id: lib.id.uuidString, title: lib.name, detail: "\(lib.documents.count) 份资料", spine: KnowledgeSpine.color(for: lib.name),
                         selected: store.libraryIDs.contains(lib.id), kind: .checkbox) {
                if store.libraryIDs.contains(lib.id) { store.libraryIDs.remove(lib.id) } else { store.libraryIDs.insert(lib.id) }
            }
        }
        if store.saved.libraries.count > 1 {
            let allIDs = Set(store.saved.libraries.map(\.id))
            let allSelected = allIDs.isSubset(of: store.libraryIDs)
            items.append(DropdownItem(id: "select-all", title: allSelected ? "取消全选" : "全选", kind: .footer, dividerBefore: true) {
                if allSelected { store.libraryIDs.subtract(allIDs) } else { store.libraryIDs.formUnion(allIDs) }
            })
        }
        return items
    }
}

/// Small classroom card: 280 wide, 320 high, persistent work above assistant activity.
/// (hint text, viewer avatars, 「N 人」 aggregation, 回答/查看 + 忽略). Pinned to-dos on top; ≥3 → first 2 + 「更多」.
/// Normal info posts (e.g. welcome) below, newest first. Same surface as the big card: 92% fill, white stroke, soft shadow.
struct CollapsedPendingBubble: View {
    @ObservedObject var store: Store
    var glassSpace: Namespace.ID?
    @Environment(\.cardContentOpacity) private var contentOpacity
    static let width: CGFloat = 280, height: CGFloat = 200, tail: CGFloat = 8, corner: CGFloat = 18
    static let tipX: CGFloat = width - 40
    static let voiceExtra: CGFloat = 112
    /// Stable classroom height; content scrolls inside instead of resizing the card.
    @MainActor static func height(for store: Store) -> CGFloat {
        return 320
    }
    /// Groups 16pt apart (5pt row padding + 6 + 5); rows inside a group keep their own spacing. Cards get the same 5pt so card ↔ group is 16 too.
    static let groupSpacing: CGFloat = 16 - 2 * PendingBoard.bubbleRowPadding
    static let pendingKinds: [PendingMessage.Kind] = [.question, .material]
    static let otherKinds: [PendingMessage.Kind] = [.risk, .technical, .notice]
    enum PinnedSection: Hashable { case pending, interactions, reminders, others }
    /// Non-empty sections, top to bottom. With waiting questions: 待答 / 资料请求 first, then running cards, reminders, the rest.
    @MainActor static func pinnedSections(for store: Store) -> [PinnedSection] {
        func has(_ kinds: [PendingMessage.Kind]?) -> Bool { store.messages.contains { m in (kinds?.contains(m.kind) ?? true) && m.pinned } }   // m.pinned = the rows PendingBoard.pinnedSection shows
        var out: [PinnedSection] = []
        let split = store.classroomQuestionCount > 0
        if split && has(pendingKinds) { out.append(.pending) }
        if !store.pinnedInteractions.isEmpty { out.append(.interactions) }
        if !store.currentReminders.isEmpty { out.append(.reminders) }
        if has(split ? otherKinds : nil) { out.append(.others) }
        return out
    }
    var body: some View {
        let shape = BubbleWithTail(corner: Self.corner, tail: Self.tail, tipX: Self.tipX)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if store.classroomQuestionCount > 0 {   // 待答 includes material requests (same count as the 工作台)
                    HStack(spacing: 4) {
                        Circle().fill(AppTheme.danger).frame(width: 5.5, height: 5.5)
                        Text("待答").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.primary)
                    }
                    Text("\(store.classroomQuestionCount)")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4.5)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(AppTheme.danger, in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.accent)
                        Text("课堂助手")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Ink.secondary)
                    }
                }
                Spacer(minLength: 4)
                // Same order as the 工作台 header: expand icon, then 「下课」 at the far right.
                PanelHeaderButtons(store: store, mode: .bubble)
                if store.connected || store.demo { EndClassButton(store: store, plain: true).padding(.leading, 7) }
            }
            .padding(.horizontal, 10).padding(.top, 8)
            .fixedSize(horizontal: false, vertical: true).layoutPriority(2)   // header stays at its top margin; never squeezed or pushed up
            // Middle list fills leftover height only; bottom dock (stream + caption) keeps layoutPriority so pinned rows never shove it off.
            ScrollView {
                // Only sections that have content are laid out: an empty ActiveInteractions / reminders VStack used to keep
                // its slot and the 8pt spacing on both sides (≈34pt between 待答 and 课堂反馈).
                VStack(alignment: .leading, spacing: Self.groupSpacing) {
                    ForEach(Self.pinnedSections(for: store), id: \.self) { section in
                        switch section {
                        // Same rule as the 课堂 tab: waiting questions (+ material requests) above the running cards; the rest stays below.
                        case .pending: PendingBoard(store: store, includedKinds: Self.pendingKinds, bubble: true, part: .allPinned).padding(.horizontal, 4)
                        case .interactions: ActiveInteractions(store: store, compact: true).padding(.horizontal, 8).padding(.vertical, PendingBoard.bubbleRowPadding)
                        case .reminders: ClassroomRemindersView(store: store)
                        case .others: PendingBoard(store: store, includedKinds: store.classroomQuestionCount > 0 ? Self.otherKinds : nil, bubble: true, part: .allPinned).padding(.horizontal, 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .modifier(BottomFadeWhenOverflowing(height: 16))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if abs(store.bubbleTopH - h) > 0.5 { store.bubbleTopH = h } }
            // Dock: 助教动态流 sits just above the caption (抖音公屏), never displaced by the list above.
            VStack(alignment: .leading, spacing: 6) {
                LiveMessageStream(store: store, compact: true, scrollable: false, limit: 2).padding(.horizontal, 10)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in if abs(store.bubbleStreamH - h) > 0.5 { store.bubbleStreamH = h } }
                // Caption pinned to the bottom: 12pt, one line, leading fade (same component as the 工作台 caption).
                TranscriptCaption(store: store, course: store.currentCourse, fontSize: 12, lineHeight: 22).padding(.horizontal, 14).padding(.bottom, 4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(2)
            if store.commandVoiceVisible { Divider().padding(.horizontal, 10); CommandVoiceInline(store: store, voice: store.voice).padding(.horizontal, 12).padding(.bottom, 8) }
        }
        .padding(.bottom, Self.tail)
        .frame(width: Self.width, height: Self.height(for: store) + Self.tail + (store.commandVoiceVisible ? Self.voiceExtra : 0), alignment: .top)
        .clipped()   // middle list absorbs overflow; header + bottom dock (stream + caption) keep their places
        .opacity(contentOpacity)   // content only; the surface below stays (expand/collapse sequencing)
        .modifier(CardSurface(shape: shape, shadow: false))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .contentShape(shape)
    }
}

/// Bubble material: clear glass + 8% white (no window-background grey layered on the glass).
struct TailBubbleGlass<S: Shape>: ViewModifier {
    var shape: S
    var namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let namespace { content.glassEffect(.clear.tint(.white.opacity(0.08)), in: shape).glassEffectID("board", in: namespace) }
            else { content.glassEffect(.clear.tint(.white.opacity(0.08)), in: shape) }
        } else {
            content.background(shape.fill(.white.opacity(0.08))).background(.ultraThinMaterial, in: shape)
        }
    }
}

/// One continuous outline (rounded body + bottom tip) so glassEffect applies once — no separate fill.
struct BubbleWithTail: Shape {
    var corner: CGFloat, tail: CGFloat, tipX: CGFloat
    /// Big card: tip measured from the trailing edge so it sits exactly where the small bubble's tip is (both share the bottom-right anchor).
    var tipFromTrailing: CGFloat? = nil
    func path(in r: CGRect) -> Path {
        let bodyH = r.height - tail
        let c = min(corner, min(r.width, bodyH) / 2)
        let tipX = tipFromTrailing.map { r.maxX - $0 } ?? self.tipX
        let tipL = tipX - 7, tipR = tipX + 7
        var p = Path()
        // top edge
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        // right edge down to body bottom
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + bodyH - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.minY + bodyH), control: CGPoint(x: r.maxX, y: r.minY + bodyH))
        // bottom of body, with tip
        p.addLine(to: CGPoint(x: tipR, y: r.minY + bodyH))
        p.addLine(to: CGPoint(x: tipX, y: r.maxY))
        p.addLine(to: CGPoint(x: tipL, y: r.minY + bodyH))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.minY + bodyH))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + bodyH - c), control: CGPoint(x: r.minX, y: r.minY + bodyH))
        // left edge up
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Shared expand + close header buttons (bubble / panel / maximized).
struct PanelHeaderButtons: View {
    enum Mode { case bubble, panel }
    @ObservedObject var store: Store
    var mode: Mode
    var body: some View {
        Button {
            store.setDetail(mode == .bubble)
        } label: {
            Image(systemName: mode == .bubble ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverCircleButtonStyle())
        .accessibilityLabel(mode == .bubble ? "展开助教工作台" : "收起为小气泡")
        .help(mode == .bubble ? "展开助教工作台" : "收起为小卡片")
    }
}

struct PendingBoard: View {
    /// 课堂 tab 待答问题: each item in its own grey card (same as 课堂反馈 box), 8 apart.
    var cardRows = false
    @ObservedObject var store: Store
    var embedded = false
    var includedKinds: [PendingMessage.Kind]? = nil
    var showGroupTitles = true
    var bubble = false
    enum Part { case all, pinned, allPinned, stream }
    var part: Part = .all
    var glassSpace: Namespace.ID? = nil
    @State private var hovered: UUID?
    @State private var detailID: UUID?
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    /// Bubble rows: 5pt above + below each row.
    static let bubbleRowPadding: CGFloat = 5
    /// Bubble top (fixed): pending items — 需要回复 first, then 仅需查看; ≥3 → first 2 + 「更多」.
    var pinnedSection: some View {
        let mine = store.messages.filter { includedKinds?.contains($0.kind) ?? true }
        let reply = mine.filter { $0.responseType == .reply }.sorted { $0.people.count > $1.people.count }
        let view = mine.filter { $0.responseType == .view }.sorted { $0.lastTime > $1.lastTime }
        let pending = reply + view
        let shown = part == .allPinned ? pending : pending.count >= 3 ? Array(pending.prefix(2)) : pending
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(shown) { row($0) }
            if part != .allPinned && pending.count >= 3 {
                Button { store.setDetail(true) } label: {
                    HStack(spacing: 3) {
                        Text("更多（\(pending.count - 2)）")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Ink.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                }.buttonStyle(.plain).help("在大卡片中查看全部")
            }
        }
    }
    /// Bubble stream (scrolls): 仅消息流 in chat order — oldest at top, newest at bottom.
    var streamSection: some View {
        streamRows(posts: store.messages.filter { $0.responseType == .stream }, limit: 1, chronological: true)
    }
    var bubbleList: some View { VStack(alignment: .leading, spacing: 1) { pinnedSection; streamSection } }
    /// 仅消息流: plain rows (assistant posts + activity log), newest first, no actions.
    func streamRows(posts: [PendingMessage], limit: Int, chronological: Bool = false, includeLog: Bool = true) -> some View {
        let all: [(Date, String, String, Bool, Bool)] = (posts.map { ($0.time, $0.title, $0.question, $0.isError, $0.isSystem) } + (includeLog ? store.log.map { ($0.time, $0.text, "", false, false) } : []))
        let newest = all.sorted { $0.0 > $1.0 }.prefix(limit)
        let items = chronological ? newest.reversed().map { $0 } : newest.map { $0 }
        return ForEach(Array(items.enumerated()), id: \.offset) { _, it in
            HStack(alignment: .top, spacing: 7) {
            Group {
                if it.4 { SystemAvatar() } else { AssistantAvatar(pet: store.saved.preferences.pet) }   // system hint vs assistant's own post
            }.padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(it.1).font(.system(size: 13)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.hm.string(from: it.0)).font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textHint)
                }
                if !it.2.isEmpty { Text(it.2).font(.system(size: 11)).foregroundStyle(it.3 ? AppTheme.danger : .secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }
    /// 仅需查看 detail: who reported, how many, time range.
    /// 「6 人反馈 · 22:31–22:38」 (a single time when first and last are the same minute).
    static func viewSummary(_ m: PendingMessage) -> String {
        let count = max(m.people.count, m.audienceCount, 1)
        let (a, b) = (hm.string(from: m.time), hm.string(from: m.lastTime))
        return "\(count) 人" + (m.kind == .question ? "提问" : "反馈") + " · " + (a == b ? a : a + "–" + b)
    }
    static func viewNames(_ m: PendingMessage) -> String {
        let names = m.people.sorted()
        return names.prefix(12).joined(separator: "、") + (names.count > 12 ? " 等 \(names.count) 人" : "")
    }
    /// `showQuestion`: false where the row itself already shows the message text (工作台 rows).
    func viewDetail(_ m: PendingMessage, showQuestion: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.viewSummary(m)).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.secondary)
            if !m.people.isEmpty { Text(Self.viewNames(m)).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
            if showQuestion, !m.question.isEmpty, m.question != m.title { Text(m.question).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(4).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))   // 决定 2b: light grey block under the row
        .textSelection(.enabled)
    }
    /// Reply rows open the composer; 仅需查看 rows (feedback / violations) toggle the detail block.
    func tap(_ m: PendingMessage) {
        if m.responseType == .view { withAnimation(.easeOut(duration: 0.15)) { detailID = detailID == m.id ? nil : m.id } }
        else { store.open(m.id) }
    }
    static let order: [PendingMessage.Kind] = [.question, .material, .risk, .technical, .notice]   // 需要回复 first
    static func name(_ k: PendingMessage.Kind) -> String { switch k { case .risk: return "违规消息"; case .question: return "待答问题"; case .technical: return "课堂反馈"; case .material: return "资料请求"; case .notice: return "助教动态" } }
    static func dot(_ k: PendingMessage.Kind) -> Color { switch k { case .risk: return .red; case .question: return .blue; case .technical: return .orange; case .material: return .green; case .notice: return .gray } }
    var groups: [(PendingMessage.Kind, [PendingMessage])] {
        Self.order.compactMap { k in
            if let includedKinds, !includedKinds.contains(k) { return nil }
            let items = store.messages.filter { $0.kind == k && !$0.evaluating }.sorted { $0.people.count > $1.people.count }
            return items.isEmpty ? nil : (k, items)
        }
    }
    var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups.filter { $0.0 != .notice }, id: \.0) { kind, items in
                VStack(alignment: .leading, spacing: 2) {
                    if showGroupTitles {
                        Text("\(Self.name(kind)) · \(items.count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.secondary)
                            .padding(.horizontal, 8).padding(.bottom, 4)
                    }
                    if cardRows {
                        VStack(alignment: .leading, spacing: 0) {   // no dividers: rows are 12pt apart (6pt padding each side)
                            ForEach(items) { m in row(m) }
                        }
                    } else {
                        ForEach(items) { row($0) }
                    }
                }
            }
        }
    }
    var body: some View {
        if bubble { switch part { case .pinned, .allPinned: pinnedSection; case .stream: streamSection; case .all: bubbleList } } else if embedded { list } else { simple }
    }
    var simple: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("待答").font(.system(size: 15, weight: .semibold))
                Text("\(store.classroomQuestionCount)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18).background(Color.primary.opacity(0.75), in: Capsule())
                Spacer()
                Button { store.setDetail(true) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.secondary).frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("详细版")
                Button { store.collapsePending() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Ink.secondary).frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("收起为气泡")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if !store.pendingCollapsed {
                ScrollView {
                    list.padding(.horizontal, 6).padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(CardSurface(shape: RoundedRectangle(cornerRadius: 18, style: .continuous), id: "board", namespace: glassSpace, shadow: false))
        .padding(6)
    }
    @ViewBuilder func row(_ m: PendingMessage) -> some View {
        if m.responseType == .stream { streamRows(posts: [m], limit: 1, includeLog: false) } else { actionRow(m) }
    }
    @ViewBuilder func actionRow(_ m: PendingMessage) -> some View {
        if cardRows { compactRow(m) } else { classicRow(m) }
    }
    /// Big card (520) row: title 13 medium · 11 grey secondary · right count column · 回复 capsule · 忽略 text.
    func compactRow(_ m: PendingMessage) -> some View {
        let hot = hovered == m.id
        let isView = m.responseType == .view
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                MessageTypeBadge(type: m.typeBadge, side: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(!m.question.isEmpty ? m.question : m.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(2)
                    let sub = !m.draft.isEmpty ? m.draft : (!m.source.isEmpty ? "依据：" + m.source : "")
                    if !sub.isEmpty { Text(sub).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.tail) }
                }
                Spacer(minLength: 12)
                if m.audienceCount > 0 { Text("\(m.audienceCount) 人").font(.system(size: 11).monospacedDigit()).foregroundStyle(Ink.secondary).frame(minWidth: 30, alignment: .trailing) }
                if !isView {
                    Button { store.open(m.id) } label: {
                        Text("回复").font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.accent)
                            .padding(.horizontal, 12).frame(height: 24)
                            .background(Ink.accent.opacity(0.16), in: Capsule())
                    }.buttonStyle(.plain)
                }
                Button { store.ignore(m.id) } label: {
                    Text("忽略").font(.system(size: 11)).foregroundStyle(AppTheme.textHint).frame(height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            LecturerSuggestionView(store: store, message: m, compact: true)
            if detailID == m.id { viewDetail(m, showQuestion: m.question.isEmpty).padding(.leading, 34) }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.subtleFill.opacity(hot ? 1 : 0)).padding(.horizontal, 10))   // inset hover, 8pt outside the text
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? m.id : (hovered == m.id ? nil : hovered) }
        .onTapGesture { tap(m) }
        .help(m.people.count == 1 ? m.people.first! : "")
    }
    func classicRow(_ m: PendingMessage) -> some View {
        let hot = hovered == m.id
        let isView = m.responseType == .view
        return VStack(alignment: .leading, spacing: 4) { HStack(alignment: .top, spacing: 8) {
            MessageTypeBadge(type: m.typeBadge, compact: bubble)
            VStack(alignment: .leading, spacing: 3) {
                Text(embedded && !m.question.isEmpty ? m.question : m.title).font(.system(size: bubble ? 12.5 : 14, weight: embedded ? .semibold : .medium)).foregroundStyle(Ink.primary).lineLimit(embedded ? 3 : 1).truncationMode(.tail)
                if m.audienceCount > 0 { Text("\(m.audienceCount) 人" + (isView ? "反馈" : "提问")).font(.system(size: 11)).foregroundStyle(Ink.secondary) }
                if bubble && !m.pinned && !m.question.isEmpty {
                    Text(m.question).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if embedded && !m.source.isEmpty {
                    Text("依据：" + m.source).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(2)
                }
                if (embedded || bubble) && !m.draft.isEmpty {
                    Label(m.draft, systemImage: "sparkles").labelStyle(DraftLabel()).font(.system(size: embedded ? 13 : 12)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                if !isView {
                    Button { store.open(m.id) } label: {
                        Text("回复")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button { store.ignore(m.id) } label: {
                    Text("忽略")
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.group)   // bubble: plain text, white 40% / black 38%
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        if embedded { LecturerSuggestionView(store: store, message: m, compact: true) }
        if detailID == m.id { viewDetail(m).padding(.leading, bubble ? 28 : 32) }
        }
        .padding(.horizontal, embedded ? 10 : 8).padding(.vertical, embedded ? 10 : bubble ? Self.bubbleRowPadding : 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hot ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? m.id : (hovered == m.id ? nil : hovered) }
        .onTapGesture { tap(m) }
        .help(m.people.count == 1 ? m.people.first! : "")
    }
}

/// Badge for 「好几个人说同一件事」 clusters; color deepens with the head count.
enum ClusterBadge {
    static func strength(_ count: Int) -> Double { min(1, Double(max(count - HighFrequency.threshold, 0)) / 9) }
    static func fill(_ count: Int, kind: PendingMessage.Kind) -> Color {
        let base: Color = kind == .technical ? AppTheme.warning : kind == .risk ? AppTheme.danger : AppTheme.accent
        return base.opacity(0.16 + 0.74 * strength(count))
    }
    static func text(_ count: Int) -> Color { strength(count) > 0.5 ? .white : .primary }
}

struct AnswerBar: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    var close: () -> Void
    @State private var shown = false
    @FocusState private var typing: Bool
    var body: some View {
        VStack { Spacer(minLength: 0)
            if let id = store.selected, let m = store.messages.first(where: { $0.id == id }) {
                content(id: id, m: m)
                    .offset(y: shown ? 0 : 40).opacity(shown ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { shown = true } }
        .tint(AppTheme.accent)
    }
    func binding(_ id: UUID) -> Binding<String> {
        Binding(get: { store.messages.first { $0.id == id }?.draft ?? "" }, set: { v in if let i = store.messages.firstIndex(where: { $0.id == id }) { store.messages[i].draft = v } })
    }
    @ViewBuilder func content(id: UUID, m: PendingMessage) -> some View {
        let recording = voice.active
        VStack(alignment: .leading, spacing: 16) {
            // What is being answered: the question (or the aggregated same message) + who asked.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(PendingBoard.dot(m.kind)).frame(width: 6, height: 6)
                    Text(m.people.count > 1 ? "\(m.people.count) 人在问同一个问题" : "正在回答")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.secondary)
                    Spacer()
                    if !m.source.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.accent)
                            Text("参考：\(m.source)")
                                .font(.system(size: 11))
                                .foregroundStyle(Ink.secondary)
                                .lineLimit(1)
                        }
                    }
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("关闭 (Esc)")
                }
                Text(m.question)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.people.isEmpty {
                    let names = m.people.sorted()
                    HStack(spacing: 6) {
                        HStack(spacing: -5) {
                            ForEach(Array(names.prefix(5)), id: \.self) {
                                ViewerAvatar(name: $0, url: store.avatars[$0], soft: true)
                            }
                        }
                        Text(names.prefix(4).joined(separator: "、") + (names.count > 4 ? " 等 \(names.count) 人" : ""))
                            .font(.system(size: 11))
                            .foregroundStyle(Ink.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 6)
            
            ScrollView { LecturerSuggestionView(store: store, message: m) }
                .frame(maxHeight: m.suggestion == nil && !m.suggestionLoading ? 0 : 160)
            // Input row: field, then mic on the RIGHT, then send.
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        if recording {
                            HStack(spacing: 6) {
                                WaveformVisualizer(active: true, barCount: 3, color: AppTheme.accent)
                                Text(voice.transcript.isEmpty ? "正在听口述…" : voice.transcript)
                                    .font(.system(size: 15))
                                    .foregroundStyle(voice.transcript.isEmpty ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                        } else {
                            TextField("输入或说出回答 (Enter 发送)", text: binding(id), axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .lineLimit(1...3)
                                .focused($typing)
                                .onSubmit { store.send(id) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.cardBorder, lineWidth: 0.75)
                )
                
                Button { store.startVoice(question: id) } label: {
                    ZStack {
                        Circle().fill(recording ? Color.red : Color.primary.opacity(0.06))
                        if recording {
                            WaveformVisualizer(active: true, barCount: 4, color: .white).frame(width: 18, height: 14)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Ink.accent)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .help(recording ? "说完了" : "点击说话")
                .disabled(m.busy || (recording && voice.phase != "正在录音"))
                
                Button { store.send(id) } label: {
                    Group {
                        if m.busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.accentGradient, in: Circle())
                    .shadow(color: AppTheme.accent.opacity(0.3), radius: 4, y: 1.5)
                }
                .buttonStyle(.plain)
                .help("发送")
                .disabled(m.busy || recording || m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(m.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 4)
            
            if !m.error.isEmpty || !store.error.isEmpty {
                Text(m.error.isEmpty ? store.error : m.error)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 6)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(DetailBoard.tint))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
        .frame(width: recording ? 600 : 560)
        .animation(.easeInOut(duration: 0.2), value: recording)
        .padding(.bottom, 16)
        .onChange(of: store.messages.contains { $0.id == id }) { _, exists in if !exists { close() } }
    }
}


struct ViewerAvatar: View {
    let name: String
    let url: String?
    var size: CGFloat = 18
    /// Reply card: distinct soft tint per person (accent / teal / orange @15%), stable per name.
    var soft = false
    static let softColors: [Color] = AppTheme.avatarSoft
    var softColor: Color { Self.softColors[name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.softColors.count] }
    @ViewBuilder var initial: some View {
        if soft {
            Text(String(name.prefix(1))).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(softColor)
                .frame(width: size, height: size).background(Circle().fill(softColor.opacity(0.15))).background(Circle().fill(AppTheme.dyn(0xFFFFFF, 0x2C2C2E)))
        } else {
            Text(String(name.prefix(1))).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size).background(Circle().fill(Color.gray))
        }
    }
    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { initial }
                }
            } else { initial }
        }
        .frame(width: size, height: size).clipShape(Circle()).overlay(Circle().strokeBorder(DetailBoard.tint, lineWidth: size > 20 ? 0 : 1.5))
    }
}

struct DraftLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 4) { configuration.icon.font(.system(size: 11)); configuration.title } }
}

struct DetailContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Big panel only: frosted .regular glass (blurs what's behind) + ~60% white tint, so it reads as a solid surface.
/// Header drag: a SwiftUI gesture behind the header content. (An NSView drag area covered the whole board
/// and swallowed every click, incl. the collapse / × buttons — that was the "collapse does nothing" bug.)
struct HeaderWindowDrag: View {
    @State private var start: NSPoint?
    @State private var window: NSWindow?
    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { g in
                    if start == nil { window = NSApp.currentEvent?.window; start = window?.frame.origin }
                    guard let start, let window else { return }
                    window.setFrameOrigin(NSPoint(x: start.x + g.translation.width, y: start.y - g.translation.height))
                }
                .onEnded { _ in start = nil; window = nil })
    }
}

struct DetailGlass: ViewModifier {   // near-solid fill, no glass (no grey rim, no refraction glow)
    var namespace: Namespace.ID?
    var maximized = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let solid = content.background(shape.fill(DetailBoard.bigCardTint))
        // Maximized: no glass layer. The morph-only .clear glass under the fill rendered as a lighter box over
        // only part of the 80%-screen panel; the panel⇄max change is a window resize, so no morph is needed there.
        if #available(macOS 26.0, *), let namespace, !maximized {
            solid.glassEffect(.clear, in: shape).glassEffectID("board", in: namespace)   // id only for the bubble ⇄ panel morph; fill stays 92% solid
        } else { solid }
    }
}

/// Detail panel edge: white highlight stroke (same as toolbar) + soft shadow, instead of the grey glass rim.
struct DetailEdge: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.dyn(0x000000, 0xFFFFFF, 0.08, 0.10), lineWidth: 0.5)   // hairline
                    .allowsHitTesting(false)
            )
            // three-layer shadow
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
    }
}

struct DetailBoard: View {
    @Environment(\.cardContentOpacity) private var contentOpacity
    static let minHeight: CGFloat = 676   // window 720 (fixed 680×720)
    static let maxHeight: CGFloat = 676
    /// Big card only: light #F7F8FA @92% (bubble/popups keep `tint`); dark same as tint.
    static var bigCardTint: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x23/255, green: 0x23/255, blue: 0x25/255, alpha: 1) : NSColor.white
        })
    }
    static var tint: Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.13, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)
        })
    }
    @ObservedObject var store: Store
    var glassSpace: Namespace.ID? = nil
    /// Sidebar: 消息 (full stream, to-dos pinned on top) · 助教笔记 (口播稿 / 金句 / 题目 / 其他) · 监控 (placeholder).
    enum Tab: String, CaseIterable { case pending = "课堂", notes = "笔记", data = "数据", monitor = "记录" }
    typealias NoteSection = NotebookSection
    var noteSections: [NotebookSection] { NotebookSection.enabled(in: store.saved.capabilities) }
    var notebookIsEmpty: Bool {
        guard let course else { return true }
        switch note {
        case .interactions: return (course.interactions ?? []).isEmpty
        case .questions: return (course.exercises ?? []).isEmpty
        case .quotes: return (course.quotes ?? []).isEmpty && course.cards.isEmpty
        case .knowledge: return (course.knowledgePoints ?? []).isEmpty
        case .transcript: return course.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return note.output.flatMap { course.outputs?[$0.rawValue] }?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }
    @State private var tab: Tab = CommandLine.arguments.contains("--preview-data") ? .data : CommandLine.arguments.contains("--preview-notes") ? .notes : CommandLine.arguments.contains("--preview-monitor") ? .monitor : .pending
    @State private var note: NoteSection = {   // dev: --preview-note <名称> picks a 笔记 sub-tab for screenshots
        if let i = CommandLine.arguments.firstIndex(of: "--preview-note"), i + 1 < CommandLine.arguments.count, let n = NoteSection(rawValue: CommandLine.arguments[i + 1]) { return n }
        return .interactions
    }()
    @State private var seen: [Tab: Int] = [:]
    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    func count(_ t: Tab) -> Int {
        switch t { case .pending: return store.badgeCount; case .notes: return store.liveQuotes.count + (course?.cards.count ?? 0); case .data, .monitor: return 0 }
    }
    func icon(_ t: Tab) -> String {
        switch t { case .pending: return "bubble.left.and.bubble.right"; case .notes: return "note.text"; case .data: return "chart.xyaxis.line"; case .monitor: return "clock.arrow.circlepath" }
    }
    var course: CourseSession? { store.saved.courses.first { $0.id == store.currentCourseID } }   // newest first
    func hasDot(_ t: Tab) -> Bool { t != .pending && t != tab && count(t) > (seen[t] ?? 0) }
    /// Compact 520 workbench: title row · three counts · segmented tabs · scrolling content.
    /// Recent assistant activity lines for the 课堂 footer (newest at the bottom; at most 3 so pending stays primary).
    var footerActivities: [PendingMessage] {
        Store.recentStreamMessages(store.messages, now: Date(), lifetime: store.flowLifetime, limit: 3)
    }
    static let shape = BubbleWithTail(corner: 18, tail: CollapsedPendingBubble.tail, tipX: 0, tipFromTrailing: CollapsedPendingBubble.width - CollapsedPendingBubble.tipX)
    /// Scale anchor = the tail tip, so the tip stays put on screen while the card grows / shrinks.
    static func tipAnchor(width: CGFloat) -> UnitPoint { UnitPoint(x: (width - (CollapsedPendingBubble.width - CollapsedPendingBubble.tipX)) / max(width, 1), y: 1) }
    var footerShown: Bool { (tab == .pending && !footerActivities.isEmpty) || ((store.connected || store.demo) && course != nil && course?.ended == nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text("助教工作台").font(.system(size: 15, weight: .semibold))
                if store.connected || store.demo { LiveDotTimer(store: store) }
                Spacer(minLength: 4)
                PanelHeaderButtons(store: store, mode: .panel)
                if store.connected || store.demo { EndClassButton(store: store, plain: true).padding(.leading, 2) }   // 10 + 2 = 12
            }
            .padding(.horizontal, 18).padding(.top, 16)
            .background(HeaderWindowDrag())   // drag the big card by its header strip (buttons still get clicks)
            // No counter row: 待答 + 反馈 ride on the 课堂 segment as a red count capsule.
            SegmentedTabs(items: Tab.allCases.map { ($0, $0.rawValue) }, selection: Binding(get: { tab }, set: { tab = $0; seen[$0] = count($0) }),
                          badges: [.pending: store.classroomQuestionCount + store.classroomFeedbackCount])
                .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 20)
            VStack(alignment: .leading, spacing: 12) {
                if tab == .notes {
                    NotebookTabs(sections: noteSections, selection: $note).padding(.horizontal, 18)
                }
                let activityCount = tab == .pending ? footerActivities.count : 0
                let fade: CGFloat = 16 + CGFloat(activityCount) * 22
                if tab == .pending {
                    ClassroomPanel(store: store, fade: fade)
                } else if tab == .notes && notebookIsEmpty {
                    NotebookEmptyState().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        content.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.bottom, 12)
                    }.scrollIndicators(.hidden).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(tab == .notes ? "notes-" + note.rawValue : tab.rawValue)   // each tab / 笔记 section opens at its top (no carried-over scroll offset)
                    .modifier(BottomEdgeFade(height: fade))
                }
                // 笔记 has no bottom buttons: notes update on their own every ≥45s while connected (ClassroomRuntime.startRuntimeLoop) and drain at 下课.
            }.padding(.bottom, footerShown ? 0 : 12).frame(maxWidth: .infinity, maxHeight: .infinity)
            if footerShown {
                VStack(alignment: .leading, spacing: 6) {
                    if tab == .pending {
                        ForEach(footerActivities) { activity in ActivityLine(message: activity) }
                    }
                    TranscriptCaption(store: store, course: course)
                }.padding(.horizontal, 32).padding(.bottom, 16)
            }
            if store.commandVoiceVisible { Color.clear.frame(height: 8); CommandVoiceInline(store: store, voice: store.voice).padding(.horizontal, 16).padding(.bottom, 12) }
        }
        .padding(.bottom, CollapsedPendingBubble.tail)   // the tail strip below the card body
        .frame(height: store.detailBoardHeight)
        .frame(maxWidth: .infinity)
        .opacity(contentOpacity)   // content only; the surface below stays (expand/collapse sequencing)
        // One outline for card + tail (same tail as the small bubble, same spot from the bottom-right): fill, stroke and shadow follow it with no seam.
        .modifier(CardSurface(shape: Self.shape))
        .contentShape(Self.shape)
        .onAppear { if store.notebookNavigationPending { tab = .notes; note = store.requestedNotebookSection; store.notebookNavigationPending = false } }
        .onChange(of: store.notebookNavigationID) { _, _ in tab = .notes; note = store.requestedNotebookSection; store.notebookNavigationPending = false }
        .onChange(of: tab) { _, t in seen[t] = count(t) }
        .onChange(of: noteSections) { _, sections in if !sections.contains(note) { note = sections.first ?? .interactions } }

    }
    func sideTab(_ t: Tab) -> some View {
        let on = tab == t
        let n = count(t)
        return Button {
            tab = t; seen[t] = n
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon(t))
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? AppTheme.accent : .secondary)
                    .frame(width: 14)
                Text(t.rawValue)
                    .font(.system(size: 13, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                if t == .pending, n > 0 {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .padding(.horizontal, 4.5).frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(on ? AppTheme.accent : Color.primary.opacity(0.06)))
                } else if hasDot(t) {
                    Circle().fill(AppTheme.accent).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(on ? .primary : .secondary)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.dyn(0x2469F3, 0x2469F3, 0.12, 0.18))
                }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    func empty(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Ink.secondary).frame(maxWidth: .infinity).padding(.top, 60)
    }
    @ViewBuilder var content: some View {
        switch tab {
        case .pending:
            ClassroomPanel(store: store)
        case .notes:
            if let error = course?.notebookError { Text(error).font(.system(size: 11)).foregroundStyle(Ink.secondary) }
            if let course { NotebookContent(store: store, course: course, section: note, live: true) }
            else { empty("正在随堂生成笔记…") }
        case .data:
            if let course { CourseDataView(store: store, course: course, live: true) }
            else { empty("暂无本场数据") }
        case .monitor:
            VStack(alignment: .leading, spacing: 28) {
                if !store.answeredItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        RecordsGroupTitle(text: "已回答")
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(store.answeredItems.reversed()) { h in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(h.question).font(.system(size: 13, weight: .medium))
                                    Text(h.answer).font(.system(size: 13)).textSelection(.enabled)
                                    HStack(spacing: 8) {   // 依据 + 「助教 · 20:26」 on one line
                                        if let line = Knowledge.sourceLine(h.sources ?? []) { SourceLine(text: line) }
                                        Spacer(minLength: 0)
                                        Text("\(h.actor) · \(h.time.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(AppTheme.textHint).fixedSize()
                                    }.padding(.top, 2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { Rectangle().fill(Ink.divider).frame(height: 0.5) }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    RecordsGroupTitle(text: "助教记录").padding(.top, store.answeredItems.isEmpty ? 6 : 0)
                    TaskTimeline(entries: store.activities)
                }
                if let course, !TranscriptRecords.paragraphs(course).isEmpty {   // the full stored transcript, selectable
                    VStack(alignment: .leading, spacing: 12) {
                        RecordsGroupTitle(text: "课堂转写")
                        TranscriptRecords(course: course)
                    }
                }
            }

        }
    }

}


/// Shared near-solid surface (big card spec): 92% white / dark-grey fill, 0.75pt gradient stroke, layered shadow.
struct SolidCard: ViewModifier {
    var cornerRadius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(DetailBoard.tint))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.42), .white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
                .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.14), radius: 24, x: 0, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 2)
    }
}


/// Assistant avatar for its own stream rows: circular crop of the HEAD of the currently selected pet.
/// Head = top square of the first frame's opaque bounds (side ≈ 34% of figure height), centred on the ink centroid of those rows.
struct AssistantAvatar: View {
    var pet: String
    var size: CGFloat = 18
    @MainActor private static var cache: [String: NSImage] = [:]
    @MainActor static func head(_ pet: String) -> NSImage? {
        if let c = cache[pet] { return c }
        guard let url = Bundle.module.url(forResource: pet, withExtension: "png"), let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let frame = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width / 4, height: cg.height / 8)) else { return nil }
        let w = frame.width, h = frame.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { p in
            CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        // Head box: top of figure → neck (narrowest row between the widest head row in the top 35% and 50% height).
        // Square = 1.32 × max(head w, h), nudged down 7% so chin and ears clear the circle. Verified on all 20 pets.
        var rows = [(Int, Int)?](repeating: nil, count: h)
        for y in 0..<h { var lo = -1, hi = -1; for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 24 { if lo < 0 { lo = x }; hi = x }; if lo >= 0 { rows[y] = (lo, hi) } }
        guard let top = rows.firstIndex(where: { $0 != nil }), let bottom = rows.lastIndex(where: { $0 != nil }), bottom > top + 8 else { return nil }
        let H = bottom - top
        func width(_ y: Int) -> Int { rows[y].map { $0.1 - $0.0 } ?? 0 }
        let hmax = (top..<(top + max(1, H * 35 / 100))).max { width($0) < width($1) } ?? top
        let neck = (hmax..<max(hmax + 1, top + H / 2)).min { width($0) < width($1) } ?? (top + H / 3)
        let headRows = (top..<max(top + 1, neck)).compactMap { rows[$0] }
        let x0 = headRows.map(\.0).min() ?? 0, x1 = headRows.map(\.1).max() ?? w
        // Wide brims/helmets (agriculture hat, astronaut helmet) would shrink the face: cap width at 1.2 × head height.
        let side = CGFloat(max(min(x1 - x0, (neck - top) * 6 / 5), neck - top)) * 1.32
        let cx = CGFloat(x0 + x1) / 2, cy = CGFloat(top + neck) / 2 + side * 0.07
        let rect = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side).integral
        guard let crop = frame.cropping(to: rect) else { return nil }
        let img = NSImage(cgImage: crop, size: NSSize(width: rect.width, height: rect.height))
        cache[pet] = img
        return img
    }
    var body: some View {
        Group {
            if let img = Self.head(pet) { Image(nsImage: img).resizable().interpolation(.high).scaledToFill() }
            else { AppTheme.accentGradient.overlay(Image(systemName: "sparkles").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)) }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(AppTheme.accent.opacity(0.12)))
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}


/// 「对助教说」 — inline section at the bottom of the bubble / big card (never a separate card).
struct CommandVoiceInline: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(voice.active ? Color.red : AppTheme.accent).frame(width: 7, height: 7)
                Text(voice.phase == "正在录音" ? "正在听" : voice.active ? voice.phase : store.busy ? "处理中" : "对助教说")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("取消") { store.dismissVoiceFeedback() }.font(.system(size: 11))
                    .buttonStyle(.plain).help(voice.active ? "取消录音" : "收起").disabled(store.busy)
            }
            if !voice.transcript.isEmpty {
                ScrollView { Text(voice.transcript).font(.system(size: 13)).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading) }
                    .defaultScrollAnchor(.bottom).frame(maxHeight: 60)
            } else { Text("正在听你说…").font(.system(size: 13)).foregroundStyle(Ink.secondary) }   // examples now a system message in the stream
        }
    }
}

/// Neutral avatar for system-generated messages/hints — distinct from the assistant's head crop.
struct SystemAvatar: View {
    var size: CGFloat = 18
    var body: some View {
        Circle().fill(Color.secondary.opacity(0.18))
            .overlay(Image(systemName: "info").font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(Ink.secondary))
            .frame(width: size, height: size)
    }
}


/// 16pt bottom fade on a ScrollView while more content sits below the visible area (macOS 15+; none before).
struct BottomFadeWhenOverflowing: ViewModifier {
    var height: CGFloat = 24
    @State private var moreBelow = false
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Bool.self) { g in g.contentSize.height - (g.contentOffset.y + g.containerSize.height) > 1 } action: { _, v in moreBelow = v }
                .mask {
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, moreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom).frame(height: height)
                    }
                }
        } else { content }
    }
}


/// 记录 tab group title: 13pt semibold secondary (settings-page system).
struct RecordsGroupTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.group) }
}

/// Big-card live status: soft red capsule, red text (下课 is a separate button).
struct LiveStatusCapsule: View {
    @ObservedObject var store: Store
    @State private var breathe = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(AppTheme.danger).frame(width: 5, height: 5).opacity(breathe ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: breathe)
            Text("直播中").font(.system(size: 11, weight: .semibold))
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PetView.elapsed(from: store.liveStart ?? context.date, to: context.date)).font(.system(size: 11, weight: .medium).monospacedDigit()).fixedSize()
            }
        }
        .foregroundStyle(AppTheme.danger)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(AppTheme.danger.opacity(0.12), in: Capsule())
        .onAppear { breathe = true }
    }
}


/// Item card inside the big card: light white + 4% shadow; dark #36363A + 0.5pt white-6% inner stroke.
struct BigCardItem: ViewModifier {
    var cornerRadius: CGFloat = 12
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(AppTheme.dyn(0x000000, 0xFFFFFF, 0.03, 0.05)))   // no stroke, no shadow
    }
}

/// Bubble ⇄ 助教工作台: the card grows up and left from its bottom-right corner (the bubble tail), content fades in;
/// collapse runs the same path back. All systems: the card surface is a solid fill (the glass id only morphs the glass layer),
/// so a plain crossfade would look like a second card appearing; scale from the bottom-right instead.
struct BubbleGrowTransition: ViewModifier {
    var width: CGFloat
    func body(content: Content) -> some View {
        // Surface: scales the whole 0.25s (content opacity is sequenced separately via cardContentOpacity).
        // Removal also fades the surface so the shrunk card doesn't pop out at the end.
        content.transition(.asymmetric(
            insertion: .scale(scale: 0.6, anchor: DetailBoard.tipAnchor(width: width)).animation(BubblesView.expandAnimation),
            removal: .scale(scale: 0.6, anchor: DetailBoard.tipAnchor(width: width)).animation(BubblesView.expandAnimation)))
    }
}

private struct CardContentOpacityKey: EnvironmentKey { static let defaultValue: Double = 1 }
extension EnvironmentValues {
    /// Opacity of a bubble / big card's content (not its surface), for the bubble ⇄ 工作台 content sequencing.
    var cardContentOpacity: Double { get { self[CardContentOpacityKey.self] } set { self[CardContentOpacityKey.self] = newValue } }
}

/// 下课: top-right of the bubble and the big card (same look in both). Outlined danger capsule.
struct EndClassButton: View {
    @ObservedObject var store: Store
    var plain = false   // kept for call sites; both places now use the same outlined capsule
    var body: some View {
        Button("下课") { LiveSessionControl.confirmEndClass(store: store) }
            .buttonStyle(DangerOutlineCapsuleButtonStyle())
            .help("结束上课")
    }
}

/// Outlined danger capsule: 24 high, 10 horizontal padding, 1pt danger @50% stroke, 13pt medium danger text,
/// danger 8% fill on hover (12% pressed).
struct DangerOutlineCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { OutlineLabel(configuration: configuration) }
    private struct OutlineLabel: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            let red = AppTheme.danger
            let shape = RoundedRectangle(cornerRadius: 12, style: .circular)   // = capsule at 24 high (Capsule's stroke rendered stray end ticks here)
            configuration.label
                .font(.system(size: 13, weight: .medium)).foregroundStyle(red)
                .padding(.horizontal, 10).frame(height: 24)
                .background(shape.fill(red.opacity(configuration.isPressed ? 0.12 : hovered ? 0.08 : 0)))
                .overlay(shape.strokeBorder(red.opacity(0.5), lineWidth: 1))
                .contentShape(shape)
                .fixedSize()   // never squeezed by the header (the capsule ends were being clipped)
                .onHover { hovered = $0 }
        }
    }
}

/// 「开始上课」 water drop: tinted glass body, top highlight, rotating specular rim (4s),
/// breathing scale + bottom glow (2.4s). Reduce Motion keeps only the static highlight.
struct WaterDropGlass: ViewModifier {
    var hovered = false
    /// false = 「对助教说」: same glass/tint/highlight, no rim shimmer, breathing or glow.
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = AppTheme.accent
    func body(content: Content) -> some View {
        let still = reduceMotion || !animated
        TimelineView(.animation(minimumInterval: 1 / 30, paused: still)) { t in
            let now = t.date.timeIntervalSinceReferenceDate
            let rim = still ? 0 : now.truncatingRemainder(dividingBy: 4) / 4 * 360
            let breath = still ? 0 : (1 - cos(now.truncatingRemainder(dividingBy: 4.8) / 4.8 * 2 * .pi)) / 2   // 0→1→0, 2.4s each way
            content
                .background { if animated { GeometryReader { g in
                    let k = 1 + 0.4 * breath   // breathing scales both layers' opacity
                    ZStack {
                        Ellipse().fill(accent.opacity(0.10 * k)).frame(width: g.size.width * 0.7, height: g.size.height * 0.6).blur(radius: 40)
                        Ellipse().fill(accent.opacity(0.18 * k)).frame(width: g.size.width * 0.7, height: g.size.height * 0.6).blur(radius: 24)
                    }.position(x: g.size.width / 2, y: g.size.height / 2 + 6 + g.size.height * 0.2)
                } } }
                .background { glass }
                .overlay { highlight.allowsHitTesting(false) }
                .overlay {
                    if animated {
                        Capsule().strokeBorder(AngularGradient(colors: [.white.opacity(0.7), accent.opacity(0.4), .clear, .white.opacity(0.7)], center: .center, angle: .degrees(rim)), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect((hovered ? 1.04 : 1.0) * (1 + 0.02 * breath))
        }
    }
    private var highlight: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: g.size.height / 2)
                Ellipse().fill(.white.opacity(0.35)).frame(width: g.size.width * 0.28, height: g.size.height * 0.32).blur(radius: 6).offset(x: g.size.width * 0.1, y: 3)
            }
        }.clipShape(Capsule())
    }
    @ViewBuilder private var glass: some View {
        // Base layer under the glass keeps it from reading grey/metallic on the transparent pet window.
        let base = Capsule().fill(AppTheme.dyn(0xFFFFFF, 0x2A2A2D, 0.35, 0.5))
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(accent.opacity(0.28)).interactive(), in: Capsule()).background(base)
        } else {
            Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(accent.opacity(0.28))).background(base)
        }
    }
}
struct WaterDropPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Big card: small red dot with faint halo + grey timer.
struct LiveDotTimer: View {
    @ObservedObject var store: Store
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(AppTheme.stopRed).frame(width: 6, height: 6)
                .background(Circle().fill(AppTheme.stopRed.opacity(0.18)).frame(width: 12, height: 12))
            Text("直播中").font(.system(size: 11)).foregroundStyle(Ink.secondary)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(PetView.elapsed(from: store.liveStart ?? context.date, to: context.date)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Ink.secondary).fixedSize()
            }
        }
    }
}

/// Native-look segmented control: grey track, white thumb (dark #636366).
struct SegmentedTabs<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var height: CGFloat = 22
    var fontSize: CGFloat = 11
    var badges: [T: Int] = [:]   // red count capsule after a segment's title, hidden at 0
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = selection == item.0
                Button { selection = item.0 } label: {
                    HStack(spacing: 4) {
                        Text(item.1).font(.system(size: fontSize, weight: on ? .medium : .regular)).foregroundStyle(on ? Ink.primary : Ink.secondary)
                        if let n = badges[item.0], n > 0 {
                            Text("\(n)").font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(.white)
                                .padding(.horizontal, 4).frame(minWidth: 14).frame(height: 14).background(AppTheme.danger, in: Capsule())
                        }
                    }
                        .frame(maxWidth: .infinity).frame(height: height)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Ink.segThumb)
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Ink.segStroke, lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Ink.segTrack))
    }
}


/// One 44pt row of the 开始上课 settings group: fixed 64pt title column, value right-aligned.
struct StartRow<Value: View>: View {
    var title: String
    var hovered: Bool
    var active: Bool
    @ViewBuilder var value: () -> Value
    var body: some View {
        HStack(spacing: 6) {   // 6pt between the value and its ›
            Text(title).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).frame(width: 64, alignment: .leading)
            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(hovered || active ? AppTheme.dyn(0x000000, 0xFFFFFF, 0.04, 0.06) : .clear)   // hover: black 4% / white 6%
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(active ? AppTheme.accent : .clear, lineWidth: 1))   // open / keyboard focus, drawn inside
        .contentShape(Rectangle())
    }
}

/// 0.5pt textHint 30% divider, starting at the 14pt left inset.
struct StartRowDivider: View {
    var body: some View { Rectangle().fill(AppTheme.textHint.opacity(0.3)).frame(height: 0.5).padding(.leading, 14) }
}

/// Dark only: 0.5pt white 10% hairline so the card edge reads against dark desktops. Light relies on the window shadow.
struct StartCardEdge: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: StartCard.radius, style: .continuous)
            .strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0), lineWidth: 0.5)
            .allowsHitTesting(false)
    }
}


/// Fades the last `height` points of a scrolling list into the card so nothing sits hard against the footer lines.
struct BottomEdgeFade: ViewModifier {
    var height: CGFloat
    func body(content: Content) -> some View {
        content.mask(VStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: height)
        })
    }
}

/// 课堂 footer: latest assistant activity, 24pt row, 16pt type avatar + 12pt secondary single line (tail-truncated).
/// Activity posts never appear in the 课堂 list (that shows questions / feedback only), so the row is not tappable.
struct ActivityLine: View {
    var message: PendingMessage
    var body: some View {
        HStack(spacing: 6) {
            if message.isSystem { SystemAvatar(size: 16) } else { MessageTypeBadge(type: message.typeBadge, side: 16) }
            VStack(alignment: .leading, spacing: 1) {
                Text(message.assistantVoiceTitle).font(.system(size: 12)).foregroundStyle(message.isError ? AppTheme.danger : AppTheme.textSecondary)
                    .lineLimit(1).truncationMode(.tail)
                if let echo = message.commandEcho {
                    Text(echo).font(.system(size: 11)).foregroundStyle(AppTheme.textHint).lineLimit(1).truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// Live transcript caption at the very bottom of the 工作台 (all tabs): latest sentence only, 13pt textSecondary 70%,
/// overflow scrolls out to the left under a 24pt fade; textHint after 10s without new speech; hidden when there is none.
struct TranscriptCaption: View {
    @ObservedObject var store: Store
    @ObservedObject private var voice: VoiceSession
    var course: CourseSession?
    /// 工作台 13pt / 28pt row; the small bubble uses 12pt / 22pt.
    var fontSize: CGFloat = 13
    var lineHeight: CGFloat = 28
    init(store: Store, course: CourseSession?, fontSize: CGFloat = 13, lineHeight: CGFloat = 28) {
        self.store = store; self.course = course; self.voice = store.liveVoice; self.fontSize = fontSize; self.lineHeight = lineHeight
    }
    private var currentLine: (text: String, time: Date)? {
        guard store.connected || store.demo, let course, course.ended == nil else { return nil }
        if voice.active {
            if voice.phase != "正在录音" && voice.phase != "识别中" { return (voice.phase, Date()) }
            if let text = Self.latestSentence(voice.caption) { return (text, voice.captionTime) }
            return ("等待课堂声音…", Date())
        }
        if store.pausedLiveForCommand { return ("课堂转写已暂停", Date()) }
        if !store.recordingError.isEmpty { return ("麦克风转写不可用", Date()) }
        return Self.sentence(store: store, course: course)
    }
    static let terminators = CharacterSet(charactersIn: "。！？!?；;\n")
    /// Latest sentence of the live class transcript, or nil (not live / nothing transcribed yet).
    @MainActor static func sentence(store: Store, course: CourseSession?) -> (text: String, time: Date)? {
        guard store.connected || store.demo, let course, course.ended == nil else { return nil }
        let text: String, time: Date
        if let seg = course.transcriptSegments?.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { text = seg.text; time = seg.time }
        else { text = String(course.transcript.suffix(400)); time = course.started }
        guard let latest = latestSentence(text) else { return nil }
        return (latest, time)
    }
    static func latestSentence(_ raw: String) -> String? {
        let parts = raw.components(separatedBy: terminators).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.last
    }
    var body: some View {
        if let line = currentLine {
            TimelineView(.periodic(from: .now, by: 1)) { clock in
                let stale = clock.date.timeIntervalSince(line.time) > 10
                ViewThatFits(in: .horizontal) {
                    Text(line.text).lineLimit(1).fixedSize().frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.overlay(alignment: .trailing) { Text(line.text).lineLimit(1).fixedSize() }.clipped()
                        .mask(HStack(spacing: 0) { LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 24); Rectangle().fill(.black) })
                }
                .font(.system(size: fontSize))
                .foregroundStyle(stale ? AnyShapeStyle(AppTheme.textHint) : AnyShapeStyle(AppTheme.textSecondary.opacity(0.7)))
                .animation(.easeOut(duration: 0.2), value: stale)
            }
            .frame(height: lineHeight)
            .animation(.easeOut(duration: 0.2), value: line.text)
            .allowsHitTesting(false)
            .accessibilityLabel("实时字幕：" + line.text)
        }
    }
}
