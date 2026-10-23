import XCTest
@testable import AssistantCore
final class CoreTests: XCTestCase {
    func testCapabilityGroupsAndDefaults() {
        var selection = CapabilitySelection()
        XCTAssertFalse(selection.isEnabled(.welcomeRecap), "auto-send features default off")
        for c in [AssistantCapability.voiceInput, .announcements, .materials] {
            selection.set(c, enabled: false); XCTAssertTrue(selection.isEnabled(c))
        }
        let rows = CapabilityGroup.allCases.flatMap(\.rows)
        XCTAssertEqual(rows, [.riskAlerts, .messageDigest, .knowledgeAnswers, .welcomeRecap, .quoteCards, .courseArchive])
        XCTAssertEqual(AssistantCapability.technicalAlerts.title, "直播异常提醒")
        // 智能答疑 is one switch: off stops question collection too.
        selection.set(.knowledgeAnswers, enabled: false)
        XCTAssertFalse(selection.isEnabled(.questionRadar))
        selection.set(.knowledgeAnswers, enabled: true)
        XCTAssertTrue(selection.isEnabled(.questionRadar))
        XCTAssertEqual(AssistantCapability.technicalAlerts.rawValue, "technicalAlerts")
        XCTAssertTrue(HighFrequency.crossed(from: 2, to: 3))
        XCTAssertFalse(HighFrequency.crossed(from: 3, to: 4))
    }
    func testLibrariesNeverCrossRetrieve() {
        let a = KnowledgeBase(name: "A", documents: [Document(name: "FAQ", text: "回放会在课程结束后24小时上线")])
        let b = KnowledgeBase(name: "B", documents: [Document(name: "FAQ", text: "下载课件需要点击资料区")])
        XCTAssertFalse(Knowledge.retrieve("回放", in: a).isEmpty)
        XCTAssertTrue(Knowledge.retrieve("回放", in: b).isEmpty)
    }
    func testRejectsInventedSourcesAndNumbers() {
        let library = KnowledgeBase(name: "A", documents: [Document(name: "FAQ", text: "回放会在24小时上线")])
        let p = Knowledge.retrieve("回放", in: library)
        XCTAssertNotNil(Knowledge.validatedAnswer(["answerable": true, "answer": "24小时上线", "source_ids": [p[0].id]], passages: p))
        XCTAssertNil(Knowledge.validatedAnswer(["answerable": true, "answer": "48小时上线", "source_ids": [p[0].id]], passages: p))
        XCTAssertNil(Knowledge.validatedAnswer(["answerable": true, "answer": "24小时上线", "source_ids": ["invented"]], passages: p))
        XCTAssertNil(Knowledge.validatedAnswer(["answerable": true, "answer": " ", "source_ids": [p[0].id]], passages: p))
    }
    func testLowConfidenceDoesNotInventQuestionOrPunish() {
        XCTAssertEqual(Decision.category(["category": ["choice": "blocked", "confidence": 0.2]])?.0, "uncertain")
        XCTAssertEqual(Decision.category(["category": ["choice": "chat", "confidence": 0.2]])?.0, "chat")
        XCTAssertNil(Decision.category(["category": ["choice": "executeShell", "confidence": 1.0]]))
    }
    func testPersistenceAndCorruptDataPreservation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let file = StateFile(url: url); var state = SavedState()
        state.libraries = [KnowledgeBase(name: "课程甲"), KnowledgeBase(name: "课程乙")]; state.preferences.pet = "male"
        try file.write(state); XCTAssertEqual(try file.read().libraries.count, 2); XCTAssertEqual(try file.read().preferences.pet, "male")
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try file.read()); XCTAssertEqual(try String(contentsOf: url), "broken")
    }
}

extension CoreTests {
    func testProviderEndpointsAndTransportBoundaries() throws {
        var provider = ModelProvider()
        provider.baseURL = "https://example.com/api/v1/"
        XCTAssertEqual(try provider.endpoint("chat/completions").absoluteString, "https://example.com/api/v1/chat/completions")
        provider.baseURL = "http://127.0.0.1:11434/v1"
        XCTAssertEqual(try provider.endpoint("models").host, "127.0.0.1")
        provider.baseURL = "http://remote.example/v1"
        XCTAssertThrowsError(try provider.endpoint("models"))
        provider.baseURL = "https://user:secret@example.com/v1"
        XCTAssertThrowsError(try provider.endpoint("models"))
    }
    func testLegacyStateMigrationAndCourseRoundTrip() throws {
        let legacy = Data("{\"libraries\":[]}".utf8)
        var state = try JSONDecoder().decode(SavedState.self, from: legacy)
        XCTAssertFalse(state.speech.autoRecord)
        XCTAssertTrue(state.providers.isEmpty)
        var course = CourseSession(title: "课程测试", channel: "123")
        course.transcript = "学习需要实践。"
        course.answers = [CourseAnswer(question: "如何学习？", answer: "通过实践。")]
        course.cards = [QuoteCard(title: "实践", quote: "学习需要实践。", path: "/tmp/card.png")]
        state.courses = [course]
        let decoded = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.courses.first?.transcript, "学习需要实践。")
        XCTAssertEqual(decoded.courses.first?.cards.first?.quote, "学习需要实践。")
    }
}

