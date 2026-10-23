import XCTest
import AppKit
import AssistantCore
@testable import Assistant

/// Always-dark surfaces (pet, login card, bubble, action card, answer bar) + the 「下课」 confirmation.
final class ForcedDarkSurfaceTests: XCTestCase {
    @MainActor func testEndClassAlertIsForcedDarkEvenWhenAppIsLight() {
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        NSApp.appearance = NSAppearance(named: .aqua)
        let alert = LiveSessionControl.endClassAlert()
        XCTAssertEqual(alert.window.appearance?.name, .darkAqua)
        XCTAssertEqual(alert.window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]), .darkAqua)
        XCTAssertEqual(alert.buttons.map(\.title), ["取消", "结束上课"])
        XCTAssertEqual(alert.buttons[0].keyEquivalent, "\r")
        XCTAssertTrue(alert.buttons[1].hasDestructiveAction)
    }
    @MainActor func testPetMenuIsDark() {
        let menu = PetMenuItem.menu(PetMenuItem.items(settings: {}, quit: {}))
        XCTAssertEqual(menu.appearance?.name, .darkAqua)
    }
    @MainActor func testBubbleKeepsFixedHeightAndSmallerCaption() {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        XCTAssertEqual(CollapsedPendingBubble.height(for: s), 320)
        let bubble = TranscriptCaption(store: s, course: nil, fontSize: 12, lineHeight: 22)
        XCTAssertEqual(bubble.fontSize, 12); XCTAssertEqual(bubble.lineHeight, 22)
        let workbench = TranscriptCaption(store: s, course: nil)
        XCTAssertEqual(workbench.fontSize, 13); XCTAssertEqual(workbench.lineHeight, 28)
    }
    func testNotebookEmptyStateCopy() {
        XCTAssertEqual(NotebookEmptyState.message, "上课后，笔记会自动生成")
    }
}

/// Small bubble: only non-empty sections take a slot, so 待答 ↔ 课堂反馈 is one 16pt group gap (not ≈34pt of empty sections).
final class BubbleGroupSpacingTests: XCTestCase {
    @MainActor func store() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.channel = "123"; s.ensureCourse(); s.classroomReminders = []
        s.messages = [PendingMessage(title: "回放在哪里？", question: "回放在哪里？", people: ["a", "b", "c"]),
                      PendingMessage(title: "课件可以下载吗？", question: "课件可以下载吗？", people: ["d", "e"]),
                      PendingMessage(kind: .technical, title: "观众反馈声音偏小", question: "声音小", people: ["f"])]
        return s
    }
    func testGroupGapIsSixteen() {
        XCTAssertEqual(PendingBoard.bubbleRowPadding * 2 + CollapsedPendingBubble.groupSpacing, 16)
    }
    @MainActor func testEmptySectionsTakeNoSlot() {
        let s = store()
        XCTAssertEqual(CollapsedPendingBubble.pinnedSections(for: s), [.pending, .others])
        if let i = s.courseIndex { s.saved.courses[i].interactions = [LiveInteraction(kind: .rush, platformID: "r1", content: "")] }
        XCTAssertEqual(CollapsedPendingBubble.pinnedSections(for: s), [.pending, .interactions, .others])
        if let i = s.courseIndex { s.saved.courses[i].interactions = [] }
        s.messages.removeAll { $0.kind == .technical }
        XCTAssertEqual(CollapsedPendingBubble.pinnedSections(for: s), [.pending])
        s.messages = [PendingMessage(kind: .technical, title: "声音小", question: "声音小", people: ["f"])]
        XCTAssertEqual(CollapsedPendingBubble.pinnedSections(for: s), [.others])
    }
}

/// Reply activity feed: `已回复 昵称 · 问题`, stacked newest-at-bottom, no invented fields.
final class ReplyActivityFeedTests: XCTestCase {
    @MainActor func testReplyTitleUsesWhateverIsAvailable() {
        XCTAssertEqual(Store.replyActivityTitle(nickname: "小林", question: "回放在哪里？"), "已回复 小林 · 回放在哪里？")
        XCTAssertEqual(Store.replyActivityTitle(nickname: "小林", question: nil), "已回复 小林")
        XCTAssertEqual(Store.replyActivityTitle(nickname: nil, question: "回放在哪里？"), "已回复 · 回放在哪里？")
        XCTAssertEqual(Store.replyActivityTitle(nickname: "  ", question: ""), "已回复")
        XCTAssertEqual(Store.replyActivityTitle(nickname: nil, question: nil), "已回复")
    }
    @MainActor func testNicknamePrefersSourceMessageAndDoesNotPickAmongMany() {
        var one = PendingMessage(title: "问", question: "完整问题", people: ["甲", "乙"])
        one.sourceMessages = [ClassroomMessage(id: "1", userID: "u1", name: "甲", text: "完整问题")]
        XCTAssertEqual(Store.replyNickname(from: one), "甲")
        XCTAssertEqual(Store.replyQuestion(from: one), "完整问题")
        let many = PendingMessage(title: "问", question: "完整问题", people: ["甲", "乙"])
        XCTAssertNil(Store.replyNickname(from: many))   // don't invent which of several
        let sole = PendingMessage(title: "问", question: "", people: ["独行"])
        XCTAssertEqual(Store.replyNickname(from: sole), "独行")
        XCTAssertEqual(Store.replyQuestion(from: sole), "问")   // falls back to title
    }
    @MainActor func testAssistantVoiceTitleKeepsReplyLineLiteral() {
        let m = PendingMessage(kind: .notice, title: "已回复 小林 · 回放在哪里？", question: "")
        XCTAssertEqual(m.assistantVoiceTitle, "已回复 小林 · 回放在哪里？")
        let other = PendingMessage(kind: .notice, title: "已发送知识点", question: "")
        XCTAssertEqual(other.assistantVoiceTitle, "我已发送知识点")
    }
    @MainActor func testFlowKeepsRecentStackNewestLast() {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let pinned = PendingMessage(title: "待答", question: "还在")
        s.messages = [pinned]
        s.flow(Store.replyActivityTitle(nickname: "甲", question: "问题一"))
        s.flow(Store.replyActivityTitle(nickname: "乙", question: "问题二"))
        s.flow(Store.replyActivityTitle(nickname: "丙", question: "问题三"))
        XCTAssertEqual(s.messages.first?.id, pinned.id)
        let feed = Store.recentStreamMessages(s.messages, lifetime: s.flowLifetime, limit: 3)
        XCTAssertEqual(feed.map(\.title), ["已回复 甲 · 问题一", "已回复 乙 · 问题二", "已回复 丙 · 问题三"])
        XCTAssertEqual(Store.recentStreamMessages(s.messages, lifetime: s.flowLifetime, limit: 2).map(\.title),
                       ["已回复 乙 · 问题二", "已回复 丙 · 问题三"])
    }
}
