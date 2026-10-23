import XCTest
import AssistantCore
@testable import Assistant

final class CourseDataTests: XCTestCase {
    private let now=CourseData.date("2026-10-16 00:00:20")!
    @MainActor private func store() -> Store {
        let s=Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var c=CourseSession(title:"课堂",channel:"100")
        c.platformSessionID="session-a"; c.started=now.addingTimeInterval(-600); c.ended=now; c.startTimeVerified=true
        s.saved.courses=[c]; return s
    }
    func testRealtimeMidnightForeignChannelAndMissingCounts() {
        let rows:[[String:Any]]=[
            ["channelId":100,"time":"23:59:50","count":12],
            ["channelId":"100","time":"00:00:10","count":"0"],
            ["channelId":999,"time":"00:00:10","count":999],
            ["channelId":100,"time":"00:00:10"],
            ["channelId":100,"time":"00:00:10","count":true],
            ["channelId":100,"time":"18:00:00","count":5]]
        let points=CourseData.realtime(rows,channel:"100",start:now.addingTimeInterval(-600),now:now)
        XCTAssertEqual(points.map(\.count),[12,0]); XCTAssertEqual(points.first?.time,now.addingTimeInterval(-30))
        XCTAssertEqual(CourseData.mergePoints(points,points).count,2)
    }
    func testHistoricalBoundsMissingAndMetricUnits() {
        let points=CourseData.historical([["day":"2026-10-15","minute":"23:59","viewers":10],["day":"2026-10-16","minute":"00:01","viewers":99]],start:now.addingTimeInterval(-120),end:now)
        XCTAssertEqual(points.count,1)
        let metrics=CourseData.metrics(["uniqueViewer":10,"averagePlayDuration":3,"totalPlayDuration":30,"startDuration":600])
        XCTAssertNil(metrics.views); XCTAssertEqual(metrics.averageMinutes,3); XCTAssertEqual(metrics.durationSeconds,600)
    }
    private func message(_ id:String, session:String="session-a",role:String="student") -> [String:Any] {
        ["id":id,"channelId":100,"sessionId":session,"time":now.addingTimeInterval(-60).timeIntervalSince1970*1000,
         "content":"变量有什么用？","userType":role,"quote":"引用原问题","sourceType":"public","user":["userId":"student-1","nickname":"小周"]]
    }
    func testChatRoleQuotePrivacyAndDeduplication() throws {
        let record=try XCTUnwrap(CourseData.chat(message("a",role:"teacher")))
        XCTAssertFalse(record.isStudent); XCTAssertEqual(record.quote,"引用原问题")
        XCTAssertEqual(CourseData.mergeChat([record],[record]).count,1)
        var privateRow=message("b"); privateRow["sourceType"]="extend"; XCTAssertNil(CourseData.chat(privateRow))
        var deleted=message("b"); deleted["status"]="delete"; XCTAssertNil(CourseData.chat(deleted))
    }
    @MainActor func testSyncCapturedChannelExactSessionPaginationAndReload() async throws {
        let s=store(), id=s.saved.courses[0].id
        s.channel="999" // Historical query must never inherit this active channel.
        var historyPages:[String]=[]
        s.statisticsOverride = { path, params in
            XCTAssertEqual(params["channelId"],"100")
            if path.contains("summary/list") { return ["contents":[["channelId":999,"sessionId":"session-a","uniqueViewer":999],["channelId":100,"sessionId":"session-a","uniqueViewer":21,"startTime":self.now.addingTimeInterval(-600).timeIntervalSince1970*1000,"endTime":self.now.timeIntervalSince1970*1000]]] }
            if path.contains("concurrence") { return [["day":"2026-10-15","minute":"23:59","viewers":10]] }
            historyPages.append(params["page"] ?? "")
            if params["page"] == "1" { return ["contents":Array(repeating:self.message("a"),count:999) + [self.message("foreign",session:"session-b")]] }
            return ["contents":[self.message("b",role:"assistant")]]
        }
        await s.refreshCourseData(id)
        XCTAssertEqual(historyPages,["1","2"])
        let c=try XCTUnwrap(s.saved.courses.first)
        XCTAssertEqual(c.analytics?.metrics?.viewers,21); XCTAssertEqual(c.publicChat?.count,2)
        XCTAssertNotNil(c.analytics?.chatSyncedThrough); XCTAssertNil(c.analytics?.chatNextPage)
        XCTAssertEqual(try s.file.read().courses.first?.publicChat?.count,2)
        var sources:[RoomSource]=[]
        let result=try s.performRoomTool("read_course_data",args:["course_id":id.uuidString,"section":"概况","offset":0],channel:"100",sources:&sources) as? [String:Any]
        XCTAssertNotNil(result); XCTAssertTrue(sources[0].text.contains("21"))
        XCTAssertThrowsError(try s.performRoomTool("read_course_data",args:["course_id":id.uuidString,"section":"概况","offset":0],channel:"999",sources:&sources))
    }
    func testSyncWindowEndIgnoresStalePlatformEndWhileLive() {
        let platformEnd=now.addingTimeInterval(-7800)   // platform summary froze at an early stream segment
        XCTAssertEqual(CourseData.syncWindowEnd(metricsEnd:platformEnd,ended:nil,live:true,now:now),now)
        XCTAssertEqual(CourseData.syncWindowEnd(metricsEnd:platformEnd,ended:now,live:false,now:now),platformEnd)
        XCTAssertEqual(CourseData.syncWindowEnd(metricsEnd:nil,ended:now.addingTimeInterval(-60),live:false,now:now),now.addingTimeInterval(-60))
        XCTAssertEqual(CourseData.syncWindowEnd(metricsEnd:now.addingTimeInterval(60),ended:nil,live:false,now:now),now)
        XCTAssertTrue(CourseData.platformEndedEarly(metricsEnd:now.addingTimeInterval(-121),live:true,now:now))
        XCTAssertFalse(CourseData.platformEndedEarly(metricsEnd:now.addingTimeInterval(-119),live:true,now:now))
        XCTAssertFalse(CourseData.platformEndedEarly(metricsEnd:now.addingTimeInterval(-7800),live:false,now:now))
        XCTAssertFalse(CourseData.platformEndedEarly(metricsEnd:nil,live:true,now:now))
    }
    @MainActor func testLiveSyncAdvancesChatPastStalePlatformEnd() async throws {
        let s=store(), id=s.saved.courses[0].id
        let started=Date().addingTimeInterval(-7200), platformEnd=started.addingTimeInterval(163)
        s.saved.courses[0].started=started; s.saved.courses[0].ended=nil
        s.currentCourseID=id; s.connected=true
        var chatEnd:Date?
        s.statisticsOverride = { path,params in
            if path.contains("summary/list") { return ["contents":[["channelId":100,"sessionId":"session-a","uniqueViewer":0,"startTime":started.timeIntervalSince1970*1000,"endTime":platformEnd.timeIntervalSince1970*1000]]] }
            if path.contains("concurrence") { return [] as [[String:Any]] }
            chatEnd=CourseData.date(params["endDay"])
            return ["contents":[]]
        }
        let before=Date()
        await s.refreshCourseData(id)
        let synced=try XCTUnwrap(s.saved.courses[0].analytics?.chatSyncedThrough)
        XCTAssertEqual(s.saved.courses[0].analytics?.metrics?.end?.timeIntervalSince1970 ?? 0,platformEnd.timeIntervalSince1970,accuracy:1)
        XCTAssertGreaterThan(synced,platformEnd.addingTimeInterval(3600))
        XCTAssertGreaterThanOrEqual(synced,before.addingTimeInterval(-2))
        XCTAssertEqual(chatEnd,synced)
        XCTAssertEqual(s.saved.courses[0].analytics?.chatSyncedFrom?.timeIntervalSince1970 ?? 0,started.timeIntervalSince1970,accuracy:1)
        // After 下课 the platform endTime bounds the window again.
        s.connected=false; s.saved.courses[0].ended=Date(); s.lastDataSyncAttempt[id] = .distantPast
        await s.refreshCourseData(id)
        XCTAssertEqual(s.saved.courses[0].analytics?.chatSyncedThrough?.timeIntervalSince1970 ?? 0,platformEnd.timeIntervalSince1970,accuracy:1)
    }
    @MainActor func testPartialChatRetryResumesWithoutLosingEarlierPages() async throws {
        let s=store(), id=s.saved.courses[0].id
        var fail=true; var pages:[String]=[]
        s.statisticsOverride = { path,params in
            if path.contains("summary/list") { return ["contents":[]] }
            if path.contains("concurrence") { return [] as [[String:Any]] }
            pages.append(params["page"] ?? "")
            if params["page"] == "1" { return ["contents":Array(repeating:self.message("a"),count:1000)] }
            if fail { throw AppError.message("模拟断网") }
            return ["contents":[self.message("b")]]
        }
        await s.refreshCourseData(id)
        XCTAssertEqual(s.saved.courses[0].publicChat?.count,1)
        XCTAssertEqual(s.saved.courses[0].analytics?.chatNextPage,2)
        XCTAssertNil(s.saved.courses[0].analytics?.chatSyncedThrough)
        fail=false; s.lastDataSyncAttempt[id] = .distantPast
        await s.refreshCourseData(id)
        XCTAssertEqual(pages,["1","2","2"])
        XCTAssertEqual(s.saved.courses[0].publicChat?.count,2)
        XCTAssertNotNil(s.saved.courses[0].analytics?.chatSyncedThrough)
    }
    @MainActor func testLateRealtimeResultCannotAttachToNewSession() async throws {
        let s=store(), id=s.saved.courses[0].id
        s.currentCourseID=id; s.connected=true
        var continuation:CheckedContinuation<Any,Never>?
        s.statisticsOverride = { _,_ in await withCheckedContinuation { continuation=$0 } }
        let task=Task { await s.pollRealtimeData(courseID:id,now:now) }
        for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
        XCTAssertNotNil(continuation)
        s.epoch=UUID()
        continuation?.resume(returning:[["channelId":100,"time":"00:00:10","count":22]])
        let success=await task.value
        XCTAssertFalse(success); XCTAssertNil(s.saved.courses[0].analytics)
    }
    @MainActor func testSourceFailuresPreserveOldValuesAndNeverInventZero() async throws {
        let s=store(), id=s.saved.courses[0].id
        var a=CourseAnalytics(); a.points=[ViewerPoint(time:now,count:33,source:"实时")]
        s.saved.courses[0].analytics=a; s.currentCourseID=id; s.connected=true
        s.statisticsOverride = { _,_ in throw AppError.message("模拟故障") }
        _ = await s.pollRealtimeData(courseID:id,now:now)
        await s.refreshCourseData(id)
        XCTAssertEqual(s.saved.courses[0].analytics?.points.first?.count,33)
        XCTAssertNil(s.saved.courses[0].analytics?.metrics)
        XCTAssertNotNil(s.dataErrors[id]); XCTAssertTrue(s.dataSyncBusy.isEmpty)
    }
}
