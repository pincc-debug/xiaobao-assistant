import XCTest
import AssistantCore
@testable import Assistant

/// 问卷 / 抢答 / 倒计时 in-progress cards, feedback detail, command echo, transcript records.
final class InteractionCardTests: XCTestCase {
    @MainActor func makeStore() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.capabilities.set(.courseArchive, enabled: false)
        s.channel = "123"; s.ensureCourse(); return s
    }
    @MainActor func testRushTimerAndQuestionnaireGetCardsThatStopToolsEnd() async throws {
        let s = makeStore()
        s.toolOverride = { name, _ in name == "start_rush_answer" ? ["rushAnswerId": "r1"] as [String: Any] : ["ok": true] }
        _ = try await s.performTool("start_rush_answer", arguments: ["duration_seconds": 30], generation: s.epoch)
        _ = try await s.performTool("start_timer", arguments: ["duration_seconds": 300], generation: s.epoch)
        _ = try await s.performTool("start_questionnaire", arguments: ["questionnaire_id": "q9"], generation: s.epoch)
        XCTAssertEqual(s.pinnedInteractions.map(\.kind), [.rush, .timer, .questionnaire])
        XCTAssertEqual(s.pinnedInteractions.first?.platformID, "r1")
        XCTAssertEqual(s.pinnedInteractions.first?.summary, "进行中")
        XCTAssertEqual(LiveInteraction.Kind.rush.badge, .rush)
        XCTAssertEqual(LiveInteraction.Kind.timer.endTitle, "结束倒计时")
        _ = try await s.performTool("stop_rush_answer", arguments: ["rush_answer_id": "r1"], generation: s.epoch)
        _ = try await s.performTool("end_timer", arguments: [:], generation: s.epoch)
        XCTAssertEqual(s.pinnedInteractions.map(\.kind), [.questionnaire])
        XCTAssertEqual(s.currentCourse?.interactions?.first?.summary, "已结束")
        // ending again adds nothing
        _ = try await s.performTool("end_timer", arguments: [:], generation: s.epoch)
        XCTAssertEqual(s.currentCourse?.interactions?.count, 3)
    }
    @MainActor func testEndButtonStopsTheMatchingPlatformInteraction() async throws {
        let s = makeStore(), course = s.currentCourseID!
        let q = LiveInteraction(kind: .questionnaire, platformID: "q9", content: "课后问卷")
        s.addInteraction(q, courseID: course)
        var calls: [String] = []
        s.interactionCallOverride = { module, method, args in calls.append("\(module).\(method)(\(args.map { "\($0)" }.joined()))"); return [:] }
        await s.closeInteraction(q.id, courseID: course)
        XCTAssertEqual(calls, ["Questionnaire.stop(q9)"])
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
        XCTAssertTrue(s.currentCourse?.interactions?.first?.finalized == true)
    }
    @MainActor func testTimedCardsEndOnTheirOwnAfterTheDeadline() async {
        let s = makeStore(), course = s.currentCourseID!
        var t = LiveInteraction(kind: .timer, platformID: "t", content: "")
        t.deadline = Date().addingTimeInterval(-1)
        var future = LiveInteraction(kind: .rush, platformID: "r", content: "")
        future.deadline = Date().addingTimeInterval(60)
        s.addInteraction(t, courseID: course); s.addInteraction(future, courseID: course)
        var calls: [String] = []
        s.interactionCallOverride = { m, f, _ in
            calls.append("\(m).\(f)")
            // Expired timer must end the platform timer (started with enableTimeOut:false). Rush stays local-only.
            if m == "Timer", f == "end" { return [:] }
            XCTFail("unexpected platform call for status-only cards: \(m).\(f)"); return [:]
        }
        await s.refreshInteraction(t.id, courseID: course)
        await s.refreshInteraction(future.id, courseID: course)
        XCTAssertEqual(calls, ["Timer.end"])
        XCTAssertEqual(s.pinnedInteractions.map(\.id), [future.id])
        XCTAssertEqual(s.interactionRecord(t.id, courseID: course)?.ended, t.deadline)
    }
    func testPendingQuestionsGroupComesFirstOnlyWhileQuestionsWait() {
        XCTAssertEqual(ClassroomPanel.sections(live: true, reminders: true, questions: false, feedback: true), [.live, .reminders, .feedback])
        XCTAssertEqual(ClassroomPanel.sections(live: true, reminders: true, questions: true, feedback: true), [.questions, .live, .reminders, .feedback])
        XCTAssertEqual(ClassroomPanel.sections(live: true, reminders: false, questions: true, feedback: false), [.questions, .live])
        XCTAssertEqual(ClassroomPanel.sections(live: false, reminders: false, questions: true, feedback: true), [.questions, .feedback])
        XCTAssertEqual(ClassroomPanel.sections(live: false, reminders: false, questions: false, feedback: false), [])
    }
    func testFailedCardShowsOnlyTheReason() {
        XCTAssertEqual(ActiveInteractions.failureReason("结果同步失败：网络连接中断"), "网络连接中断")
        XCTAssertEqual(ActiveInteractions.failureReason("结果更新失败：请求超时"), "请求超时")
        XCTAssertEqual(ActiveInteractions.failureReason("签到名单尚未同步完整"), "签到名单尚未同步完整")
        XCTAssertEqual(ActiveInteractions.failureReason("网络连接中断，请稍后重试"), "网络连接中断")
        XCTAssertNil(ActiveInteractions.failureReason("结果更新失败，可重试"))
        XCTAssertNil(ActiveInteractions.failureReason("结果同步失败："))
        XCTAssertNil(ActiveInteractions.failureReason(nil))
        XCTAssertNil(ActiveInteractions.failureReason("  "))
        for kind in [LiveInteraction.Kind.answer, .checkin, .rush, .timer, .questionnaire] {   // every type: 同步失败 + 重试
            var item = LiveInteraction(kind: kind, platformID: "x", content: ""); item.ended = Date(); item.error = "结果同步失败：网络连接中断"
            let status = ActiveInteractions.status(item, busy: false)
            XCTAssertEqual(status, .failed); XCTAssertEqual(ActiveInteractions.action(item, status: status), "重试")
            XCTAssertEqual(ActiveInteractions.status(item, busy: true), .syncing)   // retry in flight: no failed line
        }
    }
    func testAnalysisOnlyFailureKeepsNormalStatus() {
        var quiz = LiveInteraction(kind: .answer, platformID: "q", content: "题")
        quiz.snapshots = [InteractionSnapshot(count: 24, correct: 17, options: [17, 5, 2])]
        quiz.error = ActiveInteractions.analysisUnavailableError
        XCTAssertTrue(ActiveInteractions.analysisOnlyFailure(quiz)); XCTAssertFalse(ActiveInteractions.syncFailed(quiz))
        XCTAssertEqual(ActiveInteractions.status(quiz, busy: false), .running)   // running quiz: still 「进行中」 + 「结束答题」
        XCTAssertEqual(ActiveInteractions.action(quiz, status: .running), "结束答题")
        quiz.ended = Date(); XCTAssertEqual(ActiveInteractions.status(quiz, busy: false), .awaitingPublish)   // ended + stats → 待公布
        quiz.error = "结果更新失败：网络连接中断"   // stats not saved → red 同步失败
        XCTAssertFalse(ActiveInteractions.analysisOnlyFailure(quiz)); XCTAssertTrue(ActiveInteractions.syncFailed(quiz))
        XCTAssertEqual(ActiveInteractions.status(quiz, busy: false), .failed)
        var empty = LiveInteraction(kind: .answer, platformID: "e", content: "题"); empty.error = ActiveInteractions.analysisUnavailableError
        XCTAssertFalse(ActiveInteractions.analysisOnlyFailure(empty))   // no stats at all: treated as a sync failure
        XCTAssertEqual(ActiveInteractions.status(empty, busy: false), .failed)
        quiz.error = nil; XCTAssertFalse(ActiveInteractions.analysisOnlyFailure(quiz)); XCTAssertFalse(ActiveInteractions.syncFailed(quiz))
        XCTAssertEqual(AnalysisUnavailableLine.text(retry: true), "分析暂不可用 · 重试")
        XCTAssertEqual(AnalysisUnavailableLine.text(retry: false), "分析暂不可用")
    }
    func testCorrectOptionOnlyRevealedAfterTheQuizEnds() {
        var item = LiveInteraction(kind: .answer, platformID: "q", content: "题")
        XCTAssertFalse(ActiveInteractions.revealsCorrect(item))
        item.ended = Date()
        XCTAssertTrue(ActiveInteractions.revealsCorrect(item))
        XCTAssertEqual(ActiveInteractions.status(item, busy: false), .syncing)   // no stats yet → still syncing
        XCTAssertNil(ActiveInteractions.action(item, status: .syncing))   // syncing: no button
        item.snapshots = [InteractionSnapshot(count: 3, correct: 2, options: [2, 1])]
        XCTAssertEqual(ActiveInteractions.status(item, busy: false), .awaitingPublish)
        XCTAssertEqual(ActiveInteractions.action(item, status: .awaitingPublish), "公布结果")
        item.error = "失败"; XCTAssertEqual(ActiveInteractions.status(item, busy: false), .failed)
        XCTAssertEqual(ActiveInteractions.action(item, status: .failed), "重试")
        var checkin = LiveInteraction(kind: .checkin, platformID: "c", content: "")
        XCTAssertEqual(ActiveInteractions.action(checkin, status: ActiveInteractions.status(checkin, busy: false)), "结束签到")
        checkin.ended = Date(); XCTAssertNil(ActiveInteractions.action(checkin, status: ActiveInteractions.status(checkin, busy: false)))
        XCTAssertEqual(ActiveInteractions.status(checkin, busy: true), .syncing)
        let all = [LiveInteraction(kind: .checkin, platformID: "1", content: ""), LiveInteraction(kind: .checkin, platformID: "2", content: "")]
        XCTAssertEqual(ActiveInteractions.round(all[1], in: all), "第 2 轮")
    }
    @MainActor func testFeedbackDetailShowsCountAndTimeRange() {
        var m = PendingMessage(kind: .technical, title: "卡顿", question: "声音卡")
        m.people = ["小王", "小李", "阿张"]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        m.time = f.date(from: "2026-10-20 22:31")!; m.lastTime = f.date(from: "2026-10-20 22:38")!
        XCTAssertEqual(PendingBoard.viewSummary(m), "3 人反馈 · 22:31–22:38")
        XCTAssertEqual(PendingBoard.viewNames(m), "小李、小王、阿张".split(separator: "、").map(String.init).sorted().joined(separator: "、"))
        m.lastTime = m.time
        XCTAssertEqual(PendingBoard.viewSummary(m), "3 人反馈 · 22:31")
    }
    @MainActor func testCommandProcessingShowsTheInstructorsWords() {
        let s = makeStore()
        s.flow(Store.commandProcessingTitle, detail: "开始签到 两分钟")
        XCTAssertEqual(s.messages.last?.commandEcho, "「开始签到 两分钟」")
        s.flow("已发布聊天室公告", detail: "通知")
        XCTAssertNil(s.messages.last?.commandEcho)
    }
    @MainActor func testPendingCountIncludesMaterialRequests() {
        let s = makeStore()
        s.messages = [PendingMessage(title: "回放？", question: "回放在哪"), PendingMessage(kind: .material, title: "课件", question: "发下课件"),
                      PendingMessage(kind: .technical, title: "卡顿", question: "卡了")]
        XCTAssertEqual(s.pendingQuestionCount, 2)
        XCTAssertEqual(s.pendingQuestionCount, s.classroomQuestionCount)
    }
    func testTranscriptRecordsGroupSegmentsIntoParagraphs() {
        var c = CourseSession(title: "课", channel: "1")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        c.transcriptSegments = [TranscriptSegment(text: "变量用于存储数据。", time: t0), TranscriptSegment(text: "函数封装操作。", time: t0.addingTimeInterval(20)),
                                TranscriptSegment(text: " ", time: t0.addingTimeInterval(30)), TranscriptSegment(text: "下面做练习。", time: t0.addingTimeInterval(200))]
        let p = TranscriptRecords.paragraphs(c)
        XCTAssertEqual(p.map(\.text), ["变量用于存储数据。函数封装操作。", "下面做练习。"])
        XCTAssertEqual(p.first?.time, t0)
        var old = CourseSession(title: "课", channel: "1"); old.transcript = "第一段\n\n第二段\n"
        XCTAssertEqual(TranscriptRecords.paragraphs(old).map(\.text), ["第一段", "第二段"])
        XCTAssertNil(TranscriptRecords.paragraphs(old).first?.time)
    }

    func testVoiceToolListIncludesDraftPreparationAndLaunchTools() {
        XCTAssertEqual(AssistantTool.voice.map(\.name), [
            "publish_notice", "find_materials", "send_material", "start_checkin", "list_exercises", "prepare_exercise",
            "start_answer_card", "list_questionnaires", "start_questionnaire", "start_timer"
        ])
        XCTAssertEqual(AssistantTool.all.count, 10)
        XCTAssertTrue(AssistantTool.executable.map(\.name).contains("pause_timer"))
        XCTAssertTrue(AssistantTool.executable.map(\.name).contains("publish_answer_result"))
        XCTAssertTrue(AssistantTool.executable.map(\.name).contains("mute_user"))
        XCTAssertTrue(AssistantTool.executable.map(\.name).contains("kick_user"))
        XCTAssertFalse(AssistantTool.voice.map(\.name).contains("pause_timer"))
        XCTAssertFalse(AssistantTool.voice.map(\.name).contains("end_timer"))
        XCTAssertFalse(AssistantTool.voice.map(\.name).contains("stop_checkin"))
    }
    @MainActor func testExpiredTimerCallsPlatformEnd() async {
        let s = makeStore(), course = s.currentCourseID!
        var t = LiveInteraction(kind: .timer, platformID: "t1", content: "")
        t.deadline = Date().addingTimeInterval(-2)
        s.addInteraction(t, courseID: course)
        var calls: [String] = []
        s.interactionCallOverride = { m, f, _ in calls.append("\(m).\(f)"); return [:] }
        await s.refreshInteraction(t.id, courseID: course)
        XCTAssertEqual(calls, ["Timer.end"])
        let done = s.interactionRecord(t.id, courseID: course)
        XCTAssertEqual(done?.ended, t.deadline)
        XCTAssertTrue(done?.finalized == true)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
    }
    @MainActor func testCheckinAutoEndsAfterDeadline() async {
        let s = makeStore(), course = s.currentCourseID!
        var c = LiveInteraction(kind: .checkin, platformID: "c9", content: "课前签到")
        c.deadline = Date().addingTimeInterval(-1)
        s.addInteraction(c, courseID: course)
        var calls: [String] = []
        var stopped = false
        s.interactionCallOverride = { m, f, _ in
            calls.append("\(m).\(f)")
            if f == "getCheckInStatus" { return ["isCheckingIn": !stopped, "checkInId": "c9"] as [String: Any] }
            if f == "stop" { stopped = true; return [:] }
            if f == "getCheckInNum" { return 0 }
            if f == "getCheckInDetail" { return ["checkInNum": 0, "list": []] as [String: Any] }
            return [:]
        }
        await s.refreshInteraction(c.id, courseID: course)
        XCTAssertTrue(calls.contains("CheckIn.stop"))
        XCTAssertNotNil(s.interactionRecord(c.id, courseID: course)?.ended)
    }
    @MainActor func testPauseTimerMarksCardPaused() async {
        let s = makeStore(), course = s.currentCourseID!
        let t = LiveInteraction(kind: .timer, platformID: "t", content: "")
        s.addInteraction(t, courseID: course)
        var calls: [String] = []
        s.interactionCallOverride = { m, f, _ in calls.append("\(m).\(f)"); return [:] }
        await s.pauseTimer(t.id, courseID: course)
        XCTAssertEqual(calls, ["Timer.stop"])
        XCTAssertTrue(s.interactionRecord(t.id, courseID: course)?.timerPaused == true)
        XCTAssertEqual(ActiveInteractions.status(s.interactionRecord(t.id, courseID: course)!, busy: false), .paused)
        XCTAssertEqual(ActiveInteractions.action(s.interactionRecord(t.id, courseID: course)!, status: .paused), "结束倒计时")
        XCTAssertEqual(s.interactionRecord(t.id, courseID: course)?.summary, "已暂停")
    }
    @MainActor func testPublishAnswerResultFinalizesCard() async throws {
        let s = makeStore(), course = s.currentCourseID!
        var item = LiveInteraction(kind: .answer, platformID: "q1", content: "题")
        item.ended = Date()
        item.snapshots = [InteractionSnapshot(count: 2, correct: 1, options: [1, 1])]
        s.addInteraction(item, courseID: course)
        XCTAssertEqual(ActiveInteractions.action(item, status: ActiveInteractions.status(item, busy: false)), "公布结果")
        s.toolOverride = { name, args in
            XCTAssertEqual(name, "publish_answer_result")
            XCTAssertEqual(args["question_id"] as? String, "q1")
            return ["ok": true]
        }
        await s.publishAnswerResult(item.id, courseID: course)
        let done = try XCTUnwrap(s.interactionRecord(item.id, courseID: course))
        XCTAssertTrue(done.resultPublished)
        XCTAssertTrue(done.finalized)
        XCTAssertTrue(s.pinnedInteractions.isEmpty)
    }
}
