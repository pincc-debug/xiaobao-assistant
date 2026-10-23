import XCTest
import AssistantCore
@testable import Assistant

final class LecturerSuggestionTests: XCTestCase {
    func client() -> ModelsClient {
        var client = ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        client.jevOverride = { _,_ in ["supported":["choice":"yes","confidence":0.95]] }
        return client
    }
    func testPartialAnswerRetainsEvidenceAndConfirmation() async throws {
        let passages = Knowledge.chunks(in:KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"课后开放回放。")]))
        var c = client()
        c.generateOverride = { _,_ in ["kind":"partial","draft":"课后开放回放。","confirmation":"请确认回放保留多久。","evidence":[["id":passages[0].id,"quote":passages[0].text]]] }
        let result = try await c.lecturerSuggestion("有没有回放，保留多久？",passages:passages)
        XCTAssertEqual(result.kind,.partial); XCTAssertEqual(result.draft,"课后开放回放。")
        XCTAssertEqual(result.evidence.first?.title,"FAQ"); XCTAssertTrue(result.confirmation.contains("多久"))
    }
    func testConflictNeverProducesSendableDraft() async throws {
        let passages = Knowledge.chunks(in:KnowledgeBase(name:"课",documents:[Document(name:"甲",text:"回放保留七天。"),Document(name:"乙",text:"回放保留三天。")]))
        var c = client()
        c.generateOverride = { _,_ in ["kind":"conflict","draft":"七天。","confirmation":"请确认当前期限。","evidence":passages.map { ["id":$0.id,"quote":$0.text] }] }
        let result = try await c.lecturerSuggestion("多久？",passages:passages)
        XCTAssertEqual(result.kind,.conflict); XCTAssertTrue(result.draft.isEmpty); XCTAssertEqual(result.evidence.count,2)
    }
    func testMissingAndInventedEvidenceCannotBecomeDraft() async throws {
        var c = client(); c.generateOverride = { _,_ in XCTFail("empty retrieval must not generate"); return [:] }
        let missing = try await c.lecturerSuggestion("邀请码？",passages:[])
        XCTAssertEqual(missing.kind,.missing); XCTAssertTrue(missing.draft.isEmpty)
        let passages = Knowledge.chunks(in:KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"课后开放回放。")]))
        c.generateOverride = { _,_ in ["kind":"partial","draft":"邀请码为1234。","confirmation":"请确认。","evidence":[["id":passages[0].id,"quote":"邀请码为1234。"]]] }
        let invalid = try await c.lecturerSuggestion("邀请码？",passages:passages)
        XCTAssertEqual(invalid.kind,.missing); XCTAssertTrue(invalid.draft.isEmpty)
    }
    @MainActor func testPreparationDoesNotSendAndAdoptionSendsWithoutFillingInput() async {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.ensureCourse(); var message = PendingMessage(title:"回放",question:"回放多久？")
        message.sourceMessages = [ClassroomMessage(id:"original",userID:"1",name:"学生",text:message.question)]
        s.messages = [message]
        var sent: [String] = []
        s.replyOverride = { text, original in
            XCTAssertTrue(s.messages.first { $0.id == message.id }!.draft.isEmpty)
            XCTAssertEqual(original?.id,"original"); sent.append(text)
        }
        let passages = Knowledge.chunks(in:KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"课后开放回放。")]))
        var c = client()
        c.generateOverride = { _,_ in ["kind":"partial","draft":"课后开放回放。","confirmation":"请补充期限。","evidence":[["id":passages[0].id,"quote":passages[0].text]]] }
        s.suggestionClientOverride = c
        await s.prepareLecturerSuggestion(message.id,passages:passages,generation:s.epoch,revision:s.capabilityRevision)
        XCTAssertTrue(s.messages[0].draft.isEmpty); XCTAssertTrue(sent.isEmpty)
        s.adoptLecturerSuggestion(message.id); s.adoptLecturerSuggestion(message.id)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(sent,["课后开放回放。"])
        XCTAssertFalse(s.messages.contains { $0.id == message.id })
        XCTAssertEqual(s.currentCourse?.answers.last?.answer,"课后开放回放。")
    }
    @MainActor func testFailedAdoptionRetainsSuggestionAndEmptyInput() async {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var message = PendingMessage(title:"回放",question:"回放？")
        message.suggestion = LecturerSuggestion(kind:.partial,draft:"课后有回放。",confirmation:"请确认期限。")
        s.messages = [message]; s.replyOverride = { _,_ in throw AppError.message("失败") }
        s.adoptLecturerSuggestion(message.id)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(s.messages.first { $0.id == message.id }!.draft.isEmpty)
        XCTAssertNotNil(s.messages.first { $0.id == message.id }!.suggestion)
        XCTAssertFalse(s.messages.first { $0.id == message.id }!.error.isEmpty)
    }
    @MainActor func testLateSuggestionAfterSessionChangeIsDiscarded() async {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let message = PendingMessage(title:"问题",question:"回放？"); s.messages = [message]
        let passages = Knowledge.chunks(in:KnowledgeBase(name:"课",documents:[Document(name:"FAQ",text:"课后开放回放。")]))
        var c = client(); c.generateOverride = { _,_ in s.epoch = UUID(); return ["kind":"missing"] }
        s.suggestionClientOverride = c
        await s.prepareLecturerSuggestion(message.id,passages:passages,generation:s.epoch,revision:s.capabilityRevision)
        XCTAssertNil(s.messages[0].suggestion)
    }
}
