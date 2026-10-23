import SwiftUI
import AppKit
import Combine
import AssistantCore

@main enum AssistantApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = Delegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Borderless window that can still take key (typing, Return / Esc) — used by the 开始上课 card.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FloatingPanel: NSPanel {
    /// false: pet and message cards never take key, so a click can't flip glass/vibrancy between
    /// its inactive and active look. true: panels with text input (action card, answer bar).
    var keyable = true
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = Store(preview: CommandLine.arguments.contains("--preview"))
    var pet: NSPanel!
    var bubbles: NSPanel!
    var card: NSPanel?
    var settings: NSWindow?
    private var statusIconWatch: AnyCancellable?
    var start: NSWindow?
    var statusItem: NSStatusItem?
    var subscriptions = Set<AnyCancellable>()
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for path in filenames where URL(fileURLWithPath: path).pathExtension == "xblesson" { store.importLesson(URL(fileURLWithPath: path)) }
        if pet != nil { openSettings() }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dev: --export-avatars <dir> writes each pet's circular head avatar (as shown in the stream) for inspection, then quits.
        if let i = CommandLine.arguments.firstIndex(of: "--export-avatars"), i + 1 < CommandLine.arguments.count {
            let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for pet in PetAppearance.all where Bundle.module.url(forResource: pet.id, withExtension: "png") != nil {
                let r = ImageRenderer(content: AssistantAvatar(pet: pet.id, size: 160).padding(4).background(Color.white)); r.scale = 1
                if let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(pet.id).png"))
                }
            }
            exit(0)
        }
        if CommandLine.arguments.contains("--preview-screen") && PreviewScreen.target == nil { exit(2) }   // never fall back to the user's screen
        NSApp.setActivationPolicy(PreviewScreen.target == nil ? .regular : .accessory)   // offscreen preview: no Dock icon
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出小保助教", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        pet = panel(width: PetView.windowWidth, height: 216, keyable: false)
        pet.title = "桌宠"; pet.isMovableByWindowBackground = true; pet.delegate = self; pet.appearance = NSAppearance(named: .darkAqua)   // always dark, independent of the theme setting
        pet.contentView = InteractiveHostingView(rootView: PetView(store: store, voice: store.voice, settings: { [weak self] in self?.openSettings() }, courses: { [weak self] in self?.store.settingsPage = "教室"; self?.openSettings() }, start: { [weak self] in self?.openStart() }, command: { [weak self] in self?.store.talkToAssistant() }).environment(\.colorScheme, .dark).environment(\.controlActiveState, .key).tint(AppTheme.accent))
        let screen = (PreviewScreen.target ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        pet.setFrameOrigin(NSPoint(x: screen.maxX - 240 - PetView.windowInset, y: screen.minY + 55)); pet.orderFrontRegardless()
        bubbles = panel(width: 342, height: 420, keyable: false); bubbles.title = "助教工作台"; bubbles.appearance = NSAppearance(named: .darkAqua); bubbles.contentView = InteractiveHostingView(rootView: BubblesView(store: store, voice: store.voice).environment(\.colorScheme, .dark).environment(\.controlActiveState, .key).tint(AppTheme.accent))
        if PreviewScreen.target == nil { installStatusMenu() }   // offscreen preview: nothing in the menu bar
        store.showCard = { [weak self] in self?.openCard() }
        store.showStart = { [weak self] in self?.openStart() }
        store.showBroadcastDesktop = { [weak self] in
            guard let self else { return }
            self.settings?.orderOut(nil)
            self.start?.orderOut(nil)
            self.pet.orderFrontRegardless()
        }
        store.objectWillChange.merge(with: store.voice.objectWillChange).sink { [weak self] in
            DispatchQueue.main.async { self?.refreshBubbles() }
        }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--dark") { store.saved.preferences.appearance = "dark" }
        if let i = CommandLine.arguments.firstIndex(of: "--pet"), i + 1 < CommandLine.arguments.count { store.saved.preferences.pet = CommandLine.arguments[i + 1] }
        store.applyAppearance()
        if CommandLine.arguments.contains("--preview") {
            store.demoSession()
            if CommandLine.arguments.contains("--preview-room-agent") { store.prepareRoomPreview() }
            if CommandLine.arguments.contains("--preview-data") { store.prepareDataPreview() }
            if CommandLine.arguments.contains("--preview-preparation") { store.preparePreparationPreview() }
            if CommandLine.arguments.contains("--preview-tools") { store.prepareToolsPreview() }
            if CommandLine.arguments.contains("--preview-overflow") {   // dev: enough chat lines to overflow the bubble cap
                store.publicMessages += (1...10).map { ClassroomMessage(id: "preview-chat-\($0)", userID: "v\($0)", name: "观众\($0)", text: "第 \($0) 条弹幕：老师讲得很清楚") }
            }
            if let pageIndex = CommandLine.arguments.firstIndex(of: "--page"), pageIndex + 1 < CommandLine.arguments.count {
                store.settingsPage = Store.restoredSettingsPage(CommandLine.arguments[pageIndex + 1])
            }
            if CommandLine.arguments.contains("--preview-panel-window") {
                store.detailBoardHeight = 620
                let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                w.title = "实时面板验收"; w.isReleasedWhenClosed = false
                w.contentView = InteractiveHostingView(rootView: DetailBoard(store: store).tint(AppTheme.accent)); settings = w
                w.center(); if let s = PreviewScreen.target?.visibleFrame { w.setFrameOrigin(NSPoint(x: s.midX - 410, y: s.midY - 310)) }
                w.makeKeyAndOrderFront(nil); PreviewScreen.activateApp()
            }
            else if CommandLine.arguments.contains("--preview-detail") { store.setDetail(true) }
            else if CommandLine.arguments.contains("--preview-max") { store.maximizeDetail() }
            else if CommandLine.arguments.contains("--preview-bubble-after-new-class") {
                // Virtual-screen QA: leave prior-class junk, then reset like a fresh 开课 — bubble should be empty aside from welcome.
                // demoSession() ran above (demo=true); ensureCourse refuses demo, so leave demo for a real in-class shell.
                store.demo = false
                store.collapsePending()
                store.connected = true
                store.ensureCourse()
                if let courseID = store.currentCourseID, let i = store.saved.courses.firstIndex(where: { $0.id == courseID }) {
                    store.saved.courses[i].transcript = "上一场还在讲的内容，不该出现在新气泡字幕里。"
                    store.saved.courses[i].transcriptSegments = [TranscriptSegment(text: "上一场还在讲的内容，不该出现在新气泡字幕里。")]
                    store.addInteraction(LiveInteraction(kind: .notice, platformID: "old-notice", content: "旧场公告"), courseID: courseID)
                    store.messages.append(PendingMessage(kind: .question, title: "旧场待答", question: "这是上一场留下来的问题", people: ["小林"]))
                    store.flow("已忽略", detail: "旧场动态不该留在新课气泡。")
                    // Mark ended without finishCourse archive Task (runtime guards cover that path).
                    store.saved.courses[i].ended = Date()
                    store.currentCourseID = nil
                }
                store.resetLiveBubbleState()
                store.demo = false
                store.connected = true
                store.ensureCourse()
                store.announceClassStarted()
            }
            else if CommandLine.arguments.contains("--preview-bubble-crowded") {
                // Virtual-screen QA: fill the middle list so the bottom dock (stream + caption) must stay put.
                store.collapsePending()
                let extras: [(PendingMessage.Kind, String, String, [String])] = [
                    (.question, "回放多久能看？", "回放大概多久能在课程页看到？", ["小林", "阿晨"]),
                    (.question, "作业交到哪里？", "课后作业交到哪个入口？", ["小许"]),
                    (.material, "要第三章课件", "能发一下第三章课件吗？", ["小陈"]),
                    (.question, "证书怎么领？", "结业证书在哪里领取？", ["小周", "小张"]),
                    (.technical, "画面有点卡", "老师那边画面卡顿，这边也跟着卡。", ["阿晨"]),
                    (.question, "下次什么时候开课？", "下一场直播大概什么时间？", ["小林"]),
                    (.risk, "疑似广告", "加微信领资料包，限时优惠。", ["游客12"]),
                    (.question, "能不能调慢一点？", "老师讲得有点快，能稍微慢一点吗？", ["小陈", "小许"]),
                ]
                for item in extras {
                    store.messages.append(PendingMessage(kind: item.0, title: item.1, question: item.2, people: Set(item.3)))
                }
                if let courseID = store.currentCourseID {
                    store.addInteraction(LiveInteraction(kind: .notice, platformID: "preview-notice", content: "今晚 21:00 答疑加时，欢迎继续提问"), courseID: courseID)
                    store.addInteraction(LiveInteraction(kind: .checkin, platformID: "preview-checkin", content: "请大家点一下签到"), courseID: courseID)
                }
                store.flow("已忽略", detail: "声音太轻了，我都把音量拉满了。")
                store.flow("已忽略", detail: "我这边也听不清，音量好小。")
            }
            else if CommandLine.arguments.contains("--preview-bubble") { store.collapsePending() }
            else if CommandLine.arguments.contains("--preview-voice") { store.collapsePending(); store.commandVoiceVisible = true; store.postSystem("对助教说", "你可以这样说：" + CapabilitiesSettingsView.voiceExamples.map { "「\($0)」" }.joined(separator: "、")) }
            else if CommandLine.arguments.contains("--preview-card"), let first = store.messages.first { store.open(first.id) }
            else if CommandLine.arguments.contains("--preview-view-card"), let v = store.messages.first(where: { $0.responseType == .view }) { store.open(v.id) }
            else if CommandLine.arguments.contains("--preview-start") { openStart() }
            else { openSettings() }
        }
        else { bubbles.orderOut(nil) }
    }
    private func installStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        updateStatusIcon(inClass: store.connected)
        statusIconWatch = store.$connected.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] inClass in self?.updateStatusIcon(inClass: inClass) }
        let menu = NSMenu()
        for (title, action) in [("开始上课", #selector(startFromMenu)), ("设置", #selector(settingsFromMenu)), ("教室", #selector(coursesFromMenu))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出小保助教", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
    }
    /// Idle: grey `graduationcap`. In class: `graduationcap.fill` in the normal menu-bar color plus a green dot.
    func updateStatusIcon(inClass: Bool) {
        guard let button = statusItem?.button else { return }
        button.toolTip = inClass ? "小保助教 · 上课中" : "小保助教"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if !inClass {
            // Template image dimmed by the system (designer: no hardcoded grey).
            let image = NSImage(systemSymbolName: "graduationcap", accessibilityDescription: "小保助教")?.withSymbolConfiguration(config)
            image?.isTemplate = true
            button.contentTintColor = nil
            button.image = image
            button.appearsDisabled = true
            return
        }
        button.appearsDisabled = false
        guard let symbol = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: "小保助教 · 上课中")?.withSymbolConfiguration(config) else { return }
        let size = NSSize(width: max(symbol.size.width, 18), height: max(symbol.size.height, 16))
        // Drawn at display time so labelColor follows light/dark menu bars; not a template, so the dot stays green.
        let image = NSImage(size: size, flipped: false) { rect in
            let glyph = NSRect(x: (rect.width - symbol.size.width) / 2, y: (rect.height - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
            let tinted = NSImage(size: symbol.size, flipped: false) { r in
                symbol.draw(in: r); NSColor.labelColor.set(); r.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: glyph)
            let d: CGFloat = 6
            let dot = NSRect(x: rect.maxX - d, y: rect.minY, width: d, height: d)
            NSColor.clear.set()
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()   // small gap around the dot
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1, dy: -1)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemGreen.set(); NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        button.contentTintColor = nil
        button.image = image
    }
    @objc private func startFromMenu() { openStart() }
    @objc private func settingsFromMenu() { openSettings() }
    @objc private func coursesFromMenu() { store.settingsPage = "教室"; openSettings() }
    func panel(width: CGFloat, height: CGFloat, keyable: Bool = true) -> NSPanel {
        let window = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.keyable = keyable
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false
        return window
    }
    func windowWillClose(_ notification: Notification) { if (notification.object as? NSWindow) === settings { pet.makeKeyAndOrderFront(nil) } }
    /// Ordinary maximize (green button / titlebar double-click): fill screen visibleFrame — menu bar & Dock stay; never toggleFullScreen.
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame: NSRect) -> NSRect {
        guard window === settings else { return defaultFrame }
        return window.screen?.visibleFrame ?? defaultFrame
    }
    func windowDidMove(_ notification: Notification) { if (notification.object as? NSWindow) === pet { placeBubbles() } }
    func placeBubbles() {
        guard pet != nil, bubbles != nil else { return }
        let size = bubbles.frame.size
        guard !store.detailExpanded else { return }   // big card is free-floating; only the bubble follows the pet
        bubbles.setFrameOrigin(bubbleOrigin(for: size))
    }
    /// Top-centre of the pet's head in screen coords (sprite 164pt, top-aligned ~1pt in the 216pt window; art starts ~10pt down).
    var petHeadTop: NSPoint { NSPoint(x: pet.frame.midX, y: pet.frame.maxY - 8) }   // measured: hair top ≈ 8pt below window top
    /// Bubble: tail tip 12pt above the head top, slightly left; panel: bottom-right ~12pt off the head's upper-left.
    func bubbleOrigin(for size: NSSize) -> NSPoint {
        let head = petHeadTop, pad: CGFloat = 22
        if store.pendingIsCompact {
            let tipX = head.x - 6, tipY = head.y + 14   // measured 12pt tip→hair
            return NSPoint(x: tipX - pad - CollapsedPendingBubble.tipX, y: tipY - pad)
        }
        let corner = NSPoint(x: head.x - 20, y: head.y - 6)   // measured ≈12pt from panel corner curve to hair
        return NSPoint(x: corner.x + pad - size.width, y: corner.y - pad)
    }
    /// Panel content height: min(720, space above the anchor - 24), floor 480.
    func panelContentHeight() -> CGFloat {
        let screen = pet.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let bottom = petHeadTop.y - 6 - 22
        return min(720, max(480, screen.maxY - bottom - 24))
    }
    var bigCardPlaced = false
    /// Latest bubble-window resize request; a delayed collapse resize is dropped if a newer one came in.
    var resizeToken = UUID()
    /// Grow up and left from the small bubble, preserving its bottom-right anchor.
    /// Subsequent updates preserve the user's dragged position, bounded by the visible screen.
    func bigCardFrame(extra: CGFloat, placed: NSRect? = nil) -> (NSSize, NSPoint) {
        let screen = (bubbles.screen ?? assistantScreen).visibleFrame
        // Compact workbench: card 520 wide, height = half screen clamped 420…480 (+22pt shadow margin each side).
        let w = min(520 + 44, screen.width - 24)
        let h = min(min(max(screen.height / 2, 420), 480) + 44 + extra, screen.height - 24)
        let anchor = placed ?? bubbles.frame
        let x = placed == nil ? anchor.maxX - w : anchor.minX
        let y = placed == nil ? anchor.minY : anchor.maxY - h
        let origin = NSPoint(
            x: min(max(x, screen.minX + 12), screen.maxX - w - 12),
            y: min(max(y, screen.minY + 12), screen.maxY - h - 12)
        )
        return (NSSize(width: w, height: h), origin)
    }
    func maximizedSize() -> NSSize {
        let screen = pet.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        return NSSize(width: screen.width * 0.8, height: screen.height * 0.8)
    }
    func maximizedOrigin(for size: NSSize) -> NSPoint {
        let screen = pet.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        return NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
    }
    /// View / reply popups: bottom-centre of the screen with the mouse, 24pt above the visible frame's bottom.
    func bottomCenter(for size: NSSize) -> NSPoint {
        let screen = assistantScreen.visibleFrame
        return NSPoint(x: screen.midX - size.width / 2, y: screen.minY + 24)
    }
    /// Screen that currently contains the mouse cursor (fallback: pet's screen).
    var assistantScreen: NSScreen {
        pet?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    }
    /// Channel popup: horizontally centered on the mouse's screen; center at ~58% of usable height.
    func startCardOrigin(for size: NSSize) -> NSPoint {
        let screen = assistantScreen.visibleFrame
        let x = screen.midX - size.width / 2
        let centerY = screen.minY + screen.height * 0.42   // AppKit y grows up; 58% from top ≈ 42% from bottom
        return NSPoint(x: x, y: centerY - size.height / 2)
    }
    func position(_ window: NSWindow) {
        let screen = pet.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = pet.frame.minX + PetView.windowInset - window.frame.width - 18
        window.setFrameOrigin(NSPoint(x: min(max(screen.minX + 16, x), screen.maxX - window.frame.width - 16), y: min(max(screen.minY + 16, pet.frame.minY + 35), screen.maxY - window.frame.height - 16)))
    }
    func openCard() {
        if let id = store.selected, let m = store.messages.first(where: { $0.id == id }), m.kind == .question { openAnswerBar(); return }
        if card == nil { card = panel(width: 410, height: 440); card?.hasShadow = false; card?.appearance = NSAppearance(named: .darkAqua) }
        card?.contentView = InteractiveHostingView(rootView: ActionCard(store: store, voice: store.voice, close: { [weak self] in self?.card?.orderOut(nil); self?.store.cancelCommandVoice() }).environment(\.colorScheme, .dark).environment(\.controlActiveState, .key).tint(AppTheme.accent))
        // Non-activating panel: takes key for typing without pushing the user's current app back.
        if let card { card.setFrameOrigin(bottomCenter(for: card.frame.size)); card.makeKeyAndOrderFront(nil) }
    }
    var answerBar: NSPanel?
    func openAnswerBar() {
        card?.orderOut(nil)
        if answerBar == nil { answerBar = panel(width: 640, height: min(480, assistantScreen.visibleFrame.height - 48)) }   // question context above, input below
        answerBar?.appearance = NSAppearance(named: .darkAqua)
        answerBar?.contentView = InteractiveHostingView(rootView: AnswerBar(store: store, voice: store.voice, close: { [weak self] in self?.answerBar?.orderOut(nil); self?.store.cancelCommandVoice() }).environment(\.colorScheme, .dark).environment(\.controlActiveState, .key).tint(AppTheme.accent))
        if let bar = answerBar { bar.setFrameOrigin(bottomCenter(for: bar.frame.size)); bar.makeKeyAndOrderFront(nil) }   // key for typing, app not activated
    }
    private func refreshBubbles() {
        if !store.showLessonCards { bubbles.orderOut(nil); bigCardPlaced = false }
        else {
            let size: NSSize
            let origin: NSPoint
            if store.detailExpanded {
                (size, origin) = bigCardFrame(extra: 0, placed: bigCardPlaced ? bubbles.frame : nil)
                bigCardPlaced = true
                let board = size.height - 44
                store.detailBoardWidth = size.width - 44
                if abs(store.detailBoardHeight - board) > 0.5 { store.detailBoardHeight = board }
            } else {
                bigCardPlaced = false
                let showBubble = store.showLessonCards
                let bubbleH: CGFloat = showBubble ? CollapsedPendingBubble.height(for: store) + CollapsedPendingBubble.tail + 10 + (store.commandVoiceVisible ? CollapsedPendingBubble.voiceExtra : 0) : 0
                size = NSSize(width: 324, height: bubbleH + 44)
                origin = bubbleOrigin(for: size)
            }
            if bubbles.frame.size != size || abs(bubbles.frame.origin.x - origin.x) > 0.5 || abs(bubbles.frame.origin.y - origin.y) > 0.5 {
                // Bubble ⇄ big card is one transparent window. Its bottom-right stays put (bigCardFrame anchors maxX / minY);
                // the visible card animates inside it in SwiftUI (0.25s easeOut, BubblesView.boardShown).
                // Expand: grow the window at once (empty transparent area), then the card grows up-left into it.
                // Collapse: let the card shrink back first, then shrink the window.
                let collapsing = !store.detailExpanded && bubbles.isVisible && bubbles.frame.width > size.width + 1
                let target = NSRect(origin: origin, size: size)
                resizeToken = UUID()
                if collapsing {
                    let token = resizeToken
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) { [weak self] in
                        guard let self, self.resizeToken == token, !self.store.detailExpanded else { return }
                        self.bubbles.setFrame(target, display: true, animate: false)
                    }
                } else {
                    bubbles.setFrame(target, display: true, animate: false)
                }
            } else { placeBubbles() }
            if start?.isVisible != true { bubbles.orderFrontRegardless() }
        }
        if store.selected == nil { card?.orderOut(nil) }
    }
    func openSettings() {
        if settings == nil {
            let w = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            configureTitlelessWindow(w)
            // Finder/Safari-style maximize only — never enter a fullscreen Space.
            w.collectionBehavior.insert(.fullScreenNone)
            w.title = "小保助教设置"; w.delegate = self; w.isReleasedWhenClosed = false; w.contentView = InteractiveHostingView(rootView: SettingsView(store: store).ignoresSafeArea(.container, edges: .top).tint(AppTheme.accent)); settings = w
        }
        settings?.placeOnAssistantScreen()
        settings?.initialFirstResponder = settings?.contentView
        settings?.makeKeyAndOrderFront(nil); PreviewScreen.activateApp()
        // Root cause of "Settings jumps into the 小保 field": the hosting view refuses first responder, so AppKit
        // hands focus to the first key view — the 助教昵称 TextField (placeholder 「如：小保」). Clear focus instead,
        // now and again after SwiftUI's own deferred focus pass.
        if let settings { settings.makeFirstResponder(nil) }
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let settings = self?.settings, settings.isKeyWindow else { return }
                if settings.firstResponder is NSText || settings.firstResponder is NSTextView { settings.makeFirstResponder(nil) }
            }
        }
    }
    func openStart() {
        guard !store.connected else { start?.orderOut(nil); return }
        if start?.isVisible != true { store.libraryIDs = [] }
        if start == nil {
            // Borderless, transparent, exactly card-sized: the system shadow follows the card's r16 alpha edge,
            // so there is no rectangular backing or halo (the old titled window + SwiftUI shadow + 22pt margin drew one).
            let w = KeyableWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 480), styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = true; w.isMovableByWindowBackground = true
            w.title = "开始上课"; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)   // always dark, like the pet / bubbles
            let host = InteractiveHostingView(rootView: StartCard(store: store, settings: { [weak self] in self?.openSettings() }, close: { [weak self, weak w] in w?.orderOut(nil); if let self, !self.store.messages.isEmpty || !self.store.notice.isEmpty { self.bubbles.orderFrontRegardless() } }).ignoresSafeArea().environment(\.colorScheme, .dark).tint(AppTheme.accent))
            host.wantsLayer = true; host.layer?.cornerRadius = StartCard.radius; host.layer?.cornerCurve = .continuous; host.layer?.masksToBounds = true
            w.contentView = host; w.setContentSize(host.fittingSize); w.invalidateShadow(); start = w
        }
        bubbles?.orderOut(nil)
        if let start {
            let size = start.frame.size
            start.setFrameOrigin(startCardOrigin(for: size))
            start.makeKeyAndOrderFront(nil)
        }
        PreviewScreen.activateApp()
    }
    private func configureTitlelessWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
    }
    func applicationWillTerminate(_ notification: Notification) { store.connectionTask?.cancel(); store.roomTasks.values.forEach { $0.cancel() }; store.questionBankTasks.values.forEach { $0.cancel() }; store.voice.cancel(); store.liveVoice.cancel(); store.finishCourse(); store.cancelDataTasks(); store.gateway.disconnect(); store.persist() }
}

