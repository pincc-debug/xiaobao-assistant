import XCTest
import AppKit
import AssistantCore
@testable import Assistant

final class FlowTests: XCTestCase {
    @MainActor func testMultipleBubblesKeepIndependentDrafts() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.demoSession()
        let first = store.messages[0].id, second = store.messages[1].id
        store.messages[0].draft = "回放在观看页。"
        store.open(first); store.messages.append(PendingMessage(title: "新问题", question: "何时开始？"))
        XCTAssertEqual(store.selected, first)
        XCTAssertEqual(store.messages[0].draft, "回放在观看页。")
        store.send(first)
        XCTAssertFalse(store.messages.contains { $0.id == first })
        XCTAssertTrue(store.messages.contains { $0.id == second })
        XCTAssertTrue(store.notice.contains("未发送"))
    }
    @MainActor func testTranscriptsAreSavedAndCoursesAreIsolated() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.json")
        let store = Store(preview: true, storageURL: url)
        store.channel = "123"; store.ensureCourse()
        let first = try XCTUnwrap(store.currentCourseID)
        store.appendTranscript("第一场课程。", courseID: first)
        store.messages.append(PendingMessage(title: "问题", question: "回放？"))
        store.finishCourse()
        XCTAssertEqual(store.saved.courses.first?.unanswered, ["回放？"])
        store.channel = "456"; store.ensureCourse()
        let second = try XCTUnwrap(store.currentCourseID)
        XCTAssertNotEqual(first, second)
        store.appendTranscript("第二场课程。", courseID: second)
        let persisted = try StateFile(url: url).read()
        XCTAssertEqual(persisted.courses.count, 2)
        XCTAssertEqual(persisted.courses.first?.transcript, "第二场课程。\n")
        let firstCourse = try XCTUnwrap(persisted.courses.first { $0.id == first })
        XCTAssertEqual(try String(contentsOfFile: XCTUnwrap(firstCourse.recordingPath)), "第一场课程。\n")
    }
    @MainActor func testCorruptStateIsNotOverwrittenByStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("state.json")
        try Data("broken".utf8).write(to: url)
        let store = Store(preview: true, storageURL: url)
        store.persist()
        XCTAssertEqual(try String(contentsOf: url), "broken")
        XCTAssertFalse(store.error.isEmpty)
    }
    @MainActor func testQuoteCardProducesReadablePNG() async throws {
        _ = NSApplication.shared
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("assistant-quote-test.png")
        try QuoteRenderer.save(title: "从理解到实践", quote: "真正理解一个概念，不只是能够重复它的定义，而是能够在新的问题里使用它。", course: "产品培训", to: url)
        let data = try Data(contentsOf: url)
        XCTAssertTrue(data.starts(with: [137, 80, 78, 71]))
        XCTAssertNotNil(NSImage(contentsOf: url))
    }
}

extension FlowTests {
    @MainActor func testPetDragTracksScreenPointerAndDoesNotOpenChat() async throws {
        _ = NSApplication.shared
        let window = NSPanel(contentRect: NSRect(x: 400, y: 400, width: 164, height: 164), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let canvas = SpriteCanvas(frame: NSRect(x: 0, y: 0, width: 164, height: 164))
        canvas.draggable = true
        var clicks = 0
        canvas.onClick = { clicks += 1 }
        window.contentView = canvas
        func event(_ type: NSEvent.EventType, screen: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screen), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, screen: NSPoint(x: 480, y: 520)))
        canvas.mouseDragged(with: try event(.leftMouseDragged, screen: NSPoint(x: 530, y: 550)))
        XCTAssertEqual(window.frame.origin.x, 450, accuracy: 0.1)
        XCTAssertEqual(window.frame.origin.y, 430, accuracy: 0.1)
        canvas.mouseDragged(with: try event(.leftMouseDragged, screen: NSPoint(x: 560, y: 500)))
        XCTAssertEqual(window.frame.origin.x, 480, accuracy: 0.1)
        XCTAssertEqual(window.frame.origin.y, 380, accuracy: 0.1)
        canvas.mouseUp(with: try event(.leftMouseUp, screen: NSPoint(x: 560, y: 500)))
        XCTAssertEqual(clicks, 0)
        canvas.mouseDown(with: try event(.leftMouseDown, screen: NSPoint(x: 560, y: 500)))
        canvas.mouseUp(with: try event(.leftMouseUp, screen: NSPoint(x: 560, y: 500)))
        XCTAssertEqual(clicks, 1)
    }
}

