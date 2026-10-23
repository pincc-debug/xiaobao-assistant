import XCTest
import AssistantCore
@testable import Assistant

final class LiveInteractionTests: XCTestCase {
    @MainActor func makeStore() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.capabilities.set(.courseArchive, enabled: false)
        s.channel = "123"; s.ensureCourse(); return s
    }
    @MainActor func testQuestionUpdatesOneRecordThenFinalizesAfterManualStop() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind: .answer, platformID: "q1", content: "测试题")
        s.addInteraction(item, courseID: course)
        var ongoing = true, count = 2, stops = 0
        s.interactionCallOverride = { module, method, args in
            switch method {
            case "getOngoingStatus": return ["isOngoing":ongoing, "question":["questionId":"q1"], "statistics": ["total":count, "options":[["count":1],["count":count - 1]]]] as [String:Any]
            case "getQuestionStatistics": return ["total":count, "correctCount":1, "options":[["count":1],["count":count - 1]]] as [String:Any]
            case "stop": ongoing = false; stops += 1; return [:]
            default: XCTFail("Unexpected call \(module).\(method)"); return [:]
            }
        }
        s.interactionAnalysisOverride = { _ in "建议再解释两个选项的区别。" }
        await s.refreshInteraction(item.id, courseID: course)
        count = 3
        await s.refreshInteraction(item.id, courseID: course)
        XCTAssertEqual(s.currentCourse?.interactions?.count, 1)
        XCTAssertEqual(s.interactionRecord(item.id, courseID: course)?.snapshots.last?.count, 3)
        XCTAssertEqual(stops, 0)
        await s.closeInteraction(item.id, courseID: course)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(stops, 1)
        // Ending the quiz keeps the card until「公布结果」.
        XCTAssertEqual(s.pinnedInteractions.count, 1)
        XCTAssertFalse(s.pinnedInteractions.first?.finalized ?? true)
        XCTAssertEqual(ActiveInteractions.status(s.pinnedInteractions.first!, busy: false), .awaitingPublish)
        s.toolOverride = { name, _ in XCTAssertEqual(name, "publish_answer_result"); return ["ok": true] }
        await s.publishAnswerResult(item.id, courseID: course)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
        let disk = try s.file.read().courses.first!.interactions!.first!
        XCTAssertTrue(disk.finalized); XCTAssertTrue(disk.resultPublished); XCTAssertEqual(disk.snapshots.last?.count, 3)
        XCTAssertFalse(disk.analysis.isEmpty)
        await s.closeInteraction(item.id, courseID: course)
        XCTAssertEqual(stops, 1)
    }
    @MainActor func testFailedStopRetainsCardAndCanRetry() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind:.notice, platformID:"n", content:"公告")
        s.addInteraction(item, courseID:course)
        var failing = true
        s.interactionCallOverride = { _, method, _ in
            if method == "getCurrentNotice" { return "公告" }
            if failing { throw AppError.message("offline") }; return [:]
        }
        await s.closeInteraction(item.id, courseID:course)
        XCTAssertEqual(s.pinnedInteractions.count,1); XCTAssertNil(s.pinnedInteractions.first?.ended)
        XCTAssertNotNil(s.pinnedInteractions.first?.error)
        failing = false; await s.closeInteraction(item.id, courseID:course)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
        XCTAssertEqual(s.currentCourse?.interactions?.first?.content,"公告")
    }
    @MainActor func testCheckinTracksActualRosterWithoutInventingExpectedCount() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind:.checkin, platformID:"c1", content:"签到")
        s.addInteraction(item, courseID:course)
        s.interactionCallOverride = { _, method, args in
            if method == "getCheckInStatus" { return ["isCheckingIn":false] }
            XCTAssertEqual((args.first as? [String:Any])?["checkInId"] as? String,"c1")
            return ["checkInNum":2,"list":[["userId":"1","nickname":"甲","isCheckedIn":true],["userId":"2","nickname":"乙","isCheckedIn":true],["userId":"3","nickname":"丙","isCheckedIn":false]]] as [String:Any]
        }
        await s.refreshInteraction(item.id, courseID:course)
        let result = try XCTUnwrap(s.interactionRecord(item.id, courseID:course))
        XCTAssertTrue(result.finalized); XCTAssertEqual(result.attendees.map(\.name),["甲","乙"])
        XCTAssertEqual(result.summary,"已签到 2 人"); XCTAssertTrue(result.rosterComplete)
    }
    @MainActor func testActiveCheckinUsesLiveCountInsteadOfArchivedDetails() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind: .checkin, platformID: "c1", content: "签到")
        s.addInteraction(item, courseID: course)
        var count = 1
        s.interactionCallOverride = { _, method, _ in
            switch method {
            case "getCheckInStatus": return ["isCheckingIn": true, "checkInId": "c1"] as [String: Any]
            case "getCheckInNum": return count
            default: XCTFail("Active check-in must not read archived details"); return ["checkInNum": 0, "list": []] as [String: Any]
            }
        }
        await s.refreshInteraction(item.id, courseID: course)
        XCTAssertEqual(s.pinnedInteractions.first?.summary, "已签到 1 人")
        count = 3
        await s.refreshInteraction(item.id, courseID: course)
        XCTAssertEqual(s.pinnedInteractions.first?.summary, "已签到 3 人")
        XCTAssertEqual(s.currentCourse?.interactions?.count, 1)
        XCTAssertNil(s.pinnedInteractions.first?.ended)
        XCTAssertFalse(s.pinnedInteractions.first?.rosterComplete ?? true)
    }
    @MainActor func testSwitchDuringLiveCountDoesNotAttributeNewActivityCount() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind: .checkin, platformID: "old", content: "签到")
        s.addInteraction(item, courseID: course)
        var statusReads = 0
        s.interactionCallOverride = { _, method, args in
            if method == "getCheckInStatus" {
                statusReads += 1
                return ["isCheckingIn": true, "checkInId": statusReads == 1 ? "old" : "new"] as [String: Any]
            }
            if method == "getCheckInNum" { return 99 }
            XCTAssertEqual(method, "getCheckInDetail")
            XCTAssertEqual((args.first as? [String: Any])?["checkInId"] as? String, "old")
            return ["checkInNum": 1, "list": [["userId": "1", "nickname": "甲", "isCheckedIn": true]]] as [String: Any]
        }
        await s.refreshInteraction(item.id, courseID: course)
        let result = try XCTUnwrap(s.interactionRecord(item.id, courseID: course))
        XCTAssertEqual(result.snapshots.last?.count, 1)
        XCTAssertTrue(result.finalized)
    }
    @MainActor func testLaggingFinalDetailsDoNotReplaceLiveCountWithZero() async throws {
        let s = makeStore(), course = s.currentCourseID!
        var item = LiveInteraction(kind: .checkin, platformID: "c1", content: "签到")
        item.snapshots = [InteractionSnapshot(count: 2)]
        s.addInteraction(item, courseID: course)
        var ready = false
        s.interactionCallOverride = { _, method, _ in
            if method == "getCheckInStatus" { return ["isCheckingIn": false] }
            return ready ? ["checkInNum": 2, "list": [["userId": "1", "isCheckedIn": true], ["userId": "2", "isCheckedIn": true]]] as [String: Any] : ["checkInNum": 0, "list": []] as [String: Any]
        }
        await s.refreshInteraction(item.id, courseID: course)
        XCTAssertEqual(s.pinnedInteractions.first?.snapshots.last?.count, 2)
        XCTAssertFalse(s.pinnedInteractions.first?.finalized ?? true)
        ready = true
        await s.refreshInteraction(item.id, courseID: course)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
        XCTAssertEqual(s.interactionRecord(item.id, courseID: course)?.snapshots.last?.count, 2)
    }
    @MainActor func testFinalFetchFailureRetriesWithoutStoppingTwice() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind:.answer, platformID:"q1", content:"题")
        s.addInteraction(item, courseID:course)
        var ongoing = true, fail = true, stops = 0
        s.interactionCallOverride = { _, method, _ in
            if method == "getOngoingStatus" { return ["isOngoing":ongoing,"question":["questionId":"q1"]] as [String:Any] }
            if method == "stop" { ongoing = false; stops += 1; return [:] }
            if fail { throw AppError.message("offline") }
            return ["total":0,"correctCount":0,"options":[]] as [String:Any]
        }
        await s.closeInteraction(item.id, courseID:course)
        XCTAssertNotNil(s.pinnedInteractions.first?.ended)
        fail = false; await s.closeInteraction(item.id, courseID:course)
        XCTAssertEqual(stops,1)
        // Stats synced after retry; still waiting to publish before leaving 进行中.
        XCTAssertEqual(s.pinnedInteractions.count, 1)
        XCTAssertFalse(s.pinnedInteractions.first?.finalized ?? true)
        XCTAssertEqual(s.interactionRecord(item.id, courseID:course)?.analysis,"暂无作答")
        s.toolOverride = { _, _ in ["ok": true] }
        await s.publishAnswerResult(item.id, courseID: course)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
    }
    @MainActor func testDifferentActiveCheckinCannotBeStopped() async {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind:.checkin, platformID:"old", content:"签到")
        s.addInteraction(item, courseID:course)
        s.interactionCallOverride = { _, method, _ in
            XCTAssertEqual(method,"getCheckInStatus")
            return ["isCheckingIn":true,"checkInId":"new"] as [String:Any]
        }
        await s.closeInteraction(item.id, courseID:course)
        XCTAssertNil(s.pinnedInteractions.first?.ended)
    }
    @MainActor func testSessionSwitchDiscardsLateResult() async {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind:.answer, platformID:"q", content:"题")
        s.addInteraction(item, courseID:course)
        s.interactionCallOverride = { _, method, _ in
            if method == "getOngoingStatus" { return ["isOngoing":true,"question":["questionId":"q"],"statistics":["total":1,"options":[["count":1]]]] as [String:Any] }
            s.epoch = UUID()
            return ["total":10] as [String:Any]
        }
        await s.refreshInteraction(item.id, courseID:course)
        XCTAssertTrue(s.interactionRecord(item.id, courseID:course)!.snapshots.isEmpty)
    }
    @MainActor func testAnswerCardUsesLiveDistributionWhenOtherStatisticsLag() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind: .answer, platformID: "q", content: "题")
        s.addInteraction(item, courseID: course)
        var caughtUp = false
        s.interactionCallOverride = { _, method, args in
            if method == "getOngoingStatus" {
                return ["isOngoing": true, "question": ["questionId": "q"],
                        "statistics": ["total": 3, "options": [["count": 2], ["count": 1]]]] as [String: Any]
            }
            XCTAssertEqual(method, "getQuestionStatistics")
            XCTAssertEqual(args.first as? String, "q")
            return caughtUp
                ? ["total": 3, "correctCount": 2, "options": [["count": 2], ["count": 1]]] as [String: Any]
                : ["total": 0, "correctCount": 0, "options": [["count": 0], ["count": 0]]] as [String: Any]
        }
        s.interactionAnalysisOverride = { _ in "建议解释不同选项。" }
        await s.refreshInteraction(item.id, courseID: course)
        var latest = try XCTUnwrap(s.interactionRecord(item.id, courseID: course)?.snapshots.last)
        XCTAssertEqual(latest.count, 3); XCTAssertEqual(latest.options, [2, 1])
        XCTAssertNil(latest.correct)
        caughtUp = true
        await s.refreshInteraction(item.id, courseID: course)
        latest = try XCTUnwrap(s.interactionRecord(item.id, courseID: course)?.snapshots.last)
        XCTAssertEqual(latest.correct, 2)
    }
    @MainActor func testFailedAnalysisIsShownAsAnalysisOnlyNotSyncFailure() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let item = LiveInteraction(kind: .answer, platformID: "q1", content: "测试题")
        s.addInteraction(item, courseID: course)
        s.interactionCallOverride = { _, method, _ in
            if method == "getOngoingStatus" { return ["isOngoing": true, "question": ["questionId": "q1"], "statistics": ["total": 3, "options": [["count": 2], ["count": 1]]]] as [String: Any] }
            return ["total": 3, "correctCount": 2, "options": [["count": 2], ["count": 1]]] as [String: Any]
        }
        s.interactionAnalysisOverride = { _ in throw AppError.message("model offline") }
        await s.refreshInteraction(item.id, courseID: course)
        for _ in 0..<30 { await Task.yield() }
        let latest = try XCTUnwrap(s.interactionRecord(item.id, courseID: course))
        XCTAssertEqual(latest.error, ActiveInteractions.analysisUnavailableError)   // the runtime's wording matches the view check
        XCTAssertTrue(ActiveInteractions.analysisOnlyFailure(latest))
        XCTAssertEqual(ActiveInteractions.status(latest, busy: false), .running)
    }
    @MainActor func testNoticeReplacementArchivesPreviousRecord() {
        let s = makeStore(), course = s.currentCourseID!
        s.addInteraction(LiveInteraction(kind:.notice, platformID:"a", content:"旧公告"), courseID:course)
        s.addInteraction(LiveInteraction(kind:.notice, platformID:"b", content:"新公告"), courseID:course)
        XCTAssertEqual(s.pinnedInteractions.map(\.content),["新公告"])
        XCTAssertEqual(s.currentCourse?.interactions?.count,2)
        XCTAssertTrue(s.currentCourse!.interactions![0].finalized)
    }
}
