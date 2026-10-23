import XCTest
import AssistantCore
@testable import Assistant

final class PreparationTests: XCTestCase {
    @MainActor private func makeStore() -> Store {
        let store=Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        store.saved.capabilities.set(.courseArchive,enabled:false)
        return store
    }
    @MainActor private func plan(_ store:Store,channel:String="100",title:String="变量与函数") throws -> UUID {
        let id=try store.createPreparation(channel:channel,title:title)
        var plan=try XCTUnwrap(store.preparations(channel).first(where:{$0.id == id}))
        plan.goals="区分变量和函数"; plan.notes="变量存储数据，函数封装操作。"
        plan.documents=[Document(name:"讲义",text:"变量可以赋值。")]
        try store.savePreparation(plan,channel:channel,confirm:true)
        return id
    }
    @MainActor func testCopyStartsWithCourseInfoButNoAssetsOrClassroomData() throws {
        let s = makeStore()
        let id = try plan(s)
        let original = try XCTUnwrap(s.preparations("100").first { $0.id == id })
        let exercise = Exercise(question: "变量的作用？", options: ["保存数据", "画图"], correctIndices: [0], explanation: "用于保存数据", evidence: "变量存储数据")
        var course = CourseSession(title: original.title, channel: "100")
        course.preparation = original
        course.exercises = [exercise]
        course.transcript = "变量存储数据"
        course.outputs = [ArchiveOutput.summary.rawValue: "课程总结"]
        s.saved.courses = [course]
        try s.commitRoom("100") { room, _ in
            for stage in LessonAssetStage.allCases {
                var material = RoomMaterial(title: stage.rawValue, text: "原课程资产", kind: "资料", sources: [], lessonID: id)
                material.stage = stage
                room.materials.append(material)
            }
            room.messages.append(RoomMessage(role: "user", text: "备课对话", lessonID: id))
        }
        let copyID = try s.copyPreparation(original, channel: "100")
        let persisted = try s.file.read()
        let room = try XCTUnwrap(persisted.rooms.first { $0.channel == "100" })
        let copy = try XCTUnwrap(room.preparations?.first { $0.id == copyID })
        XCTAssertEqual(copy.goals, original.goals)
        XCTAssertEqual(copy.notes, original.notes)
        XCTAssertTrue(copy.documents.isEmpty)
        XCTAssertNil(copy.exercises)
        XCTAssertNil(copy.confirmedAt)
        XCTAssertNil(copy.usedByCourseID)
        XCTAssertFalse(room.materials.contains { $0.lessonID == copyID })
        XCTAssertFalse(room.messages.contains { $0.lessonID == copyID })
        XCTAssertEqual(room.materials.filter { $0.lessonID == id }.count, 3)
        XCTAssertEqual(room.preparations?.first { $0.id == id }?.documents.count, 1)
        XCTAssertEqual(persisted.courses.count, 1)
        XCTAssertEqual(persisted.courses[0].exercises?.count, 1)
        XCTAssertEqual(persisted.courses[0].transcript, "变量存储数据")
    }
    @MainActor func testLessonStatesUseThreeStages() throws {
        XCTAssertEqual(LessonStatusDot.Phase(status: "备课中"), .before)
        XCTAssertEqual(LessonStatusDot.Phase(status: "上课中"), .live)
        XCTAssertEqual(LessonStatusDot.Phase(status: "复盘中"), .after)
        let s = makeStore()
        let draftID = try plan(s)
        XCTAssertEqual(s.classroomLessons("100").first { $0.id == draftID }?.status, "备课中")
        XCTAssertEqual(s.lessonAssetStage(channel: "100", lessonID: draftID), .preparation)
        s.channel = "100"; s.ensureCourse()
        let courseID = try XCTUnwrap(s.currentCourseID)
        XCTAssertEqual(s.classroomLessons("100").first { $0.id == courseID }?.status, "上课中")
        XCTAssertEqual(s.lessonAssetStage(channel: "100", lessonID: courseID), .classroom)
        s.currentCourseID = nil
        XCTAssertEqual(s.classroomLessons("100").first { $0.id == courseID }?.status, "复盘中")
        XCTAssertEqual(s.lessonAssetStage(channel: "100", lessonID: courseID), .review)
    }
    @MainActor func testCreateRoomNormalizeAndOldState() async throws {
        let s=makeStore()
        s.saved.preferences.appID = "app"; s.saved.preferences.userID = "owner"; s.polyvSecret = "secret"
        s.channelOwnership.transport = { request in
            (Data(#"{"code":200,"status":"success","data":{"channelId":100,"userCategory":{"userId":"owner"}}}"#.utf8), HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        let first = try await s.createClassroom(" 00100 ",name:"编程教室")
        let second = try await s.createClassroom("100",name:"")
        XCTAssertEqual(first,"100"); XCTAssertEqual(second,"100")
        XCTAssertEqual(s.saved.rooms.count,1); XCTAssertEqual(s.classroomChannels,["100"])
        XCTAssertEqual(s.preparations("100").count, 1)
        XCTAssertEqual(s.preparations("100").first?.title, "新建课程")
        XCTAssertEqual(try s.file.read().rooms.first?.preparations?.count, 1)
        for invalid in ["abc", "１２３"] {
            do { _ = try await s.createClassroom(invalid,name:""); XCTFail("Invalid channel accepted") }
            catch { XCTAssertEqual(error.localizedDescription,"请输入有效频道号") }
        }
        let old=try JSONDecoder().decode(RoomConversation.self,from:Data("{\"channel\":\"1\",\"messages\":[],\"materials\":[],\"libraryIDs\":[]}".utf8))
        XCTAssertNil(old.preparations)
    }
    @MainActor func testNoPreparationAndRepeatedBroadcastsMakeSessionsInOneRoom() throws {
        let s=makeStore(); s.channel="100"
        s.ensureCourse(); let first=try XCTUnwrap(s.currentCourseID)
        s.adoptSession("session-a",started:Date())
        XCTAssertNil(s.currentCourse?.preparation)
        s.finishCourse(); s.ensureCourse(); s.adoptSession("session-b",started:Date())
        XCTAssertNotEqual(s.currentCourseID,first)
        XCTAssertEqual(s.saved.courses.count,2); XCTAssertEqual(s.classroomChannels,["100"])
        XCTAssertEqual(s.classroomLessons("100").count,2)
    }
    @MainActor func testPreparationConsumedOnlyAfterSessionAndSnapshotIsImmutable() throws {
        let s=makeStore(); let id=try plan(s); s.channel="100"; s.selectedPreparationID=id
        let publicLibrary=KnowledgeBase(name:"公共库",documents:[Document(name:"公共FAQ",text:"课程结束后可看回放。")])
        s.saved.libraries=[publicLibrary]; s.libraryIDs=[publicLibrary.id]
        s.ensureCourse()
        XCTAssertNil(s.preparations("100")[0].usedByCourseID)
        XCTAssertNil(s.currentCourse?.preparation)
        s.adoptSession("session-a",started:Date())
        let course=try XCTUnwrap(s.currentCourse)
        XCTAssertEqual(course.preparation?.id,id); XCTAssertEqual(course.preparation?.notes,"变量存储数据，函数封装操作。")
        XCTAssertEqual(s.preparations("100")[0].usedByCourseID,course.id)
        XCTAssertEqual(course.publicLibraryIDs,[publicLibrary.id]); XCTAssertEqual(s.classroomLessons("100").count,1)
        XCTAssertTrue(s.answerLibrary.documents.contains { $0.text.contains("变量可以赋值") })
        XCTAssertEqual(Set(s.answerLibrary.documents.map(\.id)).count,s.answerLibrary.documents.count)
        var used=s.preparations("100")[0]; used.notes="错误的覆盖内容"
        XCTAssertThrowsError(try s.savePreparation(used,channel:"100",confirm:true))
        let copy=try s.copyPreparation(used,channel:"100")
        XCTAssertNotEqual(copy,id); XCTAssertFalse(s.preparations("100").first { $0.id == copy }!.ready)
        XCTAssertEqual(try s.file.read().courses.first?.preparation?.notes,"变量存储数据，函数封装操作。")
        s.finishCourse(); s.ensureCourse(); s.adoptSession("session-b",started:Date())
        XCTAssertNil(s.currentCourse?.preparation)
    }
    @MainActor func testReconnectKeepsExistingPreparationAndDoesNotConsumeNewSelection() throws {
        let s=makeStore(); let first=try plan(s); s.channel="100"; s.selectedPreparationID=first
        s.ensureCourse(); s.adoptSession("session-a",started:Date()); let original=try XCTUnwrap(s.currentCourseID)
        // A dropped connection leaves the course unfinished; finishCourse means the instructor ended class.
        s.currentCourseID = nil
        let second=try plan(s,title:"下一节课"); s.selectedPreparationID=second; s.ensureCourse()
        XCTAssertNotEqual(s.currentCourseID,original)
        s.adoptSession("session-a",started:Date())
        XCTAssertEqual(s.currentCourseID,original)
        XCTAssertEqual(s.currentCourse?.preparation?.id,first)
        XCTAssertNil(s.preparations("100").first { $0.id == second }?.usedByCourseID)
        XCTAssertEqual(s.saved.courses.count,1)
        XCTAssertEqual(s.classroomLessons("100").count,2)
    }
    @MainActor func testWrongChannelNeverBindsButSelectedDraftBindsOnStart() throws {
        let s=makeStore(); let id=try plan(s,channel:"100")
        s.channel="200"; s.selectedPreparationID=id; s.ensureCourse(); s.adoptSession("other",started:Date())
        XCTAssertNil(s.currentCourse?.preparation); XCTAssertNil(s.preparations("100")[0].usedByCourseID)
        s.finishCourse(); s.channel="100"
        let draft=try s.createPreparation(channel:"100",title:"未确认")
        s.selectedPreparationID=draft; s.ensureCourse()
        XCTAssertNil(s.preparations("100").first { $0.id == draft }?.usedByCourseID)
        XCTAssertNil(s.preparations("100").first { $0.id == draft }?.confirmedAt)
        s.adoptSession("new",started:Date())
        XCTAssertEqual(s.currentCourse?.preparation?.id,draft)
        XCTAssertNotNil(s.currentCourse?.preparation?.confirmedAt)
        XCTAssertEqual(s.preparations("100").first { $0.id == draft }?.usedByCourseID,s.currentCourseID)
    }
    @MainActor func testLessonChatIsolationAndDraftTools() async throws {
        let s=makeStore(); let first=try plan(s), second=try plan(s,title:"第二节课")
        try s.commitRoom("100") { room,_ in room.messages.append(RoomMessage(role:"user",text:"第一课秘密约定",lessonID:first)) }
        s.roomAgentOverride = { input in
            let context=try XCTUnwrap(input as? [String:Any])
            XCTAssertEqual(context["current_lesson_id"] as? String,second.uuidString)
            XCTAssertFalse(String(describing:context).contains("秘密约定"))
            return ["message":"收到第二节课的要求"]
        }
        XCTAssertTrue(s.sendRoomMessage("准备第二节课",channel:"100",lessonID:second))
        await s.roomTasks["100"]?.value
        XCTAssertEqual(s.lessonConversation("100",lessonID:first).messages.count,1)
        XCTAssertEqual(s.lessonConversation("100",lessonID:second).messages.count,2)
        var sources:[RoomSource]=[]
        let matches=try s.performRoomTool("search_conversation",args:["query":"秘密约定"],channel:"100",sources:&sources,lessonID:second) as? [[String:Any]]
        XCTAssertTrue(try XCTUnwrap(matches).isEmpty)
        _ = try s.performRoomTool("update_preparation",args:["title":"第二节课","audience":"新学员","goals":"学习变量","notes":"先演示赋值，再练习。"],channel:"100",sources:&sources,lessonID:second)
        XCTAssertFalse(s.preparations("100").first { $0.id == second }!.ready)
        XCTAssertEqual(s.preparations("100").first { $0.id == first }!.notes,"变量存储数据，函数封装操作。")
    }
    @MainActor func testConfirmedKnowledgeSaveDeduplicatesAndStaleEditsFail() throws {
        let s=makeStore(); let id=try plan(s)
        let old=s.preparations("100")[0]
        s.savePreparationToKnowledge(id,channel:"100",libraryID:nil)
        s.savePreparationToKnowledge(id,channel:"100",libraryID:nil)
        XCTAssertEqual(s.saved.libraries.count,1); XCTAssertEqual(s.saved.libraries[0].documents.count,1)
        var edited=old; edited.notes="新的教学安排"
        try s.savePreparation(edited,channel:"100",confirm:false)
        XCTAssertThrowsError(try s.savePreparation(old,channel:"100",confirm:true))
        s.savePreparationToKnowledge(id,channel:"100",libraryID:nil)
        XCTAssertNotNil(s.roomErrors["100"]); XCTAssertEqual(s.saved.libraries.count,1)
    }
}

extension PreparationTests {
    @MainActor func testBindingFailureDoesNotConsumeAndCanRetry() throws {
        let s=makeStore(); let id=try plan(s); s.channel="100"; s.selectedPreparationID=id; s.ensureCourse()
        let courseID=try XCTUnwrap(s.currentCourseID)
        s.saved.courses[0].platformSessionID="session-a"
        try FileManager.default.removeItem(at:s.file.url)
        try FileManager.default.createDirectory(at:s.file.url,withIntermediateDirectories:true)
        s.bindPreparationToCurrentCourse()
        XCTAssertNil(s.currentCourse?.preparation)
        XCTAssertNil(s.preparations("100")[0].usedByCourseID)
        XCTAssertEqual(s.currentCourse?.candidatePreparationID,id)
        try FileManager.default.removeItem(at:s.file.url)
        s.bindPreparationToCurrentCourse()
        XCTAssertEqual(s.preparations("100")[0].usedByCourseID,courseID)
        XCTAssertEqual(try s.file.read().courses[0].preparation?.id,id)
    }
    @MainActor func testChangedDraftDuringConnectionIsNotSilentlyConsumed() throws {
        let s=makeStore(); let id=try plan(s); s.channel="100"; s.selectedPreparationID=id; s.ensureCourse()
        var updated=s.preparations("100")[0]; updated.notes="连接期间改了安排"
        try s.savePreparation(updated,channel:"100",confirm:true)
        s.adoptSession("session-a",started:Date())
        XCTAssertNil(s.currentCourse?.preparation); XCTAssertNil(s.currentCourse?.candidatePreparationID)
        XCTAssertNil(s.preparations("100")[0].usedByCourseID)
    }
    @MainActor func testDraftAndConversationMoveTogetherAndPublicLibraryChoicePersists() throws {
        let s=makeStore(); let id=try plan(s)
        let first=KnowledgeBase(name:"已选公共库",documents:[Document(name:"答案A",text:"只选择这个库")])
        let second=KnowledgeBase(name:"未选公共库",documents:[Document(name:"答案B",text:"不能混进本节课")])
        s.saved.libraries=[first,second]; s.libraryIDs=[first.id]
        try s.commitRoom("100") { room,_ in
            room.messages.append(RoomMessage(role:"user",text:"先讲变量，再讲函数",lessonID:id))
            room.materials.append(RoomMaterial(title:"练习",text:"变量作用？",kind:"题目",sources:[],lessonID:id))
        }
        s.channel="100"; s.selectedPreparationID=id; s.ensureCourse(); s.adoptSession("s1",started:Date())
        let courseID=try XCTUnwrap(s.currentCourseID)
        XCTAssertEqual(s.lessonConversation("100",lessonID:courseID).messages.count,1)
        XCTAssertEqual(s.lessonConversation("100",lessonID:courseID).materials.count,1)
        XCTAssertEqual(s.preparations("100")[0].usedByCourseID,courseID)
        s.libraryIDs=[second.id]
        s.adoptSession("s1",started:Date())
        XCTAssertEqual(s.libraryIDs,[first.id])
        XCTAssertFalse(s.answerLibrary.documents.contains { $0.text.contains("不能混进") })
        XCTAssertTrue(s.answerLibrary.documents.contains { $0.text.contains("只选择") })
        let restored=Store(preview:true,storageURL:s.file.url)
        XCTAssertEqual(restored.lessonConversation("100",lessonID:courseID).messages.count,1)
    }
    @MainActor func testReconnectSelectionDoesNotLeakIntoNextAutomaticSession() throws {
        let s=makeStore(); s.channel="100"; s.ensureCourse(); s.adoptSession("old",started:Date())
        let next=try plan(s); s.selectedPreparationID=next
        s.adoptSession("old",started:Date())
        XCTAssertNil(s.selectedPreparationID)
        s.adoptSession("new",started:Date())
        XCTAssertNil(s.currentCourse?.preparation)
        XCTAssertTrue(s.preparations("100")[0].ready)
    }
    @MainActor func testDocumentImportWithoutOpeningFilePanel() throws {
        let s=makeStore()
        let directory=s.file.url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let markdown=directory.appendingPathComponent("讲义.md")
        try "# 第一课\n变量保存数据。".write(to:markdown,atomically:true,encoding:.utf8)
        let document=try s.preparationDocument(at:markdown)
        XCTAssertEqual(document.name,"讲义.md"); XCTAssertTrue(document.text.contains("变量保存数据"))
        let empty=directory.appendingPathComponent("空.txt"); try " \n".write(to:empty,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try s.preparationDocument(at:empty))
        let huge=directory.appendingPathComponent("超长.txt"); try String(repeating:"字",count:100001).write(to:huge,atomically:true,encoding:.utf8)
        XCTAssertThrowsError(try s.preparationDocument(at:huge))
    }
    @MainActor func testKnowledgeSaveFailureAndChangedVersionStatus() throws {
        let s=makeStore(); let id=try plan(s)
        try FileManager.default.removeItem(at:s.file.url)
        try FileManager.default.createDirectory(at:s.file.url,withIntermediateDirectories:true)
        s.savePreparationToKnowledge(id,channel:"100",libraryID:nil)
        XCTAssertTrue(s.saved.libraries.isEmpty); XCTAssertFalse(s.preparationIsSaved(id,channel:"100"))
        try FileManager.default.removeItem(at:s.file.url)
        s.savePreparationToKnowledge(id,channel:"100",libraryID:nil)
        XCTAssertTrue(s.preparationIsSaved(id,channel:"100"))
        var value=s.preparations("100")[0]; value.notes="第二个版本"
        try s.savePreparation(value,channel:"100",confirm:true)
        XCTAssertFalse(s.preparationIsSaved(id,channel:"100"))
    }
}

extension PreparationTests {
    @MainActor func testRealModelPreparationSmoke() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_PREPARATION_LIVE"] == "1")
        let liveURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveAssistant/state.json")
        let original=try StateFile(url:liveURL).read()
        try XCTSkipIf(original.providers.isEmpty,"No configured model provider")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PreparationModelSmoke-" + UUID().uuidString)
        let file=StateFile(url:root.appendingPathComponent("state.json"))
        var state=SavedState(); state.providers=original.providers; state.defaultProviderID=original.defaultProviderID
        try file.write(state)
        let s=Store(preview:false,storageURL:file.url)
        s.saved.capabilities.set(.courseArchive,enabled:false)
        let id=try s.createPreparation(channel:"100",title:"变量与函数入门（合成测试）")
        var draft=try XCTUnwrap(s.preparations("100").first)
        draft.audience="零基础学员"; draft.goals="理解变量存储数据，函数封装可复用操作"; draft.notes="先演示变量赋值，再展示一个简单函数。"
        try s.savePreparation(draft,channel:"100",confirm:false)
        let before=s.preparations("100")[0].updatedAt
        let timeout=Task { @MainActor in
            do { try await Task.sleep(nanoseconds:120_000_000_000) } catch { return }
            s.stopRoomAgent("100")
        }
        defer { timeout.cancel(); s.stopRoomAgent("100"); s.cancelDataTasks() }
        XCTAssertTrue(s.sendRoomMessage("请先读取当前备课，再调用更新备课工具，将现有内容整理成三步教学大纲，控制在150字以内。只修改当前备课草稿，不创建其他资料。",channel:"100",lessonID:id))
        await s.roomTasks["100"]?.value
        let updated=try XCTUnwrap(s.preparations("100").first)
        XCTAssertGreaterThan(updated.updatedAt,before,"Model did not update the draft: \(s.roomErrors["100"] ?? "no reported error")")
        XCTAssertFalse(updated.notes.isEmpty)
        XCTAssertNil(updated.confirmedAt)
        XCTAssertEqual(s.lessonConversation("100",lessonID:id).messages.last?.role,"assistant",s.roomErrors["100"] ?? "No reported error")
        XCTAssertNil(s.roomErrors["100"])
        XCTAssertEqual(try file.read().rooms.first?.preparations?.first?.notes,updated.notes)
        if updated.updatedAt > before, s.lessonConversation("100",lessonID:id).messages.last?.role == "assistant" { print("REAL_PREPARATION_SMOKE: draft updated, unconfirmed, response and persistence verified") }
    }
}

extension PreparationTests {
    @MainActor func testRealModelCreatesDocumentAndAnswerCard() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_ASSETS_LIVE"] == "1")
        let liveURL=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveAssistant/state.json")
        let original=try StateFile(url:liveURL).read()
        try XCTSkipIf(original.providers.isEmpty)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("PreparationAssetSmoke-" + UUID().uuidString)
        let file=StateFile(url:root.appendingPathComponent("state.json"))
        var state=SavedState(); state.providers=original.providers; state.defaultProviderID=original.defaultProviderID; try file.write(state)
        let s=Store(preview:false,storageURL:file.url)
        let id=try s.createPreparation(channel:"100",title:"变量与函数入门（合成测试）")
        var draft=s.preparations("100")[0]; draft.audience="零基础学员"; draft.goals="理解变量与函数"
        draft.notes="变量用于保存数据，函数用于封装可复用的操作。先演示变量赋值，再展示一个简单函数。"
        try s.savePreparation(draft,channel:"100",confirm:false)
        let timeout=Task { @MainActor in do { try await Task.sleep(nanoseconds:180_000_000_000) } catch { return }; s.stopRoomAgent("100") }
        defer { timeout.cancel(); s.stopRoomAgent("100"); s.cancelDataTasks() }
        XCTAssertTrue(s.sendRoomMessage("先读取备课，然后生成两份本课资产：一份不超过80字的讲义文档，一道有两个选项的单选答题卡，包含正确答案、解析和依据。请调用相应创建工具保存，不要只在聊天里展示；不要同步平台或发送。",channel:"100",lessonID:id))
        await s.roomTasks["100"]?.value
        let assets=s.lessonConversation("100",lessonID:id).materials
        XCTAssertNil(s.roomErrors["100"])
        XCTAssertTrue(assets.contains { $0.exercise == nil && $0.stage == .preparation })
        let question=try XCTUnwrap(assets.first { $0.exercise != nil })
        XCTAssertEqual(question.stage,.preparation)
        XCTAssertNil(question.exercise?.platformID); XCTAssertNil(question.exercise?.sentAt)
        XCTAssertTrue(question.exercise!.isValid())
        XCTAssertEqual(try file.read().rooms[0].materials.count,assets.count)
        XCTAssertTrue(Set(s.lessonConversation("100",lessonID:id).messages.last?.assetIDs ?? []).isSuperset(of:Set(assets.map(\.id))))
        if assets.contains(where:{$0.exercise == nil}), assets.contains(where:{$0.exercise != nil}), s.roomErrors["100"] == nil {
            print("REAL_ASSETS_SMOKE: document + structured question persisted; platform ID and sentAt remain nil")
        }
    }
}
