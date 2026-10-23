import XCTest
import AssistantCore
@testable import Assistant

final class LiveAnswerAudit: XCTestCase {
    @MainActor func testConfiguredKnowledgeAnswersWithoutChatSending() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_LIVE_ANSWER_AUDIT"] == "1")
        let state = try StateFile(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/state.json")).read()
        let provider = try XCTUnwrap(state.providers.first { $0.id == state.defaultProviderID })
        let client = ModelsClient(preferences: state.preferences, jevKey: Vault.read("jev"), dashKey: "", provider: provider, providerKey: Vault.read("provider." + provider.id.uuidString))
        let library = try XCTUnwrap(SavedState.merged(state.libraries.filter { state.selectedLibraryIDs?.contains($0.id) ?? true }))
        for question in ["视频说 Arena 文本榜是多少分？", "促销的时候每百万 token 输入、输出分别多少钱？", "视频里的代码迁移是什么语言迁移到什么语言？"] {
            let answer = try await client.answer(question, library: library, trace: { stage, data in print("ANSWER_AUDIT", stage, data) })
            print("ANSWER_AUDIT_RESULT", question, answer?.0 ?? "NO_ANSWER")
            XCTAssertNotNil(answer, question)
        }
        let unknown = try await client.answer("老师我们班专属交流群的邀请码是什么？", library: library)
        XCTAssertNil(unknown, "没有依据的班群邀请码仍须交主讲")
    }
}
