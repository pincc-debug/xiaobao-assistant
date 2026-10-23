import Foundation
import AVFoundation

@MainActor final class VoiceSession: ObservableObject {
    @Published var phase = "" { didSet { onDiagnostic?("phase", ["value": phase]) } }
    var onDiagnostic: ((String, [String:Any]) -> Void)?
    @Published var transcript = ""
    @Published private(set) var caption = ""
    @Published private(set) var captionTime = Date.distantPast
    @Published var active = false
    var onFinal: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var completion: ((String) -> Void)?
    var failure: ((String) -> Void)?
    private var engine: AVAudioEngine?
    private var ws: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var finals: [String] = []
    private var partial = ""
    private var finishing = false
    private var sending = false
    private var audioQueue: [Data] = []
    private var externalAudio = false
    private var externalSignal = false
    func start(key: String, host: String, model: String = "qwen3-asr-flash-realtime", externalAudio: Bool = false) async {
        guard !active else { return }
        guard !key.isEmpty else { failure?("请先填写语音转写 API Key"); return }
        let generation = UUID(); self.generation = generation
        active = true; phase = "连接中"; transcript = ""; finals = []; partial = ""; finishing = false
        caption = ""; captionTime = .distantPast
        self.externalAudio = externalAudio; externalSignal = false
        let allowed = externalAudio ? true : await AVCaptureDevice.requestAccess(for: .audio)
        guard self.generation == generation else { return }
        guard allowed else { fail("请在系统设置中允许麦克风访问"); return }
        var components = URLComponents(string: "wss://\(host)/api-ws/v1/realtime")!
        components.queryItems = [URLQueryItem(name: "model", value: model)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.timeoutInterval = 15
        let ws = URLSession.shared.webSocketTask(with: request); self.ws = ws; ws.resume()
        reader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    guard let self, self.generation == generation else { return }
                    let data: Data
                    switch message { case .string(let text): data = Data(text.utf8); case .data(let value): data = value; @unknown default: continue }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { continue }
                    switch type {
                    case "session.created":
                        try await self.emit("session.update", ["session": ["input_audio_format": "pcm", "sample_rate": 16000, "input_audio_transcription": ["language": "zh"], "turn_detection": ["type": "server_vad", "threshold": 0.2, "silence_duration_ms": 500]]])
                    case "session.updated":
                        self.timeout?.cancel()
                        if !self.externalAudio { try self.capture() }
                        self.phase = self.externalAudio ? "正在转写" : "正在录音"
                    case "conversation.item.input_audio_transcription.text", "conversation.item.input_audio_transcription.delta", "conversation.item.input_audio_transcription.completed":
                        self.applyTranscriptEvent(event)
                    case "session.finished":
                        self.finishRecognition(); return
                    case "error": self.fail("语音转写失败，请检查百炼北京地域 API Key"); return
                    default: break
                    }
                }
            } catch { if let self, self.generation == generation, !Task.isCancelled { self.fail("语音连接中断，请重试") } }
        }
        deadline("语音连接超时", seconds: 15)
    }
    func finishRecognition() {
        let text = finals.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        // Silence is a successful empty result, not a recording failure.
        completion?(text)
    }
    func applyTranscriptEvent(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "conversation.item.input_audio_transcription.text":
            partial = (event["text"] as? String ?? "") + (event["stash"] as? String ?? "")
        case "conversation.item.input_audio_transcription.delta":
            partial += event["delta"] as? String ?? event["text"] as? String ?? ""
        case "conversation.item.input_audio_transcription.completed":
            if !externalAudio || externalSignal {
                if let text = event["transcript"] as? String {
                    finals.append(text); caption = text; captionTime = Date(); onFinal?(text)
                }
            }
            partial = ""
        default: return
        }
        transcript = finals.joined() + partial
        if !partial.isEmpty, !externalAudio || externalSignal {
            caption = partial; captionTime = Date(); onPartial?(partial)
        }
    }
    private func emit(_ type: String, _ fields: [String: Any] = [:]) async throws {
        var body = fields; body["type"] = type; body["event_id"] = UUID().uuidString
        guard let ws else { throw AppError.message("录音已结束") }
        let data = try JSONSerialization.data(withJSONObject: body)
        try await ws.send(.string(String(data: data, encoding: .utf8)!))
    }
    private func capture() throws {
        let engine = AVAudioEngine(); let input = engine.inputNode
        let source = input.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0, let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false), let converter = AVAudioConverter(from: source, to: target) else { throw AppError.message("未检测到可用麦克风设备") }
        let generation = self.generation
        input.installTap(onBus: 0, bufferSize: 4096, format: source) { [weak self] buffer, _ in
            let count = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / source.sampleRate + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: count) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }; supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, let samples = output.int16ChannelData, output.frameLength > 0 else { return }
            let data = Data(bytes: samples[0], count: Int(output.frameLength) * 2)
            Task { @MainActor in guard let self, self.generation == generation, !self.finishing else { return }; self.enqueue(data) }
        }
        engine.prepare(); try engine.start(); self.engine = engine
    }
    private func enqueue(_ data: Data) {
        guard audioQueue.count < 80 else { fail("网络延迟较高，语音发送超时，请重试"); return }
        audioQueue.append(data); flush()
    }
    /// Network audio is backpressured by the caller, bypassing microphone capture and its queue.
    func appendStreamPCM(_ data: Data) async throws {
        guard externalAudio, active, phase == "正在转写", !finishing else { throw AppError.message("转写连接已断开") }
        if data.contains(where: { $0 != 0 }) { externalSignal = true }
        try await emit("input_audio_buffer.append", ["audio": data.base64EncodedString()])
    }
    private func flush() {
        guard !sending else { return }; sending = true
        let generation = self.generation
        Task { [weak self] in
            guard let self else { return }
            do {
                while !self.audioQueue.isEmpty && self.generation == generation { let data = self.audioQueue.removeFirst(); try await self.emit("input_audio_buffer.append", ["audio": data.base64EncodedString()]) }
                guard self.generation == generation else { return }
                self.sending = false
                if self.finishing { try await self.emit("session.finish") }
            } catch { if self.generation == generation { self.fail("语音上传失败，请重试") } }
        }
    }
    func stop() {
        guard active, !finishing, phase == "正在录音" || phase == "正在转写" else { return }
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        finishing = true; phase = "识别中"; flush(); deadline("语音识别超时，请重试", seconds: 15)
    }
    private func deadline(_ message: String, seconds: UInt64) {
        timeout?.cancel(); timeout = Task { [weak self] in try? await Task.sleep(nanoseconds: seconds * 1_000_000_000); guard !Task.isCancelled else { return }; self?.fail(message) }
    }
    private func fail(_ text: String) { cancel(); failure?(text) }
    func cancel() {
        generation = UUID(); timeout?.cancel(); reader?.cancel(); ws?.cancel(with: .normalClosure, reason: nil); ws = nil
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        audioQueue = []; sending = false; active = false; phase = ""
    }
}
