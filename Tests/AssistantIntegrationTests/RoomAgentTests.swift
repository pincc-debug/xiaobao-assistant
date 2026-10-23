import XCTest
import AssistantCore
@testable import Assistant

final class RoomAgentTests: XCTestCase {
    @MainActor private func makeStore() -> Store {
        Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
    }
    @MainActor func testLinkedKnowledgeReachesFirstTurnWithEmptyPreparation() async throws {
        let store = makeStore()
        let id = try store.createPreparation(channel: "A", title: "教学设计")
        let library = KnowledgeBase(name: "小学数学教学设计", documents: [Document(name: "课程知识", text: "教学过程五环节是导入、新课讲授、巩固练习、课堂小结、作业布置。")])
        let excluded = KnowledgeBase(name: "其他教室资料", documents: [Document(name: "保密", text: "其他教室的内容不能带入")])
        store.saved.libraries = [library, excluded]
        store.setRoomLibraries([library.id], channel: "A")
        XCTAssertTrue(try XCTUnwrap(store.preparationForLesson(id, channel: "A")).libraryIDs.isEmpty)
        store.roomAgentOverride = { input in
            let payload = try XCTUnwrap(input as? [String: Any])
            let course = try XCTUnwrap(payload["current_course"] as? [String: Any])
            let knowledge = try XCTUnwrap(course["linked_knowledge"] as? [String: Any])
            XCTAssertEqual(knowledge["document_count"] as? Int, 1)
            let passages = try XCTUnwrap(knowledge["passages"] as? [[String: String]])
            XCTAssertTrue(passages.contains { $0["text"]?.contains("五环节") == true })
            XCTAssertFalse(String(describing: payload).contains("其他教室的内容不能带入"))
            XCTAssertLessThanOrEqual(RoomContext.bytes(payload), RoomContext.inputBudget)
            return ["message": "五环节包括导入、新课讲授、巩固练习、课堂小结、作业布置。"]
        }
        XCTAssertTrue(store.sendRoomMessage("请根据上传资料概括教学过程五环节", channel: "A", lessonID: id))
        await store.roomTasks["A"]?.value
        let answer = try XCTUnwrap(store.lessonConversation("A", lessonID: id).messages.last)
        XCTAssertEqual(answer.sources.first?.title, "课程知识")
        XCTAssertTrue(answer.sources.first?.text.contains("五环节") == true)
    }
    @MainActor func testReadPreparationIncludesRoomLibrariesAndDeduplicatesDocuments() throws {
        let store = makeStore()
        let id = try store.createPreparation(channel: "A", title: "教学设计")
        let document = Document(name: "课程知识", text: "教学目标围绕学生的知识、能力和情感体验展开。")
        let library = KnowledgeBase(name: "数学", documents: [document])
        store.saved.libraries = [library]
        store.setRoomLibraries([library.id], channel: "A")
        var sources: [RoomSource] = []
        _ = try store.performRoomTool("read_preparation", args: ["offset": 0], channel: "A", sources: &sources, lessonID: id)
        XCTAssertTrue(try XCTUnwrap(sources.first?.text).contains(document.text))
        var plan = try XCTUnwrap(store.preparationForLesson(id, channel: "A"))
        plan.documents = [document]
        try store.savePreparation(plan, channel: "A", confirm: false)
        sources = []
        _ = try store.performRoomTool("read_preparation", args: ["offset": 0], channel: "A", sources: &sources, lessonID: id)
        let text = try XCTUnwrap(sources.first?.text)
        XCTAssertEqual(text.components(separatedBy: document.text).count - 1, 1)
        XCTAssertTrue(text.contains("不等于已确认的本课安排"))
    }
    @MainActor func testKnowledgeInventoryRemainsVisibleWithoutMatchAndRespectsBudget() throws {
        let store = makeStore()
        let library = KnowledgeBase(name: "教学设计", documents: (0..<30).map { Document(name: "资料\($0)", text: String(repeating: "数学教学设计知识。", count: 200)) })
        store.saved.libraries = [library]
        store.setRoomLibraries([library.id], channel: "A")
        var sources: [RoomSource] = []
        let noMatch = store.roomKnowledgeContext(channel: "A", lessonID: nil, query: "zzzz", sources: &sources)
        XCTAssertEqual(noMatch["document_count"] as? Int, 30)
        XCTAssertEqual(noMatch["documents_truncated"] as? Bool, true)
        XCTAssertFalse((noMatch["documents"] as? [[String: Any]])?.isEmpty ?? true)
        XCTAssertTrue(sources.isEmpty)
        let matched = store.roomKnowledgeContext(channel: "A", lessonID: nil, query: "数学教学设计", sources: &sources)
        XCTAssertLessThanOrEqual(RoomContext.bytes(matched), 8000)
        XCTAssertEqual(sources.count, (matched["passages"] as? [[String: String]])?.count)
        sources = []
        let compact = store.roomKnowledgeContext(channel: "A", lessonID: nil, query: "数学教学设计", sources: &sources, byteBudget: 512)
        XCTAssertLessThanOrEqual(RoomContext.bytes(compact), 512)
        XCTAssertEqual(compact["document_count"] as? Int, 30)
        XCTAssertTrue(sources.isEmpty)
    }
    @MainActor func testRealModelUsesLinkedLibraryWithEmptyPreparation() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["XB_ROOM_KNOWLEDGE_LIVE"] == "1", "Opt-in configured knowledge test")
        let liveURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveAssistant/state.json")
        let original = try StateFile(url: liveURL).read()
        let library = try XCTUnwrap(original.libraries.first { $0.name == environment["XB_ROOM_KNOWLEDGE_LIBRARY"] })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RoomKnowledgeSmoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = StateFile(url: root.appendingPathComponent("state.json"))
        var state = SavedState()
        state.providers = original.providers; state.defaultProviderID = original.defaultProviderID
        state.libraries = [library]
        try file.write(state)
        let store = Store(preview: false, storageURL: file.url)
        let id = try store.createPreparation(channel: "local-knowledge-test", title: "知识库读取验证")
        store.setRoomLibraries([library.id], channel: "local-knowledge-test")
        let timeout = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
            store.stopRoomAgent("local-knowledge-test")
        }
        defer { timeout.cancel(); store.stopRoomAgent("local-knowledge-test"); store.cancelDataTasks() }
        XCTAssertTrue(store.sendRoomMessage("这节课面向小学教资备考者。请仅依据上传资料，概括三问、目标写法和五环节。", channel: "local-knowledge-test", lessonID: id))
        await store.roomTasks["local-knowledge-test"]?.value
        XCTAssertNil(store.roomErrors["local-knowledge-test"])
        let answer = try XCTUnwrap(store.lessonConversation("local-knowledge-test", lessonID: id).messages.last)
        XCTAssertEqual(answer.role, "assistant")
        XCTAssertTrue(answer.sources.contains { $0.text.contains("教学设计三问") || $0.text.contains("教学过程五环节") })
        XCTAssertTrue(answer.text.contains("导入"), answer.text)
        XCTAssertTrue(answer.text.contains("作业"), answer.text)
        print("ROOM_KNOWLEDGE_LIVE_ANSWER:", answer.text)
    }
    @MainActor func testReviewReceivesSpeechEvenWithNoChatOrAnalytics() async throws {
        let store = makeStore()
        var course = CourseSession(title: "本课", channel: "A")
        course.transcript = "先回顾上节课，再讲大模型逐字预测并生成回答。"
        var other = CourseSession(title: "其他频道", channel: "B")
        other.transcript = "其他频道秘密"
        store.saved.courses = [course, other]
        store.roomAgentOverride = { input in
            let payload = try XCTUnwrap(input as? [String: Any])
            let context = try XCTUnwrap(payload["current_course"] as? [String: Any])
            XCTAssertEqual(context["id"] as? String, course.id.uuidString)
            let sections = try XCTUnwrap(context["sections"] as? [[String: Any]])
            XCTAssertEqual(sections.first?["text"] as? String, course.transcript)
            XCTAssertEqual(sections.count, 6)
            XCTAssertFalse(String(describing: context).contains(other.transcript))
            XCTAssertLessThanOrEqual(RoomContext.bytes(input), RoomContext.inputBudget)
            return ["message": "口播有先回顾再讲解的结构。"]
        }
        XCTAssertTrue(store.sendRoomMessage("这节课讲得怎么样", channel: "A", lessonID: course.id))
        await store.roomTasks["A"]?.value
        XCTAssertTrue(store.lessonConversation("A", lessonID: course.id).messages.last?.sources.contains(where: { $0.text == course.transcript }) == true)
        course.transcript = String(repeating: "很长的口播", count: 2000)
        store.saved.courses = [course]
        var sources: [RoomSource] = []
        let context = store.reviewCourseContext(channel: "A", lessonID: course.id, sources: &sources)
        let first = (context["sections"] as? [[String: Any]])?.first
        XCTAssertEqual(first?["truncated"] as? Bool, true)
        XCTAssertEqual((first?["read_arguments"] as? [String: Any])?["offset"] as? Int, 3000)
    }

    @MainActor func testProgressPersistsSeparatelyFromFinalAnswerAndPrompt() async throws {
        let store = makeStore()
        var turn = 0
        store.roomAgentOverride = { _ in
            turn += 1
            if turn == 1 { return ["name": "list_courses", "arguments": ["offset": 0], "progress": "先查看课程记录。"] }
            return ["message": "目前还没有历史课程。"]
        }
        XCTAssertTrue(store.sendRoomMessage("查一下课程", channel: "100"))
        await store.roomTasks["100"]?.value
        let messages = store.room("100").messages
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.last?.text, "目前还没有历史课程。")
        let process = try XCTUnwrap(messages.first?.thinking)
        XCTAssertEqual(process.steps.first?.detail, "先查看课程记录。")
        XCTAssertNotNil(process.finished)
        XCTAssertEqual(process.status, "已完成")
        XCTAssertTrue(process.preview.isEmpty)
        XCTAssertNil(store.roomStreamingText["100"])
        let data = try JSONEncoder().encode(store.saved)
        let saved = try JSONDecoder().decode(SavedState.self, from: data)
        XCTAssertEqual(saved.rooms.first?.messages.first?.thinking?.id, process.id)
        XCTAssertNil(RoomContext.message(messages[0])["thinking"])
    }
    @MainActor func testStopKeepsProcessButNeverPromotesPartialText() async throws {
        let store = makeStore()
        store.roomAgentOverride = { _ in
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return ["message": "不应出现"]
        }
        XCTAssertTrue(store.sendRoomMessage("准备课程", channel: "100"))
        let task = store.roomTasks["100"]
        store.roomThinking["100"]?.preview = "这是一段尚未完成的内容"
        store.roomStreamingText["100"] = "这是一段尚未完成的内容"
        store.stopRoomAgent("100")
        await task?.value
        XCTAssertEqual(store.room("100").messages.count, 1)
        XCTAssertEqual(store.room("100").messages.first?.thinking?.status, "已停止")
        XCTAssertEqual(store.room("100").messages.first?.thinking?.steps.last?.detail, "这是一段尚未完成的内容")
        XCTAssertNil(store.roomStreamingText["100"])
        XCTAssertNil(store.roomStreamIDs["100"])
    }
    @MainActor func testLegacyStateAndNavigationMigration() throws {
        let state = try JSONDecoder().decode(SavedState.self, from: Data("{}".utf8))
        XCTAssertTrue(state.rooms.isEmpty)
        XCTAssertEqual(Store.restoredSettingsPage("课程回顾"), "教室")
        XCTAssertEqual(Store.restoredSettingsPage("课程沉淀"), "教室")
    }
    @MainActor func testToolScopePagingAndInvalidSources() throws {
        let store = makeStore()
        var a = CourseSession(title: "函数", channel: "A"); a.transcript = String(repeating: "函数封装操作。", count: 1200)
        var b = CourseSession(title: "其他教室", channel: "B"); b.transcript = "不能泄露的频道内容"
        store.saved.courses = [a,b]
        var sources: [RoomSource] = []
        XCTAssertThrowsError(try store.performRoomTool("read_course", args:["course_id": b.id.uuidString, "offset":0], channel:"A", sources:&sources))
        XCTAssertThrowsError(try store.performRoomTool("send_chat_message", args:[:], channel:"A", sources:&sources))
        let first = try XCTUnwrap(store.performRoomTool("read_course", args:["course_id":a.id.uuidString,"offset":0], channel:"A", sources:&sources) as? [String:Any])
        XCTAssertEqual(first["next_offset"] as? Int,6000)
        XCTAssertEqual(sources.count,1)
        XCTAssertThrowsError(try store.performRoomTool("create_material", args:["title":"复盘","text":"内容","kind":"资料","source_ids":["invented"]], channel:"A", sources:&sources))
        let restricted = KnowledgeBase(name:"B资料", documents:[Document(name:"保密", text:"保密内容")]); store.saved.libraries = [restricted]
        let result = try store.performRoomTool("search_knowledge", args:["query":"保密"], channel:"A", sources:&sources) as? [[String:String]]
        XCTAssertEqual(result?.count,0)
    }
    @MainActor func testFullAgentLoopPersistenceSaveAndRetrieve() async throws {
        let store = makeStore()
        var course = CourseSession(title:"函数入门", channel:"A"); course.transcript = "函数封装可复用的操作。"
        store.saved.courses = [course]
        var turns = 0
        store.roomAgentOverride = { input in
            turns += 1
            switch turns {
            case 1: return ["name":"list_courses","arguments":[:]]
            case 2: return ["name":"read_course","arguments":["course_id":course.id.uuidString,"offset":0]]
            case 3: return ["name":"create_material","arguments":["title":"函数复盘","kind":"资料","text":"函数封装可复用操作。建议补充练习。","source_ids":["\(course.id):0"]]]
            default: return ["message":"复盘已生成，可以存入知识库。"]
            }
        }
        XCTAssertTrue(store.sendRoomMessage("复盘这节课", channel:"A"))
        await store.roomTasks["A"]?.value
        XCTAssertEqual(turns,4)
        XCTAssertEqual(store.room("A").messages.count,2)
        let draft = try XCTUnwrap(store.room("A").materials.first)
        XCTAssertFalse(store.roomMaterialSaved(draft))
        store.saveRoomMaterial(draft.id, channel:"A", libraryID:nil)
        store.saveRoomMaterial(draft.id, channel:"A", libraryID:nil)
        let read = try store.file.read()
        XCTAssertEqual(read.libraries.count,1)
        XCTAssertEqual(read.libraries[0].documents.count,1)
        XCTAssertEqual(read.libraries[0].documents[0].sourceKind,"复盘生成文档")
        XCTAssertEqual(read.rooms[0].messages.count,2)
        XCTAssertTrue(read.libraries[0].documents[0].text.contains(course.transcript))
        var sources: [RoomSource] = []
        let result = try store.performRoomTool("search_knowledge", args:["query":"函数复盘"], channel:"A", sources:&sources) as? [[String:String]]
        XCTAssertFalse(try XCTUnwrap(result).isEmpty)
        XCTAssertTrue(store.room("B").messages.isEmpty)
    }
    @MainActor func testSaveFailureDoesNotCommitAndCanRetry() throws {
        let store = makeStore()
        let source = RoomSource(id:"source",title:"原文",text:"函数")
        let material = RoomMaterial(title:"资料",text:"正文",kind:"资料",sources:[source])
        try store.commitRoom("A") { room,_ in room.materials.append(material) }
        try FileManager.default.removeItem(at:store.file.url)
        try FileManager.default.createDirectory(at:store.file.url,withIntermediateDirectories:true)
        store.saveRoomMaterial(material.id,channel:"A",libraryID:nil)
        XCTAssertNotNil(store.roomErrors["A"])
        XCTAssertTrue(store.saved.libraries.isEmpty)
        XCTAssertNil(store.room("A").materials[0].documentID)
        XCTAssertFalse(store.sendRoomMessage("保留输入",channel:"A"))
        XCTAssertTrue(store.room("A").messages.isEmpty)
        try FileManager.default.removeItem(at:store.file.url)
        store.saveRoomMaterial(material.id,channel:"A",libraryID:nil)
        XCTAssertTrue(store.roomMaterialSaved(store.room("A").materials[0]))
    }
    @MainActor func testCancellationRejectsLateResponse() async throws {
        let store = makeStore()
        var resume: CheckedContinuation<[String:Any], Never>?
        store.roomAgentOverride = { _ in await withCheckedContinuation { resume = $0 } }
        XCTAssertTrue(store.sendRoomMessage("帮我复盘",channel:"A"))
        let task = store.roomTasks["A"]
        for _ in 0..<100 { if resume != nil { break }; await Task.yield() }
        XCTAssertNotNil(resume)
        store.stopRoomAgent("A")
        resume?.resume(returning:["message":"过期回答"])
        await task?.value
        XCTAssertEqual(store.room("A").messages.count,1)
        XCTAssertNil(store.roomProgress["A"])
    }
}
