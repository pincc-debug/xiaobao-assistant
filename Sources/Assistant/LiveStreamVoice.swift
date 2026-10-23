import Foundation
import Combine

struct LiveStreamAddress {
    var transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    func resolve(channel: String, account: PolyvChannelOwnership.Account) async throws -> URL {
        guard !channel.isEmpty, channel.utf8.allSatisfy({ (48...57).contains($0) }),
              !account.appID.isEmpty, !account.secret.isEmpty else { throw AppError.message("请检查保利威凭据") }
        var fields = ["channelId": channel, "appId": account.appID, "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))]
        fields["sign"] = ChatGateway.signature(fields, secret: account.secret)
        var url = URLComponents(string: "https://api.polyv.net/live/v2/channels/\(channel)/get")!
        url.queryItems = fields.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        let (data, response) = try await transport(URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["code"] as? Int == 200, let detail = result["data"] as? [String: Any],
              String(describing: detail["channelId"] ?? "") == channel,
              let raw = detail["m3u8Url"] as? String,
              let playback = URL(string: raw), ["https", "http"].contains(playback.scheme ?? ""),
              playback.host != nil, playback.user == nil, playback.password == nil else {
            throw AppError.message("获取直播音频失败")
        }
        return playback
    }
}

/// A dedicated network-audio session. VoiceSession remains the microphone input for commands.
@MainActor final class LiveStreamVoiceSession: ObservableObject {
    @Published private(set) var phase = ""
    @Published private(set) var active = false
    var onDiagnostic: ((String, [String: Any]) -> Void)?
    var onFinal: ((String) -> Void)?
    var completion: ((String) -> Void)?
    var failure: ((String) -> Void)?
    private let recognition = VoiceSession()
    private var task: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var process: Process?
    private var generation = UUID()
    private var lastAudio = Date()
    private var stopping = false
    private var lastPlaylistSequence: String?
    var address = LiveStreamAddress()

    static var decoder: URL? {
        let paths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg").path,
            "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"
        ]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    static func arguments(url: URL) -> [String] {
        ["-nostdin", "-hide_banner", "-loglevel", "error", "-rw_timeout", "15000000",
         "-protocol_whitelist", "http,https,tcp,tls,crypto", "-re", "-live_start_index", "-1",
         "-i", url.absoluteString, "-map", "0:a:0", "-vn", "-ar", "16000", "-ac", "1",
         "-acodec", "pcm_s16le", "-f", "s16le", "pipe:1"]
    }
    private func setPhase(_ value: String) {
        guard phase != value else { return }
        phase = value; onDiagnostic?("phase", ["value": value])
    }

    func start(key: String, host: String, channel: String, account: PolyvChannelOwnership.Account) async {
        guard !active else { return }
        guard let decoder = Self.decoder else { failure?("缺少直播音频组件，请重新安装"); return }
        guard !key.isEmpty else { failure?("请填写语音转写 API Key"); return }
        generation = UUID(); let run = generation
        active = true; stopping = false; lastPlaylistSequence = nil
        setPhase("等待直播音频")
        recognition.onFinal = { [weak self] text in
            guard let self, self.generation == run else { return }
            self.onFinal?(text)
        }
        recognition.completion = { [weak self] text in
            guard let self, self.generation == run, self.stopping else { return }
            self.active = false; self.setPhase(""); self.completion?(text)
        }
        recognition.failure = { [weak self] _ in
            guard let self, self.generation == run else { return }
            if self.stopping {
                self.active = false; self.setPhase(""); self.completion?("")
            } else {
                self.setPhase("转写重试中")
                self.stopDecoder()
            }
        }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == run, !self.stopping {
                do {
                    let url = try await self.address.resolve(channel: channel, account: account)
                    try Task.checkCancellation()
                    guard self.generation == run else { return }
                    // Avoid replaying a cached tail when a finished stream still serves its playlist.
                    let (playlist, response) = try await self.address.transport(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12))
                    guard (response as? HTTPURLResponse)?.statusCode == 200,
                          let text = String(data: playlist, encoding: .utf8), text.hasPrefix("#EXTM3U"),
                          !text.contains("#EXT-X-ENDLIST") else { throw AppError.message("等待直播音频") }
                    try Task.checkCancellation()
                    guard self.generation == run, !self.stopping else { return }
                    let sequence = text.split(separator: "\n").first { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") }.map(String.init)
                    if let sequence, sequence == self.lastPlaylistSequence { throw AppError.message("等待直播音频") }
                    self.lastPlaylistSequence = sequence
                    try await self.decode(url: url, decoder: decoder, key: key, host: host, run: run)
                } catch {
                    // Never expose signed stream URLs, provider responses or process stderr.
                    if !Task.isCancelled, self.generation == run { self.setPhase("等待直播音频") }
                }
                guard self.generation == run, !self.stopping else { return }
                self.stopDecoder()
                if self.recognition.phase == "正在转写" {
                    self.recognition.stop()
                    for _ in 0..<160 {
                        if !self.recognition.active || self.stopping || Task.isCancelled { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                guard self.generation == run, !self.stopping, !Task.isCancelled else { return }
                self.recognition.cancel()
                self.setPhase("等待直播音频")
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            }
        }
    }

    private func decode(url: URL, decoder: URL, key: String, host: String, run: UUID) async throws {
        let child = Process(), pipe = Pipe()
        child.executableURL = decoder; child.arguments = Self.arguments(url: url)
        child.standardInput = FileHandle.nullDevice; child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        process = child; lastAudio = Date()
        try child.run()
        pipe.fileHandleForWriting.closeFile()
        let monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.generation == run, !Task.isCancelled else { return }
                if Date().timeIntervalSince(self.lastAudio) > 25 { self.stopDecoder(); return }
            }
        }
        watchdog = monitor
        // One read and one send at a time: no unbounded tasks or accumulated audio when ASR is slow.
        let read = pipe.fileHandleForReading
        defer { monitor.cancel(); try? read.close() }
        var remainder = Data()
        while !Task.isCancelled, generation == run, !stopping {
            let chunk = try await Task.detached { try read.read(upToCount: 6400) ?? Data() }.value
            guard !chunk.isEmpty else { return }
            try Task.checkCancellation()
            guard generation == run, !stopping else { return }
            lastAudio = Date()
            if !recognition.active {
                await recognition.start(key: key, host: host, externalAudio: true)
                for _ in 0..<150 {
                    if recognition.phase == "正在转写" { break }
                    guard recognition.active else { throw AppError.message("转写连接失败") }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            remainder.append(chunk)
            let size = remainder.count - remainder.count % 2
            if size > 0 {
                try await recognition.appendStreamPCM(Data(remainder.prefix(size)))
                remainder.removeFirst(size)
            }
            setPhase("正在转写")
        }
    }
    private func stopDecoder() {
        watchdog?.cancel(); watchdog = nil
        if let child = process, child.isRunning {
            child.terminate()
            Task.detached {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        process = nil
    }
    func stop() {
        guard active else { return }
        stopping = true; task?.cancel(); task = nil; stopDecoder()
        if recognition.phase == "正在转写" {
            setPhase("识别中"); recognition.stop()
        } else {
            recognition.cancel(); active = false; setPhase(""); completion?("")
        }
    }
    func cancel() {
        generation = UUID(); stopping = true; task?.cancel(); task = nil
        stopDecoder(); recognition.cancel(); active = false; setPhase("")
    }
}
