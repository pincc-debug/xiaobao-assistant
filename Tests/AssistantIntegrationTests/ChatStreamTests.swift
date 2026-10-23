import XCTest
import AssistantCore
@testable import Assistant

final class ChatStreamTests: XCTestCase {
    func testSplitUTF8CRLFAndMultilineSSE() throws {
        let data = ": heartbeat\r\nevent: message\r\ndata: {\"text\":\r\ndata: \"你好\"}\r\n\r\ndata: [DONE]\n\n"
        var decoder = SSEFrameDecoder(), frames: [String] = []
        for byte in data.utf8 { if let frame = try decoder.append(byte) { frames.append(frame) } }
        XCTAssertNil(try decoder.finish())
        XCTAssertEqual(frames, ["{\"text\":\n\"你好\"}", "[DONE]"])
    }
    func testCompatibleStreamAccumulatesOnlyVisibleText() throws {
        var stream = ChatStreamAccumulator()
        try stream.accept(#"{"choices":[{"index":0,"delta":{"reasoning_content":"private thought","content":"你好"}}]}"#, anthropic:false)
        XCTAssertEqual(stream.text, "你好"); XCTAssertThrowsError(try stream.decision())
        try stream.accept(#"{"choices":[{"delta":{"content":"，**欢迎**"},"finish_reason":"stop"}]}"#, anthropic:false)
        XCTAssertEqual(try stream.decision()["message"] as? String, "你好，**欢迎**")
    }
    func testSplitToolArgumentsNeverBecomeReply() throws {
        var stream = ChatStreamAccumulator()
        try stream.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"create_material","arguments":"{\"title\":"}}]}}]}"#, anthropic:false)
        XCTAssertEqual(stream.text, ""); XCTAssertThrowsError(try stream.decision())
        try stream.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"讲义\"}"}}]},"finish_reason":"tool_calls"}]}"#, anthropic:false)
        let choice = try stream.decision()
        XCTAssertEqual(choice["name"] as? String, "create_material")
        XCTAssertEqual((choice["arguments"] as? [String:Any])?["title"] as? String, "讲义")
    }
    func testToolPreambleIsProgressRatherThanFinalReply() throws {
        var stream = ChatStreamAccumulator()
        try stream.accept(#"{"choices":[{"delta":{"content":"我先查一下课程资料。","reasoning_content":"private"}}]}"#, anthropic: false)
        try stream.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"list_courses","arguments":"{\"offset\":0}"}}]},"finish_reason":"tool_calls"}]}"#, anthropic: false)
        let result = try stream.decision()
        XCTAssertEqual(result["progress"] as? String, "我先查一下课程资料。")
        XCTAssertNil(result["message"])
        XCTAssertFalse((result["progress"] as? String ?? "").contains("private"))
    }
    func testInterruptedTruncatedAndMultipleToolsAreRejected() throws {
        var stream = ChatStreamAccumulator()
        try stream.accept(#"{"choices":[{"delta":{"content":"partial"}}]}"#, anthropic:false)
        try stream.accept("[DONE]", anthropic:false)
        XCTAssertThrowsError(try stream.decision())
        XCTAssertThrowsError(try stream.accept(#"{"choices":[{"delta":{},"finish_reason":"length"}]}"#, anthropic:false))
        XCTAssertThrowsError(try stream.accept(#"{"choices":[{"delta":{"tool_calls":[{"index":0},{"index":1}]}}]}"#, anthropic:false))
    }
    func testAnthropicTextAndTools() throws {
        var stream = ChatStreamAccumulator()
        try stream.accept(##"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"# 大纲"}}"##, anthropic:true)
        try stream.accept(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#, anthropic:true)
        XCTAssertEqual(try stream.decision()["message"] as? String, "# 大纲")
        var tool = ChatStreamAccumulator()
        try tool.accept(#"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","name":"list_courses","input":{}}}"#,anthropic:true)
        try tool.accept(#"{"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,anthropic:true)
        XCTAssertEqual(try tool.decision()["name"] as? String,"list_courses")
    }
    func testMarkdownBlocksAndUnclosedCodeFence() {
        let blocks = ChatMarkdownBlock.parse("# 标题\n\n**加粗**和[链接](https://example.com)\n\n- 第一项\n2. 第二项\n> 引用\n\n| 项 | 值 |\n| --- | --- |\n| A | B |\n\n```swift\nlet x = 1")
        XCTAssertEqual(blocks.map(\.kind), [.heading(1), .paragraph, .list("•"), .list("2."), .quote, .table, .code])
        XCTAssertEqual(blocks.last?.text,"let x = 1")
        XCTAssertEqual(ChatMarkdownBlock.cells("| A | B |"),["A","B"])
    }
    func testRetiredLocalProviderMigrationPreservesAPIAndRooms() throws {
        let oldID = UUID(), apiID = UUID()
        var state = SavedState(); var p = ModelProvider(); p.id = apiID; p.model = "deepseek-v4.1-flash"; state.providers = [p]
        state.rooms = [RoomConversation(channel:"100")]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String:Any])
        var providers = json["providers"] as! [[String:Any]]
        providers.insert(["id":oldID.uuidString,"kind":"本机 Codex"],at:0)
        json["providers"] = providers; json["defaultProviderID"] = oldID.uuidString
        let restored = try JSONDecoder().decode(SavedState.self,from: JSONSerialization.data(withJSONObject:json))
        XCTAssertEqual(restored.providers.map(\.id),[apiID]); XCTAssertEqual(restored.defaultProviderID,apiID)
        XCTAssertEqual(restored.rooms.map(\.channel),["100"])
    }
    @MainActor func testRealAPIConversationStreamsTwoTurns() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_CHAT_STREAM_LIVE"] == "1")
        let live = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LiveAssistant/state.json")
        let original = try StateFile(url:live).read()
        let provider = try XCTUnwrap(original.providers.first { $0.id == original.defaultProviderID })
        let file = StateFile(url:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var state = SavedState(); state.providers = [provider]; state.defaultProviderID = provider.id; try file.write(state)
        let s = Store(preview:false,storageURL:file.url)
        let lesson = try s.createPreparation(channel:"100",title:"合成测试")
        defer { s.stopRoomAgent("100"); s.cancelDataTasks() }
        for input in ["你好。请简短介绍你能帮我做什么。", "我想教变量与函数，请用Markdown标题和列表列出三个教学要点，不创建资料。"] {
            XCTAssertTrue(s.sendRoomMessage(input,channel:"100",lessonID:lesson))
            let task = s.roomTasks["100"]
            var sawStreaming = false
            while s.roomRunIDs["100"] != nil {
                if !(s.roomStreamingText["100"] ?? "").isEmpty { sawStreaming = true }
                try await Task.sleep(nanoseconds:30_000_000)
            }
            await task?.value
            XCTAssertNil(s.roomErrors["100"])
            XCTAssertTrue(sawStreaming, "Must expose real deltas before completion")
            XCTAssertEqual(s.lessonConversation("100",lessonID:lesson).messages.last?.role,"assistant")
        }
        XCTAssertEqual(s.lessonConversation("100",lessonID:lesson).messages.count,4)
        print("LIVE_CHAT_STREAM: two turns persisted; deltas observed; model=" + provider.model)
    }
}