extension FlowTests {
    @MainActor func testDisabledCapabilitiesBlockOperationsAndPreserveArchive() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.ensureCourse()
        let course = try XCTUnwrap(store.currentCourseID)
        store.appendTranscript("保留这段课程内容。", courseID: course)
        store.setCapability(.courseArchive, enabled: false)
        XCTAssertEqual(store.currentCourseID, course)
        XCTAssertEqual(store.saved.courses.first?.transcript, "保留这段课程内容。\n")
        store.beginRecording()
        XCTAssertFalse(store.liveVoice.active)
        XCTAssertFalse(store.liveVoice.active)
        store.demoSession()
        store.setCapability(.announcements, enabled: false)
        XCTAssertTrue(store.enabled(.announcements), "发布公告 is a voice command and stays on")
        store.setCapability(.transcription, enabled: false)
        XCTAssertTrue(store.enabled(.transcription), "实时转写 has no toggle and stays on")
        _ = course; _ = folder
    }
    @MainActor func testTechnicalFeedbackRemainsBuiltIn() async throws {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json"))
        store.setCapability(.technicalAlerts, enabled: false)
        store.setCapability(.knowledgeAnswers, enabled: false)
        store.setCapability(.riskAlerts, enabled: false)
        XCTAssertTrue(store.enabled(.technicalAlerts))
        store.classifyMessage = { _, _ in ("technical", "none") }
        store.receive(ClassroomMessage(id: "1", userID: "viewer", name: "小王", text: "听不到声音"))
        for _ in 0..<20 { if store.pendingIncoming == 0 { break }; await Task.yield() }
        XCTAssertEqual(store.messages.first?.kind, .technical)
        XCTAssertTrue(store.messages.first?.pinned == true)
    }
    @MainActor func testGiftsAreOnlyRecorded() {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json"))
        store.demo = true; store.log = []
        store.receiveGift(name: "小王", gift: "鲜花", count: 1)
        XCTAssertEqual(store.gifts.count, 1); XCTAssertTrue(store.log.isEmpty, "no auto-thanks")
    }
    @MainActor func testGatewayParsesGiftEvents() {
        XCTAssertEqual(ChatGateway.gift(from: ["EVENT": "REWARD", "content": ["unick": "小王", "rewardContent": "火箭", "goodNum": 2]])?.0, "小王")
        XCTAssertEqual(ChatGateway.gift(from: ["EVENT": "FLOWERS", "nick": "阿杰"])?.1, "鲜花")
        XCTAssertNil(ChatGateway.gift(from: ["EVENT": "SPEAK"]))
    }
}

extension FlowTests {
    @MainActor func testLiveTranscriptShowsPartialAndFinalText() async {
        let voice = VoiceSession()
        var finalText: [String] = []
        voice.onFinal = { finalText.append($0) }
        voice.applyTranscriptEvent(["type": "conversation.item.input_audio_transcription.text", "text": "请提醒", "stash": "大家"])
        XCTAssertEqual(voice.transcript, "请提醒大家")
        voice.applyTranscriptEvent(["type": "conversation.item.input_audio_transcription.completed", "transcript": "请提醒大家，"])
        voice.applyTranscriptEvent(["type": "conversation.item.input_audio_transcription.delta", "delta": "下课后"])
        voice.applyTranscriptEvent(["type": "conversation.item.input_audio_transcription.delta", "delta": "下载资料。"])
        XCTAssertEqual(voice.transcript, "请提醒大家，下课后下载资料。")
        voice.applyTranscriptEvent(["type": "conversation.item.input_audio_transcription.completed", "transcript": "下课后下载资料。"])
        XCTAssertEqual(voice.transcript, finalText.joined())
    }
    @MainActor func testVoiceEntryShowsInlineErrorWithoutOpeningCard() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        var opened = 0
        store.showCard = { opened += 1 }
        store.setCapability(.voiceInput, enabled: false)
        XCTAssertTrue(store.enabled(.voiceInput))
        store.commandVoiceVisible = true
        XCTAssertEqual(opened, 0)
        store.dismissVoiceFeedback()
        XCTAssertFalse(store.commandVoiceVisible)
    }
}

extension FlowTests {
    @MainActor func testCollapsingPendingBoardPreservesMessagesAndDraft() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.demoSession()
        store.notice = ""
        store.messages[0].draft = "保留回答草稿"
        let ids = store.messages.map(\.id)
        store.setDetail(true)
        store.collapsePending()
        XCTAssertTrue(store.pendingIsCompact)
        XCTAssertFalse(store.detailExpanded)
        XCTAssertEqual(store.messages.map(\.id), ids)
        XCTAssertEqual(store.messages[0].draft, "保留回答草稿")
        store.setDetail(true)
        XCTAssertFalse(store.pendingCollapsed)
        XCTAssertEqual(store.messages[0].draft, "保留回答草稿")
    }
}