extension CoreTests {
    func testCapabilityDependenciesAndPersistence() throws {
        var selection = CapabilitySelection()
        selection.set(.courseArchive, enabled: false)
        XCTAssertFalse(selection.isEnabled(.courseArchive))
        XCTAssertTrue(selection.isEnabled(.transcription), "实时转写 is always on")
        XCTAssertFalse(selection.isEnabled(.quoteCards))
        XCTAssertTrue(selection.isEnabled(.knowledgeAnswers))
        selection.set(.quoteCards, enabled: true)
        XCTAssertFalse(selection.isEnabled(.courseArchive))
        XCTAssertTrue(selection.isEnabled(.transcription))
        XCTAssertTrue(selection.isEnabled(.quoteCards))
        selection.set(.questionRadar, enabled: false)
        XCTAssertFalse(selection.isEnabled(.knowledgeAnswers))
        let restored = try JSONDecoder().decode(CapabilitySelection.self, from: JSONEncoder().encode(selection))
        XCTAssertFalse(restored.isEnabled(.knowledgeAnswers))
        XCTAssertTrue(restored.isEnabled(.quoteCards))
        let legacy = try JSONDecoder().decode(SavedState.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.capabilities.isEnabled(.questionRadar))
    }
    func testLibrarySelectionMigratesAndMerges() throws {
        let a = KnowledgeBase(name: "A", documents: [Document(name: "a", text: "x")]), b = KnowledgeBase(name: "B", documents: [Document(name: "b", text: "y")])
        let legacy = "{\"libraryID\":\"\(a.id.uuidString)\"}".data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(SavedState.self, from: legacy).selectedLibraryIDs, [a.id])
        var state = SavedState(); state.libraries = [a, b]; state.selectedLibraryIDs = [a.id, b.id]
        let back = try JSONDecoder().decode(SavedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.selectedLibraryIDs, [a.id, b.id]); XCTAssertEqual(back.libraries.count, 2)
        XCTAssertEqual(SavedState.merged([a, b])?.documents.map(\.id), a.documents.map(\.id) + b.documents.map(\.id))
        XCTAssertNil(SavedState.merged([]))
    }
}

final class SourceCaptureTests: XCTestCase {
    func testSourceLabelsFromRetrievalHits() {
        let doc = UUID()
        let hits = [
            Passage(id: "a_0", documentID: doc, title: "Python 入门讲义", text: "变量用于存储数据。", sourceKind: nil, courseID: nil, recordedAt: nil),
            Passage(id: "a_1", documentID: doc, title: "Python 入门讲义", text: "函数封装操作。", sourceKind: nil, courseID: nil, recordedAt: nil),
            Passage(id: "f_0", documentID: UUID(), title: "常见问题", text: "问：回放在哪里？\n答：课程主页。", sourceKind: nil, courseID: nil, recordedAt: nil)
        ]
        let labels = Knowledge.sourceLabels(hits)
        XCTAssertEqual(labels, ["《Python 入门讲义》", "FAQ · 回放在哪里？"])
        XCTAssertEqual(Knowledge.sourceLine(labels), "依据：《Python 入门讲义》、FAQ · 回放在哪里？")
        XCTAssertNil(Knowledge.sourceLine([]))
        var record = OperationRecord(question: "q", answer: "a")
        record.sources = labels
        let data = try! JSONEncoder().encode(record)
        XCTAssertEqual(try! JSONDecoder().decode(OperationRecord.self, from: data).sources, labels)
        // Old records without the key still decode.
        var old = try! JSONSerialization.jsonObject(with: data) as! [String: Any]; old["sources"] = nil
        XCTAssertNil(try! JSONDecoder().decode(OperationRecord.self, from: JSONSerialization.data(withJSONObject: old)).sources)
    }
}
