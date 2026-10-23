import XCTest
@testable import AssistantCore

final class ClassroomIssueTests: XCTestCase {
    func message(_ id: String, _ user: String) -> ClassroomMessage { .init(id:id,userID:user,name:user,text:id) }
    func testPartialRecoveryCountsPeopleNotMessagesAndCanReopen() throws {
        var issue = ClassroomIssue(kind:.technical,title:"回声")
        try issue.receive(message("1","a"),relation:.new)
        try issue.receive(message("2","a"),relation:.merge)
        try issue.receive(message("3","b"),relation:.merge)
        XCTAssertEqual(issue.participants.count,2)
        try issue.receive(message("4","a"),relation:.recovered)
        XCTAssertEqual(issue.status,.partial)
        XCTAssertEqual(issue.activeParticipants,["b"])
        try issue.receive(message("5","b"),relation:.recovered)
        XCTAssertEqual(issue.status,.resolved)
        try issue.receive(message("6","a"),relation:.followup)
        XCTAssertEqual(issue.status,.open)
        XCTAssertEqual(issue.activeParticipants,["a"])
    }
    func testStrangerCannotResolveOthersAndDuplicateDeliveryIsIdempotent() throws {
        var issue = ClassroomIssue(kind:.technical,title:"回声")
        try issue.receive(message("1","a"),relation:.new)
        try issue.receive(message("1","a"),relation:.merge)
        XCTAssertEqual(issue.messages.count,1)
        XCTAssertThrowsError(try issue.receive(message("2","b"),relation:.recovered))
        XCTAssertEqual(issue.participants,["a"])
    }
    func testSentIsWaitingAndFollowupReopensAfterPersistence() throws {
        var issue = ClassroomIssue(kind:.question,title:"目标")
        try issue.receive(message("1","a"),relation:.new)
        issue.recordReceipt(kind:"question",text:"已回复")
        XCTAssertEqual(issue.status,.waiting)
        var restored = try JSONDecoder().decode(ClassroomIssue.self,from:JSONEncoder().encode(issue))
        try restored.receive(message("2","a"),relation:.followup)
        XCTAssertEqual(restored.status,.open)
        XCTAssertEqual(restored.lastReceipt,"已回复")
    }
    func testOldCourseWithoutIssuesDecodes() throws {
        let course = CourseSession(title:"旧课",channel:"1")
        let data = try JSONEncoder().encode(course)
        XCTAssertNil(try JSONDecoder().decode(CourseSession.self,from:data).classroomIssues)
    }
}