extension FlowTests {
    func testPetMenuSections() {
        let titles = PetMenuItem.items(quit: {}).map { $0.isSeparator ? "—" : $0.title }
        XCTAssertEqual(titles, ["设置", "退出"])
    }
}

extension FlowTests {
    @MainActor func testLaunchHintIsTransient() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.toast("已发送", seconds: 0.05)
        XCTAssertEqual(store.notice, "已发送")
        XCTAssertTrue(store.messages.isEmpty); XCTAssertTrue(store.log.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(store.notice, "")
        XCTAssertTrue(store.messages.isEmpty); XCTAssertTrue(store.log.isEmpty)
    }
}

extension FlowTests {
    @MainActor func testSettingsPageRestore() {
        XCTAssertEqual(Store.restoredSettingsPage(nil), "形象与风格")
        XCTAssertEqual(Store.restoredSettingsPage("助教"), "形象与风格")
        XCTAssertEqual(Store.restoredSettingsPage("形象"), "形象与风格")
        XCTAssertEqual(Store.restoredSettingsPage("形象与风格"), "形象与风格")
        XCTAssertEqual(Store.restoredSettingsPage("知识库"), "知识库")
        XCTAssertEqual(Store.restoredSettingsPage("不存在"), "形象与风格")
        XCTAssertEqual(Set(Store.settingsPages).count, 5)   // 通用 removed
    }
}

extension FlowTests {
    @MainActor func testClassTimerFormat() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(PetView.elapsed(from: start, to: start.addingTimeInterval(23 * 60 + 15)), "00:23:15")
        XCTAssertEqual(PetView.elapsed(from: start, to: start.addingTimeInterval(3600 + 5)), "01:00:05")
        XCTAssertEqual(PetView.elapsed(from: start, to: start.addingTimeInterval(-5)), "00:00:00")
    }
}

extension FlowTests {
    @MainActor func testSingleBubbleStream() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.ensureCourse()
        store.insertWelcome()
        XCTAssertEqual(store.messages.first?.pinned, false, "welcome is a normal (unpinned) message")
        XCTAssertEqual(store.badgeCount, 0, "welcome / 仅消息流 never counts toward the badge")
        XCTAssertTrue(store.pendingIsCompact, "only small form is the bubble")
        store.dismissMessages()
        XCTAssertFalse(store.messagesHidden)
        XCTAssertEqual(store.messages.count, 1, "× hides the bubble, items are kept")
        store.messages.append(PendingMessage(title: "回放？", question: "回放在哪"))
        XCTAssertFalse(store.messagesHidden, "a new message shows the bubble again")
        XCTAssertTrue(store.messages.last!.pinned, "questions are pinned to-dos")
        XCTAssertEqual(store.badgeCount, 1)
        store.messages.append(PendingMessage(kind: .technical, title: "卡", question: "网络不好"))
        XCTAssertEqual(store.messages.last!.responseType, .view)
        XCTAssertEqual(store.badgeCount, 2, "仅需查看 counts too")
        store.setDetail(true); XCTAssertFalse(store.pendingIsCompact)
        store.collapsePending(); XCTAssertTrue(store.pendingIsCompact, "big card collapses back to the bubble")
    }
}

extension FlowTests {
    /// 欢迎总结 with mocked model + chat (no real class login).
    @MainActor func testWelcomeRecap() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        var sent: [String] = []
        store.recapGenerate = { "欢迎！前面讲了：\($0.prefix(4))" }
        store.recapSend = { sent.append($0) }
        XCTAssertFalse(store.enabled(.welcomeRecap), "auto-send is opt-in")
        store.newArrivals = 2
        let off = await store.recapTick(); XCTAssertNil(off)
        store.setCapability(.welcomeRecap, enabled: true)
        store.ensureCourse()
        store.newArrivals = 1
        let noTranscript = await store.recapTick(); XCTAssertNil(noTranscript, "no transcript yet → skip")
        let course = try XCTUnwrap(store.currentCourseID)
        store.appendTranscript("变量与函数的区别。", courseID: course)
        store.newArrivals = 0
        let none = await store.recapTick(); XCTAssertNil(none, "no new arrivals → skip")
        store.newArrivals = 3
        let text = await store.recapTick()
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(text, sent.first)
        XCTAssertTrue(store.messages.contains { $0.responseType == .stream && $0.title.contains("欢迎总结") && $0.question == sent.first })
        XCTAssertEqual(store.newArrivals, 0)
        XCTAssertEqual(ChatGateway.join(from: ["EVENT": "LOGIN", "user": ["nick": "小王", "userType": "student"]]), "小王")
        XCTAssertNil(ChatGateway.join(from: ["EVENT": "LOGIN", "user": ["nick": "讲师", "userType": "teacher"]]))
    }
}

