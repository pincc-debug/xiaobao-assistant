import XCTest
import AssistantCore
@testable import Assistant

final class RoomContextTests: XCTestCase {
    func testMoreThanTwentyMessagesStayVerbatim() throws {
        var room = RoomConversation(channel:"A")
        room.messages = (0..<150).map { RoomMessage(role:$0 % 2 == 0 ? "user" : "assistant", text:"第\($0)条讨论") }
        let context = RoomContext.build(room:room,results:[])
        let messages = try XCTUnwrap(context["messages"] as? [[String:Any]])
        XCTAssertEqual(messages.count,150)
        XCTAssertEqual(messages.first?["text"] as? String,"第0条讨论")
    }
    func testBudgetCurrentRequestAndRecall() throws {
        var room = RoomConversation(channel:"A")
        room.messages = [RoomMessage(role:"user",text:"之前约定：课程代号蓝鲸，练习只出三题。")]
            + (0..<90).map { RoomMessage(role:$0 % 2 == 0 ? "user" : "assistant",text:String(repeating:"其他课程讨论",count:200)) }
        let query = "蓝鲸课程之前约定出几道题？"
        room.messages.append(RoomMessage(role:"user",text:query))
        let results: [[String:Any]] = (0..<8).map { ["tool":"read_course","result":String(repeating:"历史资料",count:1200),"ordinal":$0] }
        let context = RoomContext.build(room:room,results:results)
        XCTAssertLessThanOrEqual(RoomContext.bytes(context),RoomContext.inputBudget)
        let messages = try XCTUnwrap(context["messages"] as? [[String:Any]])
        XCTAssertEqual(messages.last?["text"] as? String,query)
        XCTAssertGreaterThan(try XCTUnwrap(context["omitted_messages"] as? Int),0)
        let recalled = try XCTUnwrap(context["recalled_messages"] as? [[String:Any]])
        XCTAssertTrue(recalled.contains { ($0["text"] as? String)?.contains("只出三题") == true })
        XCTAssertEqual(room.messages.count,92)
    }
    func testLargestAllowedRequestAndToolResultFit() throws {
        var room = RoomConversation(channel:"A")
        let text = String(repeating:"中",count:12000)
        room.messages = [RoomMessage(role:"user",text:text)]
        let result: [[String:Any]] = [["tool":"read_course","result":String(repeating:"中",count:6000)]]
        let context = RoomContext.build(room:room,results:result)
        XCTAssertLessThanOrEqual(RoomContext.bytes(context),RoomContext.inputBudget)
        XCTAssertEqual((context["messages"] as? [[String:Any]])?.last?["text"] as? String,text)
        XCTAssertEqual((context["results"] as? [[String:Any]])?.count,1)
    }
    @MainActor func testOldConversationRetrievalIsChannelScopedAndNotFactEvidence() throws {
        let store = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let original = RoomMessage(role:"user",text:"蓝鲸课程只出三题。" + String(repeating:"课堂记录",count:2000))
        try store.commitRoom("A") { room,_ in room.messages = [original,RoomMessage(role:"user",text:"之前的约定？")] }
        try store.commitRoom("B") { room,_ in room.messages = [RoomMessage(role:"user",text:"蓝鲸保密记录"),RoomMessage(role:"user",text:"继续")] }
        var sources: [RoomSource] = []
        let result = try store.performRoomTool("search_conversation",args:["query":"蓝鲸"],channel:"A",sources:&sources) as? [[String:Any]]
        XCTAssertTrue(try XCTUnwrap(result?.first?["text"] as? String).contains("只出三题"))
        XCTAssertFalse(try XCTUnwrap(result?.first?["text"] as? String).contains("保密"))
        XCTAssertTrue(sources.isEmpty)
        let page = try store.performRoomTool("read_conversation",args:["message_id":original.id.uuidString,"offset":4000],channel:"A",sources:&sources) as? [String:Any]
        XCTAssertEqual(page?["next_offset"] as? Int,8000)
        XCTAssertThrowsError(try store.performRoomTool("read_conversation",args:["message_id":original.id.uuidString,"offset":0],channel:"B",sources:&sources))
        let restored = Store(preview:true,storageURL:store.file.url)
        XCTAssertEqual(restored.room("A").messages.first?.text,original.text)
        let browse = try restored.performRoomTool("list_conversation",args:["offset":0],channel:"A",sources:&sources) as? [String:Any]
        XCTAssertEqual((browse?["messages"] as? [[String:Any]])?.first?["id"] as? String,original.id.uuidString)
    }
}
