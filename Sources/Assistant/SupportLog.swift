import Foundation
import AppKit
import CryptoKit
import AssistantCore

@MainActor final class SupportLog {
    let root: URL
    private(set) var directory: URL?
    private(set) var runID = ""
    private var segment = 0
    init(root: URL) { self.root = root }
    func start(channel: String) {
        runID = UUID().uuidString; segment = 0
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        directory = root.appendingPathComponent(stamp + "-" + String(runID.prefix(8)))
        try? FileManager.default.createDirectory(at: directory!, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        write("session.start", fields: ["channel": channel, "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development", "os": ProcessInfo.processInfo.operatingSystemVersionString])
    }
    static func scrub(_ fields: [String:Any]) -> [String:Any] {
        fields.mapValues { $0 }.reduce(into: [:]) { result, pair in
            let key = pair.key.lowercased().replacingOccurrences(of: "_", with: "")
            if ["key", "apikey", "appsecret", "secret", "token", "channeltoken", "authorization", "password", "sign", "cookie"].contains(key) { result[pair.key] = "[redacted]" }
            else if let object = pair.value as? [String:Any] { result[pair.key] = scrub(object) }
            else if let array = pair.value as? [Any] { result[pair.key] = array.prefix(50).map { scrub(["value": $0])["value"] ?? NSNull() } }
            else if let value = pair.value as? String {
                let redacted = value.replacingOccurrences(of: #"(?i)bearer\s+\S+|sk-[A-Za-z0-9_-]+|\b(?:loginToken|token|appSecret|apiKey|sign|password)=[^\s&]+"#, with: "[redacted]", options: .regularExpression)
                result[pair.key] = String(redacted.prefix(1500))
            } else { result[pair.key] = pair.value }
        }
    }
    func write(_ event: String, level: String = "info", fields: [String:Any] = [:]) {
        guard let directory else { return }
        var url = directory.appendingPathComponent("assistant-\(segment).jsonl")
        if (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 8_000_000 { segment += 1; url = directory.appendingPathComponent("assistant-\(segment).jsonl") }
        let entry: [String:Any] = ["time": ISO8601DateFormatter().string(from: Date()), "unix_ms": Int(Date().timeIntervalSince1970 * 1000), "run_id": runID, "level": level, "event": event, "fields": Self.scrub(fields)]
        guard var data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }; data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions:0o600]) }
        if let handle = try? FileHandle(forWritingTo: url) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf: data) }
    }
}
extension Store {
    func diagnostic(_ event: String, _ fields: [String:Any] = [:], error: Bool = false) { supportLog.write(event, level: error ? "error" : "info", fields: fields) }
    func attachLogToCourse() {
        guard let i = courseIndex, let path = supportLog.directory?.path else { return }
        var paths = saved.courses[i].logDirectories ?? []
        if !paths.contains(path) { paths.append(path); saved.courses[i].logDirectories = paths; persist() }
    }
    func openLogs() {
        let root = supportLog.root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }
    func exportLogs(_ course: CourseSession) {
        let paths = course.logDirectories ?? []
        guard !paths.isEmpty else { error = "本场没有运行日志"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "助教日志-\(course.channel)-\(String(ISO8601DateFormatter().string(from: course.started).prefix(10))).zip"
        panel.placeOnAssistantScreen()
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("AssistantLogs-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            for path in paths {
                let source = URL(fileURLWithPath: path).standardizedFileURL
                guard source.path.hasPrefix(supportLog.root.standardizedFileURL.path + "/"), FileManager.default.fileExists(atPath: source.path) else { continue }
                try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
            }
            let manifest: [String:Any] = ["channel":course.channel,"session_id":course.platformSessionID ?? "","started":ISO8601DateFormatter().string(from:course.started),"messages":course.events?.count ?? 0,"answers":course.answers.count,"operations":course.operations?.count ?? 0,"exercises":course.exercises?.count ?? 0]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: staging.appendingPathComponent("manifest.json"))
            let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto"); process.arguments = ["-c","-k","--keepParent",staging.path,destination.path]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw AppError.message("日志导出失败") }
        } catch { self.error = error.localizedDescription }
    }
}
