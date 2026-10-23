import XCTest
import AssistantCore
@testable import Assistant

final class VoiceExerciseTests: XCTestCase {
    @MainActor func testClassroomSpeechCannotInvokeAttendanceOrOtherPlatformTools() async {
        let s = fixture()
        s.classroomCueClassifierOverride = { _ in "start_checkin" }
        s.interactionCallOverride = { _, _, _ in XCTFail("Passive speech cannot invoke platform APIs"); return [:] }
        s.toolOverride = { _, _ in XCTFail("Passive speech cannot run command tools"); return [:] }
        await s.handleClassroomCue("大家到了吧，发个签到", courseID: s.currentCourseID!, generation: s.epoch)
        XCTAssertTrue((s.currentCourse?.interactions ?? []).isEmpty)
        XCTAssertFalse(Store.mayContainClassroomCue("大家到了吧，帮我发签到"))
    }
    @MainActor func testClassroomCueCreatesDraftWithoutSendingOrOpeningWorkbench() async {
        let s = fixture()
        s.classroomCueClassifierOverride = { _ in "question" }
        s.exerciseDraftOverride = { _, sources in
            ["question": "有哪些登录方式？", "options": ["微信扫码", "手机号", "账号", "邮箱"], "correct_indices": [0,1,2], "explanation": "前三项", "evidence": sources[0].text, "source_ids": [sources[0].id]]
        }
        s.interactionCallOverride = { _, _, _ in XCTFail("Draft only"); return [:] }
        await s.handleClassroomCue("刚才的内容出一道题考考大家", courseID: s.currentCourseID!, generation: s.epoch)
        XCTAssertEqual(s.currentCourse?.exercises?.count, 1)
        XCTAssertNil(s.currentCourse?.exercises?.first?.sentAt)
        XCTAssertFalse(s.detailExpanded)
        XCTAssertFalse(s.currentReminders.isEmpty)
    }
    @MainActor func testClassroomNoteRequiresSourceEvidence() async {
        let s = fixture()
        s.classroomCueClassifierOverride = { _ in "note" }
        s.classroomPointOverride = { source in ["text": "三种登录方式", "evidence": source] }
        await s.handleClassroomCue("这是重点，记一下", courseID: s.currentCourseID!, generation: s.epoch)
        XCTAssertEqual(s.currentCourse?.knowledgePoints?.count, 1)
        s.classroomPointOverride = { _ in ["text": "无依据的内容", "evidence": "这段内容从未在课堂出现"] }
        await s.handleClassroomCue("再记一下", courseID: s.currentCourseID!, generation: s.epoch)
        XCTAssertEqual(s.currentCourse?.knowledgePoints?.count, 1)
    }
    @MainActor private func fixture() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.channel = "100"; s.ensureCourse(); s.demo = true
        s.saved.courses[0].transcript = "课堂讲解了三种登录方式：微信扫码、手机号和账号登录。"
        return s
    }
    @MainActor func testPreparingCreatesLocalSendableDraftWithoutPublishing() async throws {
        let s = fixture()
        s.exerciseDraftOverride = { _, sources in
            ["question": "有哪些登录方式？", "options": ["微信扫码", "手机号", "账号", "邮箱"], "correct_indices": [0,1,2], "explanation": "前三项是课堂提到的方式", "evidence": sources[0].text, "source_ids": [sources[0].id]]
        }
        s.interactionCallOverride = { _, _, _ in XCTFail("Preparing must not publish"); return [:] }
        s.questionBankOverride = { _, _, _ in XCTFail("Preparing must not create a platform question"); return [:] }
        _ = try await s.performTool("prepare_exercise", arguments: ["request": "准备登录方式的题"], generation: s.epoch, instructorRequest: "准备一道登录方式的题")
        let exercise = try XCTUnwrap(s.currentCourse?.exercises?.last)
        XCTAssertNil(exercise.sentAt); XCTAssertNil(exercise.platformID)
        XCTAssertTrue(exercise.isValid())
        XCTAssertEqual(s.requestedNotebookSection, .questions)
        XCTAssertFalse(s.detailExpanded)
    }
    @MainActor func testLateDraftCannotWriteToAnotherClass() async throws {
        let s = fixture()
        s.exerciseDraftOverride = { _, _ in s.epoch = UUID(); return [:] }
        do { _ = try await s.prepareVoiceExercise("准备一道题", generation: s.epoch); XCTFail("Must reject stale draft") } catch {}
        XCTAssertTrue((s.currentCourse?.exercises ?? []).isEmpty)
    }
    @MainActor func testRealModelRoutesPreparationToDraftTool() async throws {
        guard ProcessInfo.processInfo.environment["RUN_VOICE_PREPARE_SMOKE"] == "1" else { throw XCTSkip("Opt-in model test") }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/state.json")
        let state = try StateFile(url: path).read()
        let provider = try XCTUnwrap(state.providers.first { $0.id == state.defaultProviderID })
        let result = try await ProviderAPI.chooseTool(provider, key: Vault.read("provider." + provider.id.uuidString), input: ["instruction": "准备一道答题卡，登录的三种方式，看一下大家上节课有没有学会，先准备好给我看。", "previous": [], "results": []] as [String: Any])
        XCTAssertEqual(result["name"] as? String, "prepare_exercise")
        let s = fixture()
        s.saved.providers = [provider]; s.saved.defaultProviderID = provider.id
        s.providerKeys[provider.id] = Vault.read("provider." + provider.id.uuidString)
        _ = try await s.prepareVoiceExercise("根据本课讲过的三种登录方式，准备一道多选题。", generation: s.epoch)
        let draft = try XCTUnwrap(s.currentCourse?.exercises?.last)
        XCTAssertTrue(draft.isValid())
        XCTAssertNil(draft.sentAt); XCTAssertNil(draft.platformID)
    }
    @MainActor func testCommandLogsKeepNestedCredentialsRedacted() {
        let fields = SupportLog.scrub(["arguments": [["token": "secret", "url": "https://example.com/?loginToken=secret"]]])
        let text = String(describing: fields)
        XCTAssertFalse(text.contains("secret"))
    }
}
