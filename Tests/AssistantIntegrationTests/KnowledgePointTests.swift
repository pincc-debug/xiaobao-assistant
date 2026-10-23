import XCTest
import AssistantCore
@testable import Assistant

final class KnowledgePointTests: XCTestCase {
    func testParaphrasedPointRequiresExactEvidenceAndGrounding() async throws {
        let source = "函数就是把能反复使用的操作放在一起，后面直接调用就可以了。"
        let point = "函数封装可复用的操作，使用时直接调用。"
        var client = ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        client.generateOverride = { _,_ in ["point":point,"evidence":source] }
        client.jevOverride = { _,_ in ["supported":["choice":"yes","confidence":0.95]] }
        let result = try await client.extractKnowledgePoint(source,alreadySent:[])
        XCTAssertEqual(result?.text,point); XCTAssertEqual(result?.evidence,source)
        client.jevOverride = { _,_ in ["supported":["choice":"no","confidence":0.99]] }
        let rejected = try await client.extractKnowledgePoint(source,alreadySent:[])
        XCTAssertNil(rejected)
    }
    func testInventedEvidenceAndDuplicatesAreRejected() async throws {
        var client = ModelsClient(preferences:Preferences(),jevKey:"",dashKey:"",provider:nil,providerKey:"")
        let point = "函数封装可复用的操作，使用时直接调用。"
        client.generateOverride = { _,_ in ["point":point,"evidence":"这不是课堂中说过的原话。"] }
        client.jevOverride = { _,_ in XCTFail("invalid evidence must not reach verification"); return [:] }
        let invalid = try await client.extractKnowledgePoint("变量用于存储数据，函数用于封装操作。",alreadySent:[])
        XCTAssertNil(invalid)
        client.generateOverride = { _,_ in ["point":point,"evidence":point] }
        let duplicate = try await client.extractKnowledgePoint(point,alreadySent:[point])
        XCTAssertNil(duplicate)
    }
    @MainActor func testPublishedPointHasRequestedPrefixAndIsSaved() async throws {
        let store = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        store.ensureCourse(); store.saved.capabilities.set(.quoteCards,enabled:true)
        let source = "变量用于存储数据，函数用于封装可以重复使用的操作。"
        store.quoteBuffer = source; store.quoteGenerate = { _,_ in source }
        var sent = ""; store.quoteSend = { sent = $0 }
        _ = await store.quoteTick()
        XCTAssertEqual(sent,"【知识点】" + source)
        XCTAssertEqual(store.currentCourse?.knowledgePoints?.last?.text,source)
        XCTAssertEqual(store.currentCourse?.quotes?.last,source)
    }
}
