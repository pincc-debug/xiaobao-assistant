import XCTest
import AssistantCore
@testable import Assistant

final class ClassroomHarnessTests: XCTestCase {
    @MainActor func store() -> Store {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.channel = "100"; s.ensureCourse()
        s.saved.capabilities.set(.knowledgeAnswers,enabled:true)
        return s
    }
    func call(_ name: String, _ args: [String:Any] = [:]) -> [String:Any] { ["name":name,"arguments":args] }
    func route(_ category: String, _ relation: String = "new", _ id: String = "none") -> [String:Any] { call("route_message",["category":category,"relation":relation,"issue_id":id,"reason":"测试证据"]) }
    @MainActor func settle(_ s: Store) async throws {
        for _ in 0..<200 { if s.pendingIncoming == 0 { return }; try await Task.sleep(nanoseconds:5_000_000) }
        XCTFail("message loop did not settle")
    }
    @MainActor func testToolErrorReturnsToModelAndRecoveryOnlyUpdatesReporter() async throws {
        let s = store()
        var issue = ClassroomIssue(kind:.technical,title:"回声")
        try issue.receive(.init(id:"a1",userID:"a",name:"甲",text:"回声"),relation:.new)
        try issue.receive(.init(id:"b1",userID:"b",name:"乙",text:"我也有"),relation:.merge)
        s.saveClassroomIssue(issue); s.restoreClassroomIssues()
        var step = 0
        s.classroomDecisionOverride = { context in
            defer { step += 1 }
            switch step {
            case 0: return self.call("read_issue",["id":"bad-id"])
            case 1:
                XCTAssertNotNil((context["results"] as? [[String:Any]])?.last?["error"])
                return self.call("read_context")
            case 2: return self.call("read_issue",["id":issue.id.uuidString])
            default: return self.route("technical","recovered",issue.id.uuidString)
            }
        }
        s.receive(.init(id:"a2",userID:"a",name:"甲",text:"我这好了")); try await settle(s)
        XCTAssertEqual(step,4)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.status,.partial)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.activeParticipants,["b"])
        XCTAssertTrue(s.messages.contains { $0.id == issue.id })
    }
    @MainActor func testFollowupReopensAnsweredIssueAndKeepsIdentity() async throws {
        let s = store()
        var issue = ClassroomIssue(kind:.question,title:"目标怎么写")
        let first = ClassroomMessage(id:"q1",userID:"a",name:"甲",text:"目标怎么写")
        try issue.receive(first,relation:.new)
        s.saveClassroomIssue(issue)
        var receipt = OperationRecord(question:first.text,answer:"先明确知识点",kind:"question",sourceMessageIDs:[first.id])
        receipt.id = issue.id; s.complete(receipt)
        var step = 0
        s.classroomDecisionOverride = { _ in defer { step += 1 }; switch step {
        case 0: return self.call("read_context")
        case 1: return self.call("read_issue",["id":issue.id.uuidString])
        default: return self.route("question","followup",issue.id.uuidString)
        }}
        s.receive(.init(id:"q2",userID:"a",name:"甲",text:"还是没懂")); try await settle(s)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.status,.open)
        XCTAssertEqual(s.messages.filter { $0.id == issue.id }.count,1)
        XCTAssertEqual(s.messages.first { $0.id == issue.id }?.sourceMessages.count,2)
        XCTAssertEqual(s.messages.first { $0.id == issue.id }?.sourceMessages.first?.id,"q2")
        // A late receipt for the earlier question cannot close the new follow-up.
        s.complete(receipt)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.status,.open)
    }
    @MainActor func testBoundedFailureLeavesDurableReviewInsteadOfDroppingMessage() async throws {
        let s = store(); var calls = 0
        s.classroomDecisionOverride = { _ in calls += 1; return self.call("not_a_tool") }
        s.receive(.init(id:"fail",userID:"a",name:"甲",text:"听不到")); try await settle(s)
        XCTAssertEqual(calls,6)
        XCTAssertEqual(s.currentCourse?.events?.last?.category,"uncertain")
        XCTAssertTrue(s.messages.contains { $0.sourceMessages.contains { $0.id == "fail" } })
        s.messages = []; s.restorePending()
        XCTAssertTrue(s.messages.contains { $0.sourceMessages.contains { $0.id == "fail" } })
    }
    @MainActor func testEpochChangeDiscardsPlanWithoutMutation() async throws {
        let s = store()
        s.classroomDecisionOverride = { _ in s.epoch = UUID(); return self.route("feedback") }
        do { _ = try await s.planClassroomMessage(.init(id:"1",userID:"a",name:"甲",text:"太快"),generation:s.epoch); XCTFail("expected cancellation") } catch is CancellationError {} 
        XCTAssertTrue((s.currentCourse?.classroomIssues ?? []).isEmpty)
    }
}

