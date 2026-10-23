import XCTest
import AppKit
import AssistantCore
@testable import Assistant

final class ClassroomTests: XCTestCase {
    @MainActor func testMultipleChoiceUsesCommaSeparatedAnswersInBothRequests() async throws {
        let s = store(); s.channel = "100"; s.ensureCourse()
        let e = Exercise(question: "哪些方式可以登录？", options: ["微信", "手机号", "账号", "邮箱"], correctIndices: [2, 0, 1], explanation: "课堂提到了前三种", evidence: "课堂原文里提到三种登录方式")
        XCTAssertEqual(s.exercisePayload(e)["answer"] as? String, "A,B,C")
        s.saved.courses[0].exercises = [e]
        s.questionBankOverride = { path, _, params in
            if path.contains("list-question") { return ["list": []] }
            XCTAssertEqual(params["answer"], "A,B,C")
            return "multi-id"
        }
        let saved = try await s.ensureExerciseInQuestionBank(e, courseID: s.currentCourseID!)
        XCTAssertEqual(saved.platformID, "multi-id")
    }
    @MainActor func testDefiniteSaveRejectionAllowsRetry() async throws {
        let s = store(); s.channel = "100"; s.ensureCourse()
        let e = Exercise(question: "题", options: ["甲", "乙"], correctIndices: [0], explanation: "说明", evidence: "测试使用的课堂原文")
        s.saved.courses[0].exercises = [e]
        var attempts = 0
        s.questionBankOverride = { path, _, _ in
            if path.contains("list-question") { return ["list": []] }
            attempts += 1
            if attempts == 1 { throw QuestionBankRejected(message: "请提交正确的答案值") }
            return "retry-id"
        }
        do { _ = try await s.ensureExerciseInQuestionBank(e, courseID: s.currentCourseID!); XCTFail("Expected rejection") } catch {}
        let pending = s.currentCourse!.exercises!.first!
        XCTAssertEqual(pending.platformSavePending, false)
        let saved = try await s.ensureExerciseInQuestionBank(pending, courseID: s.currentCourseID!)
        XCTAssertEqual(saved.platformID, "retry-id")
    }
    @MainActor func testQuestionBankRejectsBusinessErrorWithoutExposingSecrets() throws {
        let invalid = Data(#"{"code":400,"message":"请提交正确的答案值"}"#.utf8)
        XCTAssertThrowsError(try Store.questionBankResponse(invalid, status: 400)) { error in
            XCTAssertTrue(error is QuestionBankRejected)
            XCTAssertEqual(error.localizedDescription, "请提交正确的答案值")
        }
        let unknown = Data(#"{"code":400,"message":"token=private"}"#.utf8)
        XCTAssertThrowsError(try Store.questionBankResponse(unknown, status: 400)) { error in
            XCTAssertFalse(error.localizedDescription.contains("private"))
        }
    }
    @MainActor func testGeneratedExerciseIsSavedBeforeSending() async throws {
        let s = store(); s.channel = "100"; s.ensureCourse()
        let source = "变量用于保存需要使用的数据。"
        s.saved.courses[0].transcript = source
        let e = Exercise(question: "变量有什么用？", options: ["保存数据", "播放视频"], correctIndices: [0], explanation: "保存数据", evidence: source)
        s.saved.courses[0].exercises = [e]
        var created = 0, sent = 0
        s.questionBankOverride = { path, _, _ in
            if path.contains("list-question") { return ["list": []] }
            created += 1; return "q-created"
        }
        s.interactionCallOverride = { _, method, args in
            if method == "getOngoingStatus" { return ["isOngoing": false] }
            XCTAssertEqual(method, "start"); sent += 1
            XCTAssertEqual(s.currentCourse?.exercises?.first?.platformID, "q-created")
            let question = (args.first as? [String: Any])?["question"] as? [String: Any]
            XCTAssertEqual(question?["questionId"] as? String, "q-created")
            return "q-created"
        }
        _ = try await s.publishExercise(e.id, duration: 0, generation: s.epoch)
        XCTAssertEqual(created, 1); XCTAssertEqual(sent, 1)
        XCTAssertNotNil(s.currentCourse?.exercises?.first?.sentAt)
    }
    @MainActor func testUncertainSaveIsReconciledWithoutDuplicateCreation() async throws {
        let s = store(); s.channel = "100"; s.ensureCourse()
        let source = "变量用于保存需要使用的数据。"
        s.saved.courses[0].transcript = source
        let e = Exercise(question: "变量有什么用？", options: ["保存数据", "播放视频"], correctIndices: [0], explanation: "保存数据", evidence: source)
        s.saved.courses[0].exercises = [e]
        let courseID = s.currentCourseID!
        var created = 0
        s.questionBankOverride = { path, _, _ in
            if path.contains("list-question") {
                return ["list": created == 0 ? [] : [["questionId": "q", "name": e.question, "options": e.options, "answer": "A"]]] as [String: Any]
            }
            created += 1; throw AppError.message("timeout")
        }
        do { _ = try await s.ensureExerciseInQuestionBank(e, courseID: courseID); XCTFail("Expected timeout") } catch {}
        let pending = s.currentCourse!.exercises!.first!
        XCTAssertEqual(pending.platformSavePending, true)
        let recovered = try await s.ensureExerciseInQuestionBank(pending, courseID: courseID)
        XCTAssertEqual(recovered.platformID, "q"); XCTAssertEqual(created, 1)
    }
    func testLiveNotebookExcludesPostClassOutputs() {
        let tabs = NotebookSection.enabled(in: CapabilitySelection())
        XCTAssertFalse(tabs.contains(.summary)); XCTAssertFalse(tabs.contains(.outline)); XCTAssertFalse(tabs.contains(.handout))
        XCTAssertTrue(tabs.contains(.interactions))
    }
    @MainActor func testSendErrorStaysNextToItsExercise() async {
        let s = store(); s.ensureCourse()
        let e = Exercise(question: "题目", options: ["甲", "乙"], correctIndices: [0], explanation: "解释", evidence: "足够长度的课堂原文")
        s.toolOverride = { _, _ in throw AppError.message("已有答题正在进行") }
        s.sendExercise(e)
        await s.exerciseSendTasks[e.id]?.value
        XCTAssertEqual(s.exerciseSendErrors[e.id], "已有答题正在进行")
        XCTAssertNil(s.exerciseSendTasks[e.id])
    }
    @MainActor func store() -> Store { Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")) }
    @MainActor func settle(_ s: Store) async {
        for _ in 0..<100 { if s.pendingIncoming == 0 { break }; await Task.yield() }
    }
    @MainActor func testFlowStacksStreamAndKeepsPinned() {
        let s = store(); let q = PendingMessage(title: "问题", question: "怎么操作")
        s.messages = [q]; s.flow("发送中"); s.flow("已发送")
        XCTAssertEqual(s.messages.count, 3); XCTAssertEqual(s.messages.map(\.title), ["问题", "发送中", "已发送"])
        XCTAssertEqual(s.messages.first?.id, q.id); XCTAssertFalse(s.messages.last!.pinned)
        XCTAssertEqual(Store.recentStreamMessages(s.messages, lifetime: s.flowLifetime, limit: 3).map(\.title), ["发送中", "已发送"])
    }
    @MainActor func testSessionReconnectAndRepeatedChannel() throws {
        let s = store(); s.channel = "123"; s.ensureCourse()
        s.adoptSession("session-a", started: Date(timeIntervalSince1970: 100))
        let a = try XCTUnwrap(s.currentCourseID)
        s.appendTranscript("第一场讲课。", courseID: a)
        s.adoptSession("session-a", started: nil)
        XCTAssertEqual(s.currentCourseID, a); XCTAssertEqual(s.saved.courses.count, 1)
        s.saved.capabilities.set(.courseArchive, enabled: false)
        s.adoptSession("session-b", started: Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(s.currentCourseID, a); XCTAssertEqual(s.saved.courses.count, 2)
        XCTAssertEqual(s.saved.courses.first?.platformSessionID, "session-b")
        XCTAssertEqual(s.saved.courses.last?.transcript, "第一场讲课。\n")
    }

    @MainActor func testNewClassClearsBubbleEvenWithReusedPlatformSession() throws {
        let s = store(); s.channel = "123"; s.ensureCourse()
        s.adoptSession("session-reuse", started: Date(timeIntervalSince1970: 100))
        let first = try XCTUnwrap(s.currentCourseID)
        s.appendTranscript("上一场讲课内容。", courseID: first)
        s.messages = [PendingMessage(kind: .question, title: "旧待答", question: "旧问题", people: ["A"])]
        s.flow("已忽略", detail: "旧动态")
        s.addInteraction(LiveInteraction(kind: .notice, platformID: "old", content: "旧公告"), courseID: first)
        s.finishCourse()
        XCTAssertNil(s.currentCourseID)
        s.resetLiveBubbleState()
        XCTAssertTrue(s.messages.isEmpty)
        s.ensureCourse()
        s.adoptSession("session-reuse", started: Date(timeIntervalSince1970: 200))
        let second = try XCTUnwrap(s.currentCourseID)
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(s.messages.filter { $0.kind == .question }.isEmpty, "prior pending must not return on new class")
        XCTAssertTrue((s.currentCourse?.interactions ?? []).isEmpty)
        XCTAssertTrue((s.currentCourse?.transcript ?? "").isEmpty)
        XCTAssertEqual(s.saved.courses.filter { $0.platformSessionID == "session-reuse" }.count, 2)
    }

    @MainActor func testQuestionAggregationCountsUserIDsNotNicknames() async throws {
        let s = store(); s.ensureCourse()
        s.classifyMessage = { _, groups in ("question", groups.first?.0 ?? "none") }
        s.receive(ClassroomMessage(id: "a", userID: "1", name: "同名", text: "怎么操作")); await settle(s)
        s.receive(ClassroomMessage(id: "b", userID: "1", name: "同名", text: "怎么操作")); await settle(s)
        s.receive(ClassroomMessage(id: "c", userID: "2", name: "同名", text: "怎么操作")); await settle(s)
        XCTAssertEqual(s.messages.filter { $0.kind == .question }.count, 1)
        XCTAssertEqual(s.messages.first?.people.count, 2)
        XCTAssertEqual(s.messages.first?.sourceMessages.count, 3)
        s.receive(ClassroomMessage(id: "c", userID: "2", name: "同名", text: "怎么操作")); await settle(s)
        XCTAssertEqual(s.currentCourse?.events?.count, 3)
    }
    @MainActor func testHandledPersistsForBothActors() throws {
        let s = store(); s.ensureCourse(); let id = try XCTUnwrap(s.currentCourseID)
        s.demo = true
        let a = PendingMessage(title: "回放", question: "哪里看回放", draft: "课程主页", people: ["A"])
        let b = PendingMessage(title: "练习", question: "哪里看练习", draft: "资料区", people: ["B"])
        s.messages = [a,b]; s.send(a.id, auto: true); s.send(b.id)
        let saved = try s.file.read(); let course = try XCTUnwrap(saved.courses.first { $0.id == id })
        XCTAssertEqual(course.operations?.map(\.actor), ["助教", "主讲"])
        XCTAssertEqual(course.answers.map(\.actor), ["助教", "主讲"])
        XCTAssertFalse(s.messages.contains { $0.kind == .question })
    }
    @MainActor func testNotebookGroundingDedupAndKnowledgeDestination() async throws {
        let s = store(); s.ensureCourse(); let id = try XCTUnwrap(s.currentCourseID)
        let text = "变量用于存储数据，函数用于封装可复用的操作。学习编程需要理解变量和函数的区别，并通过实际操作掌握这些概念。"
        s.appendTranscript(text, courseID: id)
        s.saved.libraries = [KnowledgeBase(name: "原资料")]
        s.saved.capabilities.set(.faqToKnowledge, enabled: true)
        s.notebookGenerate = { source in ["completed_transcript": source, "points": [["text": "变量存储数据", "evidence": "变量用于存储数据，函数用于封装可复用的操作"]], "exercises": [["question": "变量用于什么？", "options": ["存储数据", "封装操作"], "correct_indices": [0], "explanation": "变量用于存储数据。", "evidence": "变量用于存储数据，函数用于封装可复用的操作"], ["question": "编造", "options": ["A", "B"], "correct_indices": [8], "explanation": "不存在", "evidence": "不在原文"]]] }
        await s.notebookTick(final: true)
        XCTAssertEqual(s.currentCourse?.exercises?.count, 1)
        XCTAssertEqual(s.currentCourse?.knowledgePoints?.count, 1)
        XCTAssertEqual(s.saved.libraries.first?.documents.count, 0)
        XCTAssertEqual(s.saved.libraries.last?.documents.count, 1)
        s.appendTranscript(text, courseID: id); await s.notebookTick(final: true)
        XCTAssertEqual(s.currentCourse?.exercises?.count, 1)
        XCTAssertEqual(s.saved.libraries.last?.documents.count, 1)
    }
    @MainActor func testNotebookRetainsIncompleteTailAcrossChecks() async throws {
        let s = store(); s.ensureCourse(); let id = try XCTUnwrap(s.currentCourseID)
        s.appendTranscript(String(repeating: "变量用于存储数据。", count: 8), courseID: id)
        let original = try XCTUnwrap(s.currentCourse?.transcript)
        s.notebookGenerate = { _ in ["completed_transcript": "", "points": [], "exercises": []] }
        await s.notebookTick()
        XCTAssertEqual(s.currentCourse?.notebookOffset ?? 0, 0)
        s.appendTranscript("变量讲完了。接下来函数的参数包括", courseID: id)
        let full = try XCTUnwrap(s.currentCourse?.transcript)
        let boundary = try XCTUnwrap(full.range(of: "接下来"))
        let completed = String(full[..<boundary.lowerBound])
        s.notebookGenerate = { source in
            XCTAssertTrue(source.contains(original))
            XCTAssertTrue(source.contains("函数的参数包括"))
            return ["completed_transcript": completed, "points": [], "exercises": []]
        }
        await s.notebookTick()
        XCTAssertEqual(s.currentCourse?.notebookOffset, completed.count)
        XCTAssertTrue(String(full.dropFirst(completed.count)).hasPrefix("接下来"))
        s.notebookGenerate = { _ in ["completed_transcript": "错误边界", "points": [], "exercises": []] }
        await s.notebookTick(final: true)
        XCTAssertEqual(s.currentCourse?.notebookOffset, completed.count)
        XCTAssertNotNil(s.currentCourse?.notebookError)
    }
    @MainActor func testNotebookFailureDoesNotConsumeTranscript() async throws {
        let s = store(); s.ensureCourse(); let id = try XCTUnwrap(s.currentCourseID)
        s.appendTranscript(String(repeating: "这是课堂知识。", count: 12), courseID: id)
        s.notebookGenerate = { _ in throw AppError.message("网络故障") }
        await s.notebookTick()
        XCTAssertNil(s.currentCourse?.notebookOffset); XCTAssertNotNil(s.currentCourse?.notebookError)
    }
    @MainActor func testTimedSendDisabledDuringGenerationNeverSends() async throws {
        let s = store(); s.ensureCourse(); s.setCapability(.welcomeRecap, enabled: true)
        s.appendTranscript("欢迎学习变量和函数。", courseID: try XCTUnwrap(s.currentCourseID)); s.newArrivals = 3
        var sent = false
        s.recapGenerate = { _ in s.setCapability(.welcomeRecap, enabled: false); return "欢迎" }
        s.recapSend = { _ in sent = true }
        let result = await s.recapTick()
        XCTAssertNil(result); XCTAssertFalse(sent); XCTAssertEqual(s.newArrivals, 0)
    }
    @MainActor func testFailedQuoteSendRetainsBuffer() async throws {
        let s = store(); s.ensureCourse(); s.setCapability(.quoteCards, enabled: true)
        let source = "学习编程最重要的是每天动手写一点代码，坚持比天赋更重要。"
        s.appendTranscript(source, courseID: try XCTUnwrap(s.currentCourseID))
        s.quoteGenerate = { text,_ in String(text.prefix(20)) }; s.quoteSend = { _ in throw AppError.message("发送失败") }
        let result = await s.quoteTick()
        XCTAssertNil(result); XCTAssertTrue(s.quoteBuffer.contains(source)); XCTAssertTrue(s.handled.isEmpty)
    }
    @MainActor func testToolValidationAndSessionGuards() async throws {
        XCTAssertThrowsError(try AssistantTool.validate("start_checkin", ["duration_seconds": 0,"tips":"签到"]))
        XCTAssertThrowsError(try AssistantTool.validate("start_checkin", ["duration_seconds": true,"tips":"签到"]))
        XCTAssertThrowsError(try AssistantTool.validate("unknown", [:]))
        let s = store(); var called = 0
        s.toolOverride = { _,_ in called += 1; return ["ok": true] }
        do { _ = try await s.performTool("publish_notice", arguments: ["content":"通知"], generation: UUID()); XCTFail("stale task") } catch {}
        XCTAssertEqual(called, 0)
        _ = try await s.performTool("publish_notice", arguments: ["content":"通知"], generation: s.epoch)
        XCTAssertEqual(called, 1); XCTAssertEqual(s.handled.count, 1)
        XCTAssertEqual(s.messages.last?.title, "已发布聊天室公告")
    }
    @MainActor func testExerciseOneClickSendAndReviewPersistence() async throws {
        let s = store(); s.ensureCourse(); let id = try XCTUnwrap(s.currentCourseID)
        s.appendTranscript("变量用于存储数据，函数用于封装操作。", courseID: id)
        let e = Exercise(question: "变量作用？", options: ["存储数据", "封装操作"], correctIndices: [0], explanation: "变量存储数据", evidence: "变量用于存储数据，函数用于封装操作")
        s.saved.courses[0].exercises = [e]; s.demo = true
        _ = try await s.performTool("start_answer_card", arguments: ["exercise_id":e.id.uuidString,"duration_seconds":0], generation:s.epoch)
        XCTAssertNotNil(s.currentCourse?.exercises?.first?.sentAt)
        do { _ = try await s.publishExercise(e.id, duration:60, generation:s.epoch); XCTFail("duplicate") } catch {}
        XCTAssertNotNil(try s.file.read().courses.first?.exercises?.first?.platformID)
    }
}

extension ClassroomTests {
    @MainActor func testBundledSDKRunsInsideWebKitWithNativeTransport() async throws {
        _ = NSApplication.shared
        let gateway = ChatGateway(); gateway.isConnected = true; gateway.roomID = "test-room"; gateway.sessionID = "test-session"
        let bridge = InteractionBridge(gateway: gateway); defer { bridge.reset() }
        var sent: [[String:Any]] = []
        bridge.transportOverride = { body in
            guard body["kind"] as? String == "socket", let raw = body["raw"] as? String, let payload = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String:Any] else { throw AppError.message("unexpected transport") }
            sent.append(payload); return ["code":200]
        }
        _ = try await bridge.call("Notice", "publishNotice", ["测试公告"])
        _ = try await bridge.call("CheckIn", "start", [["duration":60,"tips":"请签到"]])
        XCTAssertEqual(sent.map { $0["EVENT"] as? String }, ["BULLETIN","SIGN_IN"])
        XCTAssertEqual((sent.last?["data"] as? [String:Any])?["sessionId"] as? String, "test-session")
    }
}

extension ClassroomTests {
    @MainActor func testIgnoredFeedbackLeavesPinnedAreaAndDoesNotImmediatelyReturn() async throws {
        let s = store(); s.ensureCourse()
        s.classifyMessage = { _, groups in ("technical", groups.first?.0 ?? "none") }
        s.receive(ClassroomMessage(id: "feedback-a", userID: "viewer-a", name: "甲", text: "声音太小")); await settle(s)
        let id = try XCTUnwrap(s.messages.first { $0.kind == .technical }?.id)
        s.ignore(id)
        XCTAssertFalse(s.messages.contains { $0.pinned })
        XCTAssertEqual(s.handled.first?.kind, "dismiss")
        s.receive(ClassroomMessage(id: "feedback-b", userID: "viewer-b", name: "乙", text: "老师声音小")); await settle(s)
        XCTAssertFalse(s.messages.contains { $0.kind == .technical })
        XCTAssertEqual(s.handled.first?.sourceMessageIDs.count, 2)
        s.restorePending(); XCTAssertFalse(s.messages.contains { $0.kind == .technical })
    }
    @MainActor func testRoomSignatureNeedsNoAccountKey() {
        XCTAssertEqual(ChatGateway.roomSignature("test-room"), "ae1bb9961e719a1d2f1bba00f779026b")
        XCTAssertNotEqual(ChatGateway.roomSignature("test-room"), ChatGateway.roomSignature("other-room"))
    }
    @MainActor func testSpeechConfigurationIsFixedDespiteLegacyState() {
        let s = store()
        s.saved.preferences.region = "ap-southeast-1"; s.saved.speech.model = "legacy"
        XCTAssertEqual(s.client.host, SpeechSettings.fixedHost)
        XCTAssertEqual(SpeechSettings.fixedModel, "qwen3-asr-flash-realtime")
    }
}

extension ClassroomTests {
    @MainActor func testSupportLogCreatesOneDirectoryPerStartAndRedactsSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let logger = SupportLog(root: root)
        logger.start(channel: "123"); let first = try XCTUnwrap(logger.directory)
        logger.write("test", fields: ["API_Key":"secret-value", "nested":["token":"private-token"],"message":"Bearer confidential sk-private-key"])
        let text = try String(contentsOf: first.appendingPathComponent("assistant-0.jsonl"))
        XCTAssertFalse(text.contains("secret-value")); XCTAssertFalse(text.contains("private-token")); XCTAssertFalse(text.contains("confidential")); XCTAssertFalse(text.contains("sk-private-key"))
        XCTAssertTrue(text.contains("[redacted]"))
        logger.start(channel: "123"); XCTAssertNotEqual(first, logger.directory)
    }
    @MainActor func testNotebookTabsFollowCapabilitySelection() {
        var selection = CapabilitySelection()
        selection.set(.quoteCards, enabled: false); selection.set(.questions, enabled: false)
        var tabs = NotebookSection.enabled(in: selection)
        XCTAssertFalse(tabs.contains(.transcript)); XCTAssertTrue(tabs.contains(.interactions)); XCTAssertFalse(tabs.contains(.quotes)); XCTAssertFalse(tabs.contains(.questions)); XCTAssertTrue(tabs.contains(.keyPoints))
        selection.set(.questions, enabled: true); selection.set(.quoteCards, enabled: true)
        tabs = NotebookSection.enabled(in: selection)
        XCTAssertTrue(tabs.contains(.questions)); XCTAssertTrue(tabs.contains(.quotes))
        selection.set(.courseArchive, enabled: false)
        XCTAssertFalse(NotebookSection.enabled(in: selection).contains(.handout))
    }
    @MainActor func testClassroomCountsMatchShownRows() {
        let s = store()
        var evaluating = PendingMessage(title: "判断中", question: "还在判断"); evaluating.evaluating = true
        s.messages = [PendingMessage(title: "回放？", question: "回放在哪"), PendingMessage(kind: .material, title: "课件", question: "发下课件"),
                      PendingMessage(kind: .technical, title: "卡顿", question: "卡了"), PendingMessage(kind: .risk, title: "广告", question: "加微信"),
                      PendingMessage(kind: .notice, title: "欢迎", question: ""), evaluating]
        XCTAssertEqual(s.classroomQuestionCount, 2)   // question + material request, not the one still being evaluated
        XCTAssertEqual(s.classroomFeedbackCount, 2)   // feedback + violation
    }
    @MainActor func testTranscriptCaptionShowsLatestSentenceOnlyWhileLive() {
        XCTAssertEqual(TranscriptCaption.latestSentence("变量用于存储数据。函数封装操作！现在看第三个例子"), "现在看第三个例子")
        XCTAssertEqual(TranscriptCaption.latestSentence("先看定义。\n"), "先看定义")
        XCTAssertNil(TranscriptCaption.latestSentence("。 \n"))
        let s = store()
        var c = CourseSession(title: "课", channel: "1"); c.transcriptSegments = [TranscriptSegment(text: "第一句。第二句")]
        XCTAssertNil(TranscriptCaption.sentence(store: s, course: c))   // not live
        s.connected = true
        XCTAssertEqual(TranscriptCaption.sentence(store: s, course: c)?.text, "第二句")
        c.ended = Date(); XCTAssertNil(TranscriptCaption.sentence(store: s, course: c))
        var empty = CourseSession(title: "课", channel: "1"); empty.transcript = ""
        XCTAssertNil(TranscriptCaption.sentence(store: s, course: empty))
    }
    @MainActor func testViewingReminderArchivesIt() {
        let s = store(); s.ensureCourse()
        let m = PendingMessage(kind: .technical, title: "卡顿", question: "声音卡了")
        s.messages = [m]; s.review(m.id)
        XCTAssertEqual(s.viewedMessage?.id, m.id)
        XCTAssertEqual(s.handled.first?.kind, "viewed"); XCTAssertFalse(s.messages.contains { $0.id == m.id })
    }
    @MainActor func testLessonImportIsIdempotentAndPreservesExistingLibraries() throws {
        let s = store(); s.saved.libraries = [KnowledgeBase(name:"已有资料")]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("xblesson")
        defer { try? FileManager.default.removeItem(at:url) }
        let lesson = LessonImport(id:UUID(),name:"测试课",documents:[Document(name:"课程",text:"课程原文")],enableTestCapabilities:true)
        try JSONEncoder().encode(lesson).write(to:url)
        s.importLesson(url); s.importLesson(url)
        XCTAssertEqual(s.saved.libraries.count,2); XCTAssertEqual(s.saved.libraries.first?.name,"已有资料")
        XCTAssertTrue(s.enabled(.welcomeRecap)); XCTAssertTrue(s.enabled(.quoteCards))
    }
    @MainActor func testWelcomeOnlyUsesCurrentOneMinuteWindow() async throws {
        let s = store(); s.ensureCourse(); s.setCapability(.welcomeRecap,enabled:true)
        s.appendTranscript("现在开始讲解变量与函数。", courseID:try XCTUnwrap(s.currentCourseID))
        s.newArrivals = 1; s.newArrivalTimes = [Date().addingTimeInterval(-70)]
        var sent = 0; s.recapGenerate = { _ in "欢迎" }; s.recapSend = { _ in sent += 1 }
        _ = await s.recapTick(); XCTAssertEqual(sent,0)
        s.newArrivals = 1; s.newArrivalTimes = [Date()]
        _ = await s.recapTick(); XCTAssertEqual(sent,1)
        _ = await s.recapTick(); XCTAssertEqual(sent,1)
        XCTAssertEqual(s.recapInterval,60); XCTAssertEqual(s.quoteInterval,60); XCTAssertEqual(s.quotePhaseOffset,0)
    }
}