/// Settings window: zoom toggles between user frame and screen.visibleFrame (Finder/Safari-style maximize, not Spaces fullscreen).
/// Title is hidden + fullSizeContentView, so the SwiftUI host receives titlebar clicks and AppKit never sees a
/// "titlebar double-click". sendEvent re-creates it for the top strip; the brand header calls toggleMaximize() too.
final class SettingsWindow: NSWindow {
    private var frameBeforeZoom: NSRect?
    /// Height of the draggable top strip (titlebar area, ≈28–32pt).
    var titlebarBand: CGFloat { max(28, frame.height - contentLayoutRect.height) }

    private func isNearlyMaximized(_ target: NSRect) -> Bool {
        let t: CGFloat = 24   // tolerate min-size / rounding / animation drift
        return abs(frame.minX - target.minX) < t && abs(frame.minY - target.minY) < t
            && abs(frame.width - target.width) < t && abs(frame.height - target.height) < t
    }

    override func zoom(_ sender: Any?) { toggleMaximize() }

    func toggleMaximize() {
        guard let screen = screen ?? NSScreen.main else { return }
        if styleMask.contains(.fullScreen) { toggleFullScreen(nil); return }   // never stay in a fullscreen Space
        let target = screen.visibleFrame
        let maxed = isNearlyMaximized(target)
        NSLog("SettingsWindow.zoom maxed=%@ frame=%@ target=%@ saved=%@", maxed ? "YES" : "NO",
              NSStringFromRect(frame), NSStringFromRect(target), frameBeforeZoom.map { NSStringFromRect($0) } ?? "nil")
        if maxed {
            var restore = frameBeforeZoom ?? NSRect(x: 0, y: 0, width: min(1180, target.width - 80), height: min(760, target.height - 80))
            if frameBeforeZoom == nil || !target.intersects(restore) {
                restore.origin = NSPoint(x: target.midX - restore.width / 2, y: target.midY - restore.height / 2)
            }
            frameBeforeZoom = nil
            setFrame(restore, display: true, animate: true)
        } else {
            frameBeforeZoom = frame
            setFrame(target, display: true, animate: true)
        }
    }

