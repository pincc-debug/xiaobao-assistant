import XCTest
import AppKit
import SwiftUI
import AssistantCore
@testable import Assistant

final class FollowupTests: XCTestCase {
    @MainActor func makeStore() -> Store { Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")) }
    @MainActor func testOnlyAnsweredQuestionsAppearInHandledBoard() {
        let store = makeStore()
        store.complete(OperationRecord(question:"问题",answer:"回答",kind:"question"))
        store.complete(OperationRecord(question:"欢迎",answer:"欢迎",kind:"recap"))
        store.complete(OperationRecord(question:"广告",answer:"禁言",kind:"moderation"))
        XCTAssertEqual(store.answeredItems.count,1); XCTAssertEqual(store.activities.count,3)
    }
    @MainActor func testErrorsStayInStreamAndNotPending() {
        let store=makeStore();store.postError("模型连接失败")
        XCTAssertEqual(store.badgeCount,0);XCTAssertEqual(store.messages.last?.responseType,.stream)
        XCTAssertEqual(store.activities.last?.status,"失败")
    }
    @MainActor func testNotInClassCannotStartVoice() {
        let store=makeStore();store.talkToAssistant()
        XCTAssertFalse(store.voice.active);XCTAssertFalse(store.commandVoiceVisible)
        store.ensureCourse();store.connected=true
        XCTAssertTrue(store.canTalkToAssistant)
        store.connected=false;XCTAssertFalse(store.canTalkToAssistant)
    }
    @MainActor func testTransientActivityExpiresWithoutRemovingPending() async throws {
        let store=makeStore();store.flowLifetime=0.02
        let question=PendingMessage(title:"问题",question:"问题")
        store.messages=[question];store.flow("已发送")
        try await Task.sleep(nanoseconds:60_000_000)
        XCTAssertEqual(store.messages.map(\.id),[question.id])
    }
    @MainActor func testActivityPersistsOriginalMessageAndDecision() throws {
        let store=makeStore();store.ensureCourse()
        store.activity("消息判断","课程提问 → 检索回答依据",source:"Arena多少分？",messageID:"message-1")
        let course=try XCTUnwrap(try store.file.read().courses.first)
        XCTAssertEqual(course.activities?.first?.source,"Arena多少分？")
        XCTAssertEqual(course.activities?.first?.messageID,"message-1")
    }
    @MainActor func testDuplicateCorrectSourcesDoNotFailExclusiveSelectionGate() async throws {
        let library=KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"Arena 文本榜1525分，排名第1。"),Document(name:"课程资料",text:"视频给出的 Arena 文本榜成绩是1525分。")])
        var client=ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        var generatedSources=0
        client.generateOverride = { _,input in
            let passages=(input as? [String:Any])?["passages"] as? [[String:String]] ?? []
            generatedSources=passages.count
            return ["answerable":true,"answer":"1525分。","source_ids":passages.map { $0["id"]! }]
        }
        client.jevOverride = { _,questions in
            XCTAssertNil(questions["source"],"不再要求在重复正确资料间选唯一一份")
            return ["supported":["choice":"yes","confidence":0.98]]
        }
        let answer=try await client.answer("Arena文本榜多少分？",library:library)
        XCTAssertEqual(generatedSources,2);XCTAssertEqual(answer?.0,"1525分。")
    }
    @MainActor func testUnsupportedQuestionStillEscalates() async throws {
        let library=KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"本课视频介绍模型价格，但没有班群邀请码。")])
        var client=ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        client.generateOverride={_,_ in ["answerable":false]}
        client.jevOverride={_,_ in XCTFail("无答案时不做无意义核验");return [:]}
        let result=try await client.answer("本班的邀请码是什么？",library:library)
        XCTAssertNil(result)
    }
}

extension FollowupTests {
    @MainActor func testLookingUpAnswerDoesNotCountAsLecturerPending() {
        let store=makeStore()
        var message=PendingMessage(title:"问题",question:"问题");message.evaluating=true
        store.messages=[message]
        XCTAssertEqual(store.badgeCount,0);XCTAssertFalse(store.hasDisplayMessages)
        store.escalateQuestion(message.id)
        XCTAssertEqual(store.badgeCount,1);XCTAssertTrue(store.hasDisplayMessages)
    }
    @MainActor func testStartFormClosesOnlyAfterSuccessfulConnection() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_UI_TESTS"] == "1", "Window tests require explicit opt-in")
        _ = NSApplication.shared
        let store=makeStore();var closed=0
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:364,height:480),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false
        let host=NSHostingView(rootView:StartCard(store:store,settings:{},close:{closed += 1}))
        window.contentView=host;window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(nanoseconds:100_000_000)
        store.status="登录失败";store.connected=false
        try await Task.sleep(nanoseconds:50_000_000)
        XCTAssertEqual(closed,0)
        store.connected=true
        try await Task.sleep(nanoseconds:150_000_000)
        XCTAssertEqual(closed,1)
    }
}

extension FollowupTests {
    @MainActor func testNoLessonHasNoCardAndNoGreeting() {
        let s=makeStore()
        XCTAssertFalse(s.showLessonCards);XCTAssertTrue(s.messages.isEmpty)
        s.setDetail(true);XCTAssertFalse(s.detailExpanded)
        s.ensureCourse();XCTAssertTrue(s.showLessonCards)
        s.setDetail(true);s.flow("新消息")
        XCTAssertTrue(s.detailExpanded,"新消息不能改变卡片形态")
        s.collapsePending();XCTAssertFalse(s.detailExpanded)
        s.dismissMessages();XCTAssertFalse(s.messagesHidden)
    }
    @MainActor func testHistoryDeleteExcludesActiveCourseAndCanUndo() throws {
        let s=makeStore();s.ensureCourse();let active=try XCTUnwrap(s.currentCourseID)
        let old=CourseSession(title:"历史",channel:"123");s.saved.courses.append(old);s.persist()
        s.deleteCourses([old.id,active])
        XCTAssertEqual(s.saved.courses.map(\.id),[active])
        XCTAssertEqual(try s.file.read().courses.map(\.id),[active])
        XCTAssertNotNil(s.deletedCoursesBackup)
        s.undoDeleteCourses();XCTAssertEqual(Set(s.saved.courses.map(\.id)),Set([old.id,active]))
    }
    func testModelCachePersistsAndTracksServiceContext() throws {
        var p=ModelProvider();p.kind = .anthropic;p.model="chosen"
        p.cachedModels=["chosen","another"];p.cachedModelsContext=p.modelsContext;p.modelsRefreshedAt=Date()
        var restored=try JSONDecoder().decode(ModelProvider.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(restored.availableCachedModels,["chosen","another"])
        restored.kind = .compatible;XCTAssertTrue(restored.availableCachedModels.isEmpty)
    }
}
