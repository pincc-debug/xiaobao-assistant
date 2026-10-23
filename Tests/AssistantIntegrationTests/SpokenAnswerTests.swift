import XCTest
import AssistantCore
@testable import Assistant

final class SpokenAnswerTests: XCTestCase {
    @MainActor func fixture() -> (Store, PendingMessage, TranscriptSegment) {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.capabilities.set(.knowledgeAnswers,enabled:true); s.saved.capabilities.set(.courseArchive,enabled:false)
        s.ensureCourse()
        var q = PendingMessage(title:"回放多久",question:"回放保留多久？")
        q.time = Date().addingTimeInterval(-10)
        q.sourceMessages = [ClassroomMessage(id:"original",userID:"student",name:"学生",text:q.question)]
        let segment = TranscriptSegment(text:"这节课的回放保留七天。")
        s.messages = [q]; s.saved.courses[0].transcriptSegments = [segment]
        s.saved.courses[0].transcript = segment.text
        return (s,q,segment)
    }
    func client(_ q: PendingMessage, _ segment: TranscriptSegment, supported: Bool = true, evidence: String? = nil) -> ModelsClient {
        var c = ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        c.generateOverride = { _,_ in ["matches":[["question_id":q.id.uuidString,"answer":"回放保留七天。","evidence":evidence ?? segment.text,"segment_ids":[segment.id.uuidString]]]] }
        c.jevOverride = { _,_ in ["supported":["choice":supported ? "yes":"no","confidence":0.99]] }
        return c
    }
    @MainActor func testSpokenAnswerRepliesToOriginalAndPersistsEvidence() async throws {
        let (s,q,segment) = fixture(); s.spokenClientOverride = client(q,segment)
        var sent = 0
        s.replyOverride = { text, original in sent += 1; XCTAssertEqual(original?.id,"original"); XCTAssertEqual(text,"老师刚刚说明：回放保留七天。") }
        await s.followSpokenAnswers()
        XCTAssertEqual(sent,1); XCTAssertFalse(s.messages.contains { $0.id == q.id })
        let answer = try XCTUnwrap(try s.file.read().courses.first?.answers.first)
        XCTAssertEqual(answer.actor,"主讲口述，助教整理"); XCTAssertEqual(answer.spokenEvidence,segment.text); XCTAssertEqual(answer.spokenSegmentIDs,[segment.id])
        await s.followSpokenAnswers(); XCTAssertEqual(sent,1)
    }
    @MainActor func testMentionOrUncertainAnswerStaysPending() async {
        let (s,q,segment) = fixture(); s.spokenClientOverride = client(q,segment,supported:false)
        s.replyOverride = { _,_ in XCTFail("must not send") }
        await s.followSpokenAnswers(); XCTAssertTrue(s.messages.contains { $0.id == q.id }); XCTAssertTrue(s.currentCourse!.answers.isEmpty)
    }
    @MainActor func testInventedEvidenceAndPreQuestionSpeechAreRejected() async throws {
        let (_,q,segment) = fixture()
        let invented = try await client(q,segment,evidence:"回放永久开放。").matchSpokenAnswers([q],segments:[segment])
        XCTAssertTrue(invented.isEmpty)
        var old = segment; old.time = q.time.addingTimeInterval(-1)
        let past = try await client(q,old).matchSpokenAnswers([q],segments:[old])
        XCTAssertTrue(past.isEmpty)
    }
    @MainActor func testSendFailureKeepsDraftAndDoesNotAutomaticallyRetry() async {
        let (s,q,segment) = fixture(); s.spokenClientOverride = client(q,segment)
        var sends = 0
        s.replyOverride = { _,_ in sends += 1; throw AppError.message("timeout") }
        await s.followSpokenAnswers(); await s.followSpokenAnswers()
        XCTAssertEqual(sends,1); XCTAssertTrue(s.currentCourse!.answers.isEmpty)
        let pending = s.messages.first { $0.id == q.id }!
        XCTAssertFalse(pending.busy); XCTAssertFalse(pending.draft.isEmpty); XCTAssertNotNil(pending.spokenMatch)
    }
    @MainActor func testNewCorrectionArrivingDuringModelCallPreventsSending() async {
        let (s,q,segment) = fixture(); var c = client(q,segment)
        c.jevOverride = { _,_ in
            s.saved.courses[0].transcriptSegments?.append(TranscriptSegment(text:"纠正一下，刚才说错了。"))
            return ["supported":["choice":"yes","confidence":0.99]]
        }
        s.spokenClientOverride = c; s.replyOverride = { _,_ in XCTFail("stale answer must not send") }
        await s.followSpokenAnswers(); XCTAssertTrue(s.currentCourse!.answers.isEmpty)
    }
    @MainActor func testLecturerEditingAnswerIsNotOverwritten() async {
        let (s,q,segment) = fixture(); s.spokenClientOverride = client(q,segment)
        s.messages[0].draft = "老师正在编辑"
        s.replyOverride = { _,_ in XCTFail("must not send") }
        await s.followSpokenAnswers(); XCTAssertEqual(s.messages[0].draft,"老师正在编辑")
    }
}
