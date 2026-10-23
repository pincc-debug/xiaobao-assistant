import XCTest
import AssistantCore
@testable import Assistant

final class ClassroomReminderTests: XCTestCase {
    @MainActor func makeStore() -> Store {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.ensureCourse(); return s
    }
    @MainActor func testBubbleStaysTallWithoutMessages() {
        let s = makeStore()
        XCTAssertEqual(CollapsedPendingBubble.height(for:s),320)
        s.bubbleTopH = 900; s.bubbleStreamH = 500
        XCTAssertEqual(CollapsedPendingBubble.height(for:s),320)
    }
    @MainActor func testReminderSurvivesFlowAndViewingDoesNotDeleteExercise() {
        let s = makeStore()
        let id = s.currentCourseID!
        let e = Exercise(question:"测试题",options:["甲","乙"],correctIndices:[0],explanation:"甲",evidence:"这是课堂原文依据。")
        s.saved.courses[0].exercises = [e]
        s.remind(.exercise(e.id),title:"我准备了一道练习题",detail:e.question,courseID:id)
        s.flow("已发送知识点"); s.flow("已回复问题")
        XCTAssertEqual(s.currentReminders.count,1)
        s.openReminder(s.currentReminders[0])
        XCTAssertTrue(s.currentReminders.isEmpty); XCTAssertTrue(s.detailExpanded)
        XCTAssertEqual(s.requestedNotebookSection,.questions)
        XCTAssertEqual(s.currentCourse?.exercises?.count,1); XCTAssertNil(s.currentCourse?.exercises?.first?.sentAt)
    }
    @MainActor func testAnalysisUpdatesSameReminderAndOldCoursesDoNotLeak() {
        let s = makeStore(), interaction = UUID()
        let course = s.currentCourseID!
        s.remind(.analysis(interaction),title:"分析",detail:"第一版",courseID:course)
        s.remind(.analysis(interaction),title:"分析",detail:"第二版",courseID:course)
        s.remind(.analysis(UUID()),title:"旧课",detail:"",courseID:UUID())
        XCTAssertEqual(s.currentReminders.count,1); XCTAssertEqual(s.currentReminders[0].detail,"第二版")
    }
    @MainActor func testClassGreetingRequiresConnectionAndOnlyRunsOnce() {
        let s = makeStore()
        s.announceClassStarted(); XCTAssertFalse(s.messages.contains { $0.title.hasPrefix("开课啦") })
        s.connected = true; s.announceClassStarted()
        let first = s.messages.last!.id
        s.announceClassStarted(); XCTAssertEqual(s.messages.last?.id,first)
        XCTAssertEqual(s.messages.last?.title,"开课啦，我来帮你留意提问、整理重点。")
        XCTAssertTrue(s.handled.isEmpty)
    }
}
