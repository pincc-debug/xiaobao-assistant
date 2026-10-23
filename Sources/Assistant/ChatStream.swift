import Foundation
import AssistantCore

/// Accumulates complete SSE events. Tool arguments are never exposed as reply text.
struct ChatStreamAccumulator {
    var text = ""
    var calls: [Int: (name: String, arguments: String)] = [:]
    var finished = false
    mutating func accept(_ payload: String, anthropic: Bool) throws {
        if payload == "[DONE]" { return }
        guard let data = payload.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.message("回答格式异常，请重试") }
        if event["error"] != nil || event["type"] as? String == "error" { throw AppError.message("回答服务暂不可用，请重试") }
        if anthropic {
            let index = event["index"] as? Int ?? 0
            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any] ?? [:]
                if block["type"] as? String == "tool_use" { calls[index] = (block["name"] as? String ?? "", "") }
                else if block["type"] as? String == "text" { text += block["text"] as? String ?? "" }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                if delta["type"] as? String == "text_delta" { text += delta["text"] as? String ?? "" }
                if delta["type"] as? String == "input_json_delta", var call = calls[index] { call.arguments += delta["partial_json"] as? String ?? ""; calls[index] = call }
            case "message_delta":
                if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String {
                    guard ["end_turn", "tool_use", "stop_sequence"].contains(reason) else { throw AppError.message("回答未完成，请重试") }
                    finished = true
                }
            default: break
            }
        } else {
            for choice in event["choices"] as? [[String: Any]] ?? [] where (choice["index"] as? Int ?? 0) == 0 {
                let delta = choice["delta"] as? [String: Any] ?? [:]
                text += delta["content"] as? String ?? ""
                for fragment in delta["tool_calls"] as? [[String: Any]] ?? [] {
                    let index = fragment["index"] as? Int ?? 0
                    let function = fragment["function"] as? [String: Any] ?? [:]
                    var call = calls[index] ?? ("", "")
                    call.name += function["name"] as? String ?? ""
                    call.arguments += function["arguments"] as? String ?? ""
                    calls[index] = call
                }
                if let reason = choice["finish_reason"] as? String {
                    guard ["stop", "tool_calls"].contains(reason) else { throw AppError.message("回答未完成，请重试") }
                    finished = true
                }
            }
        }
        guard calls.count <= 1, text.utf8.count + calls.values.reduce(0, { $0 + $1.arguments.utf8.count }) <= 1_000_000 else { throw AppError.message("回答内容异常，请重试") }
    }
    func decision() throws -> [String: Any] {
        guard finished else { throw AppError.message("回答连接中断，请重试") }
        if let call = calls.values.first {
            guard !call.name.isEmpty else { throw AppError.message("工具指令不完整，请重试") }
            return ["name": call.name, "arguments": try ProviderAPI.parseJSON(call.arguments.isEmpty ? "{}" : call.arguments), "progress": text]
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("助教没有返回内容，请重试") }
        return ["message": text]
    }
}

extension ProviderAPI {
    static func streamDecision(_ request: URLRequest, anthropic: Bool, onText: @escaping @Sendable (String) -> Void) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 120
        let session = URLSession(configuration: configuration, delegate: RejectRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AppError.message(status == 401 || status == 403 ? "请检查 API Key 和模型权限" : "服务请求失败（\(status)）") }
        var accumulator = ChatStreamAccumulator(), decoder = SSEFrameDecoder()
        var total = 0, lastText = ""
        func consume(_ payload: String) throws {
            try accumulator.accept(payload, anthropic: anthropic)
            if accumulator.calls.isEmpty, accumulator.text != lastText { lastText = accumulator.text; onText(lastText) }
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            total += 1
            guard total <= 10_000_000 else { throw AppError.message("回答内容过长") }
            if let payload = try decoder.append(byte) { try consume(payload) }
        }
        if let payload = try decoder.finish() { try consume(payload) }
        try Task.checkCancellation()
        return try accumulator.decision()
    }
}


struct SSEFrameDecoder {
    private var line: [UInt8] = []
    private var fields: [String] = []
    mutating func append(_ byte: UInt8) throws -> String? {
        if byte != 10 {
            line.append(byte)
            guard line.count < 1_000_000 else { throw AppError.message("回答内容过长") }
            return nil
        }
        return try consumeLine()
    }
    private mutating func consumeLine() throws -> String? {
        if line.last == 13 { line.removeLast() }
        guard let text = String(bytes: line, encoding: .utf8) else { throw AppError.message("回答编码异常") }
        line = []
        if text.isEmpty {
            guard !fields.isEmpty else { return nil }
            let payload = fields.joined(separator: "\n"); fields = []; return payload
        }
        if text.hasPrefix("data:") {
            var value = String(text.dropFirst(5)); if value.hasPrefix(" ") { value.removeFirst() }
            fields.append(value)
        }
        return nil
    }
    mutating func finish() throws -> String? {
        if !line.isEmpty, let payload = try consumeLine() { return payload }
        guard !fields.isEmpty else { return nil }
        let payload = fields.joined(separator: "\n"); fields = []; return payload
    }
}
