import XCTest
@testable import Assistant

final class LiveStreamVoiceTests: XCTestCase {
    private let account = PolyvChannelOwnership.Account(appID: "app", userID: "owner", secret: "secret")
    func testPlaybackRequestIsSignedForCapturedChannel() async throws {
        let client = LiveStreamAddress { request in
            XCTAssertEqual(request.url?.path, "/live/v2/channels/100/get")
            var fields = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            let signature = fields.removeValue(forKey: "sign")
            XCTAssertEqual(fields["channelId"], "100")
            XCTAssertEqual(signature, ChatGateway.signature(fields, secret: "secret"))
            let data = Data(#"{"code":200,"data":{"channelId":100,"m3u8Url":"https://example.com/live.m3u8?auth_key=test"}} "#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let url = try await client.resolve(channel: "100", account: account)
        XCTAssertEqual(url.host, "example.com")
    }
    func testWrongChannelOrNonNetworkAddressIsRejected() async {
        for detail in [
            #"{"channelId":101,"m3u8Url":"https://example.com/live.m3u8"}"#,
            #"{"channelId":100,"m3u8Url":"file:///tmp/audio"}"#
        ] {
            let client = LiveStreamAddress { request in
                (Data("{\"code\":200,\"data\":\(detail)}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.resolve(channel: "100", account: account); XCTFail("Must reject invalid source") }
            catch {}
        }
    }
    @MainActor func testOfflineStreamWaitsAndCancelPreventsRestart() async throws {
        let session = LiveStreamVoiceSession()
        var requests = 0
        session.address = LiveStreamAddress { request in
            requests += 1
            if request.url?.host == "api.polyv.net" {
                return (Data(#"{"code":200,"data":{"channelId":100,"m3u8Url":"https://example.com/live.m3u8"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        await session.start(key: "unused", host: "unused.invalid", channel: "100", account: account)
        for _ in 0..<30 {
            if requests >= 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(session.phase, "等待直播音频")
        XCTAssertTrue(session.active)
        session.cancel()
        let count = requests
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(requests, count)
        XCTAssertFalse(session.active)
        XCTAssertEqual(session.phase, "")
    }
    @MainActor func testDecoderUsesNetworkAudioOnlyAndNoShell() {
        let url = URL(string: "https://example.com/live.m3u8?token=a&x=b")!
        let args = LiveStreamVoiceSession.arguments(url: url)
        XCTAssertTrue(args.contains(url.absoluteString))
        XCTAssertTrue(args.contains("0:a:0"))
        XCTAssertTrue(args.contains("pcm_s16le"))
        XCTAssertFalse(args.contains("avfoundation"))
        XCTAssertTrue(args.contains("-re"))
    }
    @MainActor func testRealExternalAudioRecognition() async throws {
        guard ProcessInfo.processInfo.environment["RUN_STREAM_ASR_SMOKE"] == "1" else {
            throw XCTSkip("Opt-in real ASR test")
        }
        let credentials = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/credentials.json")
        let values = try JSONSerialization.jsonObject(with: Data(contentsOf: credentials)) as! [String: String]
        let key = try XCTUnwrap(values["dashscope"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let audio = directory.appendingPathComponent("speech.aiff")
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", "Tingting", "-o", audio.path, "这是直播音频转写测试。我们正在测试课堂笔记。"]
        try say.run(); say.waitUntilExit()
        XCTAssertEqual(say.terminationStatus, 0)
        let decoder = Process(), pipe = Pipe()
        decoder.executableURL = try XCTUnwrap(LiveStreamVoiceSession.decoder)
        decoder.arguments = ["-v", "error", "-i", audio.path, "-ar", "16000", "-ac", "1", "-f", "s16le", "pipe:1"]
        decoder.standardOutput = pipe
        try decoder.run()
        let pcm = pipe.fileHandleForReading.readDataToEndOfFile()
        decoder.waitUntilExit()
        XCTAssertGreaterThan(pcm.count, 32000)
        let voice = VoiceSession()
        defer { voice.cancel() }
        var result = "", failure = false
        voice.onFinal = { result += $0 }
        voice.failure = { _ in failure = true }
        await voice.start(key: key, host: "dashscope.aliyuncs.com", externalAudio: true)
        for _ in 0..<150 {
            if voice.phase == "正在转写" || failure { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(failure)
        for offset in stride(from: 0, to: pcm.count, by: 6400) {
            try await voice.appendStreamPCM(pcm.subdata(in: offset..<min(offset + 6400, pcm.count)))
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        voice.stop()
        for _ in 0..<150 {
            if !voice.active { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(failure)
        XCTAssertTrue(result.contains("测试"), "Synthetic speech should produce a recognizable transcript")
    }
}