    /// Honour System Settings › Desktop & Dock › "Double-click a window's title bar to" (default: zoom/fill).
    private func performTitlebarDoubleClick() {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize": miniaturize(nil)
        case "None": break
        default: toggleMaximize()
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2 {
            let p = event.locationInWindow
            let inBand = p.y >= frame.height - titlebarBand
            let onTrafficLight = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].contains { type in
                guard let b = standardWindowButton(type), b.superview != nil else { return false }
                return b.convert(b.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(p)
            }
            if inBand && !onTrafficLight {
                performTitlebarDoubleClick()
                return
            }
        }
        super.sendEvent(event)
    }
}

extension NSWindow {
    @MainActor func placeOnAssistantScreen() {
        let screen = (NSApp.delegate as? Delegate)?.assistantScreen ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let size = NSSize(width: min(frame.width, area.width - 32), height: min(frame.height, area.height - 32))
        setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: false)
    }
}

/// Dev screenshots: `--preview --preview-screen <CGDirectDisplayID>` keeps every window on that (virtual) display,
/// never activates the app and adds no Dock or menu-bar item, so nothing appears on the user's desktop.
@MainActor enum PreviewScreen {
    static let target: NSScreen? = {
        let args = CommandLine.arguments
        guard args.contains("--preview"), let i = args.firstIndex(of: "--preview-screen"), i + 1 < args.count, let id = UInt32(args[i + 1]) else { return nil }
        return NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }()
    static func activateApp() { if target == nil { NSApp.activate(ignoringOtherApps: true) } }
}