extension ClassroomHarnessTests {
    @MainActor func testRealModelRecoveryAndFollowupWithoutChatConnection() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_HARNESS_LIVE"] == "1")
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/state.json")
        let original = try StateFile(url:path).read()
        let provider = try XCTUnwrap(original.providers.first { $0.id == original.defaultProviderID })
        let s = store()
        s.saved.providers = [provider]; s.saved.defaultProviderID = provider.id
        s.providerKeys[provider.id] = Vault.read("provider." + provider.id.uuidString)
        var issue = ClassroomIssue(kind:.technical,title:"声音有回声")
        try issue.receive(.init(id:"a1",userID:"a",name:"甲",text:"我听到双重声音"),relation:.new)
        try issue.receive(.init(id:"b1",userID:"b",name:"乙",text:"我也有回声"),relation:.merge)
        s.saveClassroomIssue(issue)
        s.saved.courses[s.courseIndex!].events = issue.messages
        let result = try await s.planClassroomMessage(.init(id:"a2",userID:"a",name:"甲",text:"现在我这边好了，不知道别人还有没有回声"),generation:s.epoch)
        XCTAssertEqual(result.relation,.recovered)
        XCTAssertEqual(result.issue?.id,issue.id)
        XCTAssertEqual(result.issue?.status,.partial)
        XCTAssertEqual(result.issue?.activeParticipants,["b"])
        var question = ClassroomIssue(kind:.question,title:"教学目标怎么写")
        try question.receive(.init(id:"q1",userID:"c",name:"丙",text:"教学目标怎么写"),relation:.new)
        question.recordReceipt(kind:"question",text:"从知识、方法能力、情感体验三个方面写。")
        s.saveClassroomIssue(question)
        let followup = try await s.planClassroomMessage(.init(id:"q2",userID:"c",name:"丙",text:"你刚才回复的三个方面我还是不理解，具体怎么填进数学课？"),generation:s.epoch)
        XCTAssertEqual(followup.relation,.followup)
        XCTAssertEqual(followup.issue?.id,question.id)
        XCTAssertEqual(followup.issue?.status,.open)
        let feedback = try await s.planClassroomMessage(.init(id:"f1",userID:"d",name:"丁",text:"教学目标这页讲太快了，能不能再举个例子？"),generation:s.epoch)
        XCTAssertEqual(feedback.category,"feedback")
        let report = try await s.planClassroomMessage(.init(id:"r1",userID:"e",name:"戊",text:"刚才那个让大家加微信买保过答案的是广告，大家不要加他。"),generation:s.epoch)
        XCTAssertNotEqual(report.category,"blocked")
        print("HARNESS_REAL_MODEL: four scenarios evaluated; see XCTest assertions; no chat connection or external actions")
    }
}

extension ClassroomHarnessTests {
    @MainActor func testLateSendCompletionDoesNotDismissFollowupCard() throws {
        let s = store()
        let first = ClassroomMessage(id:"old",userID:"a",name:"甲",text:"目标怎么写")
        let next = ClassroomMessage(id:"new",userID:"a",name:"甲",text:"还是没懂")
        var issue = ClassroomIssue(kind:.question,title:first.text)
        try issue.receive(first,relation:.new); try issue.receive(next,relation:.followup)
        s.saveClassroomIssue(issue)
        var old = PendingMessage(kind:.question,title:first.text,question:first.text,draft:"旧回答",sourceMessages:[first])
        old.id = issue.id; old.time = Date(timeIntervalSince1970:1)
        var current = PendingMessage(kind:.question,title:next.text,question:next.text,sourceMessages:[next,first])
        current.id = issue.id
        s.messages = [current]
        s.completeMessage(old,auto:true)
        XCTAssertEqual(s.messages.first?.question,next.text)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.status,.open)
    }
}

extension ClassroomHarnessTests {
    @MainActor func testReportCannotBeEscalatedDespiteRepeatedBlockedDecisions() async throws {
        let s = store(); var step = 0
        s.classroomRiskReviewOverride = { _ in ["intent":"report","evidence":""] }
        s.classroomDecisionOverride = { context in
            defer { step += 1 }
            if step == 0 { return self.call("read_context") }
            if step == 1 { return self.call("review_risk") }
            if step == 2 { return self.route("blocked") }
            XCTAssertNotNil((context["results"] as? [[String:Any]])?.last?["error"])
            return self.route("chat")
        }
        let result = try await s.planClassroomMessage(.init(id:"r",userID:"a",name:"甲",text:"别加那个广告号"),generation:s.epoch)
        XCTAssertEqual(result.category,"chat")
        XCTAssertEqual(step,3)
    }
}

extension ClassroomHarnessTests {
    @MainActor func testLearningFeedbackLinksToQuestionWithoutChangingItsType() async throws {
        let s = store()
        var issue = ClassroomIssue(kind:.question,title:"教学目标")
        try issue.receive(.init(id:"q",userID:"a",name:"甲",text:"怎么写目标"),relation:.new)
        s.saveClassroomIssue(issue)
        var step = 0
        s.classroomDecisionOverride = { _ in
            defer { step += 1 }
            return step == 0 ? self.call("read_issue",["id":issue.id.uuidString]) : self.route("feedback","followup",issue.id.uuidString)
        }
        let result = try await s.planClassroomMessage(.init(id:"f",userID:"b",name:"乙",text:"目标这页太快了"),generation:s.epoch)
        XCTAssertEqual(result.category,"feedback")
        XCTAssertEqual(result.relation,.new)
        XCTAssertEqual(result.issue?.relatedIssueID,issue.id)
        XCTAssertNotEqual(result.issue?.id,issue.id)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.kind,.question)
    }
}
