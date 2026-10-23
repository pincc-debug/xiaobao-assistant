import XCTest
import AssistantCore
@testable import Assistant

final class HybridRetrievalTests: XCTestCase {
    func temporaryIndex() -> (RetrievalIndex, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (RetrievalIndex(url: folder.appendingPathComponent("index.json")), folder)
    }
    func testSemanticRecallWithoutSharedWordsAndRerank() async throws {
        let (index, folder) = temporaryIndex(); defer { try? FileManager.default.removeItem(at: folder) }
        var client = ModelsClient(preferences: Preferences(), jevKey: "", dashKey: "", provider: nil, providerKey: "")
        client.retrievalIndex = index
        client.embeddingOverride = { texts in texts.map { $0.contains("回放") || $0.contains("迟到") ? [1, 0] : [0, 1] } }
        client.rerankOverride = { _, passages in passages.indices.sorted { passages[$0].text.contains("回放") && !passages[$1].text.contains("回放") } }
        let library = KnowledgeBase(name: "课程", documents: [Document(name: "安排", text: "课后开放回放。"), Document(name: "内容", text: "模型支持图片生成。")])
        try await client.prepareKnowledge(library)
        let result = try await client.retrieve("迟到错过了怎么办", library: library, trace: nil)
        XCTAssertEqual(result.first?.title, "安排")
    }
    func testSemanticRecallReachesBeyondLexicalCandidateLimit() async throws {
        let (index, folder) = temporaryIndex(); defer { try? FileManager.default.removeItem(at: folder) }
        var client = ModelsClient(preferences: Preferences(), jevKey: "", dashKey: "", provider: nil, providerKey: "")
        client.retrievalIndex = index
        client.embeddingOverride = { texts in texts.map { $0.contains("回放") || $0.contains("迟到") ? [1, 0] : [0, 1] } }
        var documents = (0..<30).map { Document(name: "资料\($0)", text: "模型支持图片生成。") }
        documents.append(Document(name: "安排", text: "课后开放回放。"))
        let library = KnowledgeBase(name: "课", documents: documents)
        try await client.prepareKnowledge(library)
        let results = try await client.retrieve("迟到错过了怎么办", library: library, trace: nil)
        XCTAssertEqual(results.first?.title, "安排")
    }
    func testGroundedAnswerDoesNotRequireSecondModelVerification() async throws {
        var client = ModelsClient(preferences: Preferences(), jevKey: "", dashKey: "", provider: nil, providerKey: "")
        client.generateOverride = { _, input in
            let passages = (input as! [String:Any])["passages"] as! [[String:String]]
            return ["answerable":true, "answer":"回放七天。", "source_ids":[passages[0]["id"]!]]
        }
        client.jevOverride = { _, _ in
            XCTFail("自动答疑不应再次调用判断模型")
            throw AppError.message("unexpected verification")
        }
        let library = KnowledgeBase(name: "课", documents: [Document(name: "安排", text: "回放七天。")])
        let result = try await client.answer("回放保留多久", library: library)
        XCTAssertEqual(result?.0, "回放七天。")
        XCTAssertEqual(result?.1.first?.title, "安排")
    }
    func testCacheSurvivesRestartAndOnlyEmbedsChanges() async throws {
        let (index, folder) = temporaryIndex(); defer { try? FileManager.default.removeItem(at: folder) }
        var requests: [[String]] = []
        let fetch: ([String]) async throws -> [[Double]] = { texts in requests.append(texts); return texts.map { _ in [1, 0] } }
        _ = try await index.embed(["old", "unchanged"], using: fetch)
        let reopened = RetrievalIndex(url: folder.appendingPathComponent("index.json"))
        _ = try await reopened.embed(["new", "unchanged"], using: fetch)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1], ["new"])
        let contents = try String(contentsOf: folder.appendingPathComponent("index.json"))
        XCTAssertFalse(contents.contains("unchanged"))
    }
    func testFailureFallsBackAndDeletedSourceIsNotRecalled() async throws {
        let (index, folder) = temporaryIndex(); defer { try? FileManager.default.removeItem(at: folder) }
        var client = ModelsClient(preferences: Preferences(), jevKey: "", dashKey: "", provider: nil, providerKey: "")
        client.retrievalIndex = index
        client.embeddingOverride = { _ in throw AppError.message("offline") }
        client.rerankOverride = { _, _ in throw AppError.message("offline") }
        let library = KnowledgeBase(name: "课程", documents: [Document(name: "FAQ", text: "回放保留七天。")])
        let results = try await client.retrieve("回放多久", library: library, trace: nil)
        XCTAssertEqual(results.first?.text, "回放保留七天。")
        let empty = try await client.retrieve("回放多久", library: KnowledgeBase(name: "已清空"), trace: nil)
        XCTAssertTrue(empty.isEmpty)
    }
    func testLatestTranscriptIsIncludedWithoutLexicalHit() async throws {
        var client = ModelsClient(preferences: Preferences(), jevKey: "", dashKey: "", provider: nil, providerKey: "")
        client.generateOverride = { _, _ in [:] }
        let library = KnowledgeBase(name: "本场", documents: [Document(name: "本场课堂转写", text: "报名截止到明天中午。")])
        let result = try await client.retrieve("刚刚说的是什么", library: library, trace: nil)
        XCTAssertEqual(result.first?.text, "报名截止到明天中午。")
    }
    func testFAQPairsStayTogetherAndFusionDeduplicates() {
        let library = KnowledgeBase(name: "课", documents: [Document(name: "FAQ", text: "问：如何回看？\n答：课后开放回放。\n问：何时开始？\n答：周三上午。")])
        let chunks = Knowledge.chunks(in: library)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].text.contains("答：课后开放回放"))
        XCTAssertEqual(Knowledge.fuse([chunks, chunks], limit: 6).count, 2)
    }
    func testInvalidVectorsAreNotPersisted() async throws {
        let (index, folder) = temporaryIndex(); defer { try? FileManager.default.removeItem(at: folder) }
        do { _ = try await index.embed(["x"], using: { _ in [[Double.nan]] }); XCTFail("invalid vector accepted") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.json").path)) }
    }
}
