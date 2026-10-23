import XCTest
@testable import Assistant

final class SilentRecognitionTests: XCTestCase {
    @MainActor func testPartialCaptionsDoNotBecomeSavedTranscript() {
        let voice = VoiceSession()
        var partials: [String] = [], finals: [String] = []
        voice.onPartial = { partials.append($0) }
        voice.onFinal = { finals.append($0) }
        voice.applyTranscriptEvent(["type":"conversation.item.input_audio_transcription.text", "text":"正在讲解", "stash":"变量"])
        XCTAssertEqual(partials.last, "正在讲解变量")
        XCTAssertTrue(finals.isEmpty)
        voice.applyTranscriptEvent(["type":"conversation.item.input_audio_transcription.completed", "transcript":"正在讲解变量。"])
        XCTAssertEqual(finals, ["正在讲解变量。"])
    }
    @MainActor func testEmptyRecognitionCompletesWithoutFailure() {
        let voice = VoiceSession()
        var finished: String?
        voice.completion = { finished = $0 }
        voice.failure = { _ in XCTFail("silence must not be reported as an error") }
        voice.applyTranscriptEvent(["type":"conversation.item.input_audio_transcription.completed","transcript":"  \n"])
        voice.finishRecognition()
        XCTAssertEqual(finished, ""); XCTAssertFalse(voice.active); XCTAssertEqual(voice.phase, "")
    }
    @MainActor func testEmptyCommandDoesNotEraseDraftOrRunCommand() {
        let store = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        var pending = PendingMessage(title:"问题",question:"回放？")
        pending.draft = "已写好的答案"; store.messages = [pending]
        store.commandVoiceVisible = true
        store.voice.finishRecognition()
        XCTAssertEqual(store.messages[0].draft,"已写好的答案")
        XCTAssertTrue(store.error.isEmpty); XCTAssertFalse(store.commandVoiceVisible)
    }
    @MainActor func testActualRecognizedSpeechStillCompletes() {
        let voice = VoiceSession(); var result = ""
        voice.completion = { result = $0 }
        voice.applyTranscriptEvent(["type":"conversation.item.input_audio_transcription.completed","transcript":"发布公告"])
        voice.finishRecognition(); XCTAssertEqual(result,"发布公告")
    }
}