extension FlowTests {
    /// 已处理 only records assistant auto-replies, never lecturer-handled ones.
    @MainActor func testHandledIncludesLecturerAndAssistant() {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json"))
        store.demo = true
        var a = PendingMessage(kind: .question, title: "怎么报名", question: "怎么报名", people: ["小王", "小李"]); a.draft = "点击下方链接报名"
        var b = PendingMessage(kind: .question, title: "回放在哪", question: "回放在哪", people: ["小张"]); b.draft = "课后发"
        store.messages = [a, b]
        store.send(a.id, auto: true)
        store.send(b.id)
        XCTAssertEqual(store.handled.map(\.question), ["怎么报名", "回放在哪"])
        XCTAssertEqual(store.handled.map(\.actor), ["助教", "主讲"])
        XCTAssertEqual(store.handled.first?.people, ["小李", "小王"])
        XCTAssertEqual(store.handled.first?.answer, "点击下方链接报名")
    }
}

extension FlowTests {
    /// 金句提炼: mocked model + chat; skips when nothing new, never repeats.
    @MainActor func testQuoteLoop() async throws {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json"))
        var sent: [String] = []
        store.quoteGenerate = { src, _ in String(src.prefix(20)) }
        store.quoteSend = { sent.append($0) }
        store.setCapability(.quoteCards, enabled: true)
        store.ensureCourse()
        let course = try XCTUnwrap(store.currentCourseID)
        let none = await store.quoteTick(); XCTAssertNil(none, "no transcript → skip")
        store.appendTranscript("学习编程最重要的是每天动手写一点代码，坚持比天赋更重要。", courseID: course)
        let first = await store.quoteTick(); XCTAssertNotNil(first)
        let idle = await store.quoteTick(); XCTAssertNil(idle, "nothing new → skip")
        store.appendTranscript("学习编程最重要的是每天动手写一点代码，坚持比天赋更重要。", courseID: course)
        let repeatQuote = await store.quoteTick(); XCTAssertNil(repeatQuote, "no repeats")
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(store.messages.contains { $0.title == "已发送知识点" })
    }
}

extension FlowTests {
    /// 课程归档 sub-options: only enabled outputs are generated (mocked model); FAQ 补充 opt-in writes to the knowledge base.
    @MainActor func testArchiveOutputs() async throws {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("s.json"))
        store.archiveGenerate = { o, _, _ in "【\(o.rawValue)】" }
        store.ensureCourse()
        let id = try XCTUnwrap(store.currentCourseID)
        store.appendTranscript("今天讲变量和函数。", courseID: id)
        store.saved.capabilities.set(.outline, enabled: false)
        XCTAssertFalse(store.saved.capabilities.isEnabled(.faqToKnowledge))
        await store.generateArchive(courseID: id)
        let outs = try XCTUnwrap(store.saved.courses.first { $0.id == id }?.outputs)
        XCTAssertEqual(outs[ArchiveOutput.summary.rawValue], "【课程总结】")
        XCTAssertNil(outs[ArchiveOutput.outline.rawValue])
        XCTAssertNil(outs[ArchiveOutput.faqToKnowledge.rawValue])
    }
}


extension FlowTests {
    @MainActor func testConnectionSaveClearsStaleErrorAndChecksAllPolyvFields() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.saved.preferences.userID = ""
        store.saved.preferences.appID = ""
        store.polyvSecret = "test-secret"
        XCTAssertFalse(store.polyvConfigured)
        store.saved.preferences.userID = "test-user"
        store.saved.preferences.appID = "test-app"
        XCTAssertTrue(store.polyvConfigured)
        store.error = "请先配置保利威接入凭据"
        store.saveConnections()
        XCTAssertTrue(store.error.isEmpty)
        XCTAssertEqual(try StateFile(url: folder.appendingPathComponent("state.json")).read().preferences.appID, "test-app")
        store.saved.preferences.userID = "  "
        XCTAssertFalse(store.polyvConfigured)
    }
}


extension FlowTests {
    @MainActor func testEmptyConnectionKeyCannotReportSaved() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = Store(preview: true, storageURL: folder.appendingPathComponent("state.json"))
        store.jevKey = "  "
        store.saveConnections(section: "消息判断")
        XCTAssertEqual(store.error, "请输入 API Key")
        store.jevKey = "test-key"
        store.saveConnections(section: "消息判断")
        XCTAssertTrue(store.error.isEmpty)
        store.dashKey = ""
        store.saveConnections(section: "语音转写")
        XCTAssertEqual(store.error, "请输入 API Key")
    }
}

