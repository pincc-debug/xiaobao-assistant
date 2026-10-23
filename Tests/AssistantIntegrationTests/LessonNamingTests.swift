import XCTest
import AssistantCore
@testable import Assistant

final class LessonNamingTests: XCTestCase {
    @MainActor private func fixture(rounds: Int) throws -> (Store, UUID) {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        let id = try store.createPreparation(channel: "100", title: "新建课程")
        try store.commitRoom("100") { room, _ in
            for _ in 0..<rounds {
                room.messages.append(RoomMessage(role: "user", text: "讲解变量", lessonID: id))
                room.messages.append(RoomMessage(role: "assistant", text: "变量保存数据", lessonID: id))
            }
            // Other lessons and unfinished requests must not advance the threshold.
            room.messages.append(RoomMessage(role: "assistant", text: "其他课", lessonID: UUID()))
            room.messages.append(RoomMessage(role: "user", text: "继续", lessonID: id))
        }
        return (store, id)
    }

    @MainActor func testNamesOnlyAfterFiveCompletedExchangesAndPersistsOnce() async throws {
        let (store, id) = try fixture(rounds: 4)
        var calls = 0
        let generate: (Any) async throws -> [String: Any] = { input in
            calls += 1
            XCTAssertEqual((input as? [[String: String]])?.count, 10)
            return ["title": "变量入门"]
        }
        await store.namePreparationAfterConversation(channel: "100", lessonID: id, generate: generate)
        XCTAssertEqual(calls, 0)
        try store.commitRoom("100") { room, _ in
            room.messages.append(RoomMessage(role: "assistant", text: "继续学习变量", lessonID: id))
        }
        await store.namePreparationAfterConversation(channel: "100", lessonID: id, generate: generate)
        await store.namePreparationAfterConversation(channel: "100", lessonID: id, generate: generate)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.preparations("100").first?.title, "变量入门")
        XCTAssertEqual(try store.file.read().rooms.first(where: { $0.channel == "100" })?.preparations?.first?.title, "变量入门")
    }

    @MainActor func testManualRenameDuringGenerationWins() async throws {
        let (store, id) = try fixture(rounds: 5)
        await store.namePreparationAfterConversation(channel: "100", lessonID: id) { _ in
            var plan = store.preparations("100")[0]
            plan.title = "我自己的课程名"
            try store.savePreparation(plan, channel: "100", confirm: false)
            return ["title": "AI课程名"]
        }
        XCTAssertEqual(store.preparations("100")[0].title, "我自己的课程名")
    }

    @MainActor func testFailureKeepsDefaultAndConfirmedPreparationIsNotRenamed() async throws {
        let (store, id) = try fixture(rounds: 5)
        await store.namePreparationAfterConversation(channel: "100", lessonID: id) { _ in
            throw NSError(domain: "test", code: 1)
        }
        XCTAssertEqual(store.preparations("100")[0].title, "新建课程")
        XCTAssertNil(store.roomErrors["100"])
        try store.savePreparation(store.preparations("100")[0], channel: "100", confirm: true)
        await store.namePreparationAfterConversation(channel: "100", lessonID: id) { _ in
            XCTFail("Confirmed preparation should retain its title")
            return ["title": "不应覆盖"]
        }
        XCTAssertEqual(store.preparations("100")[0].title, "新建课程")
    }
}
