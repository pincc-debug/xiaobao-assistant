import Foundation
import CryptoKit
import AssistantCore

extension ChatGateway {
    var targetChannel: String { channelValue }
    func readSession(_ json: [String: Any]) {
        let data = json["data"] as? [String: Any] ?? json
        guard let id = data["sessionId"] as? String, !id.isEmpty else { return }
        sessionID = id
        var started: Date?
        if let timestamp = data["startTime"] as? Double, timestamp > 1_000_000_000 { started = Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp) }
        onSession?(id, started)
        if started == nil, resolvingSessionID != id {
            resolvingSessionID = id
            let stamp = connectionStamp
            Task {
                do {
                    let data = try await api("/live/v4/statistics/session-stats/summary/list", params: ["keyword": id, "pageNumber": "1", "pageSize": "20"], method: "GET") as? [String:Any]
                    guard connectionStamp == stamp, let item = (data?["contents"] as? [[String:Any]])?.first(where: { $0["sessionId"] as? String == id }) else { return }
                    let raw = (item["startTime"] as? NSNumber)?.doubleValue ?? Double(item["startTime"] as? String ?? "") ?? 0
                    if raw > 0 { onSession?(id, Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1000 : raw)) }
                } catch { /* Remains explicitly marked as join time until verified. */ }
            }
        }
    }
    func emitAcknowledged(event: String, raw: String) async throws -> Any {
        guard isConnected, let socket else { throw AppError.message("聊天室未连接") }
        return try await withCheckedThrowingContinuation { continuation in
            socket.emitWithAck(event, raw).timingOut(after: 12) { values in
                guard let value = values.first, value as? String != "NO ACK" else { continuation.resume(throwing: AppError.message("未确认执行结果，请先查询状态")); return }
                if let object = value as? [String: Any], let code = object["code"] as? Int, code != 200 { continuation.resume(throwing: AppError.message("平台执行失败（\(code)）")); return }
                continuation.resume(returning: value)
            }
        }
    }
    func api(_ path: String, params: [String:String], method: String = "POST") async throws -> Any {
        guard !preferences.appID.isEmpty, !secret.isEmpty else { throw AppError.message("请配置保利威凭据") }
        var fields = params; fields["channelId"] = targetChannel; fields["appId"] = preferences.appID; fields["timestamp"] = String(Int(Date().timeIntervalSince1970 * 1000)); fields["sign"] = Self.signature(fields, secret: secret)
        var c = URLComponents(); c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        let encoded = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        var request = URLRequest(url: URL(string: "https://api.polyv.net" + path + (method == "GET" ? "?" + encoded : ""))!); request.httpMethod = method; request.timeoutInterval = 20
        if method != "GET" { request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"); request.httpBody = Data(encoded.utf8) }
        let json = try await ProviderAPI.execute(request)
        guard json["code"] as? Int == 200 else { throw AppError.message("平台操作失败（\(json["code"] ?? "未知")）") }
        return json["data"] ?? NSNull()
    }
    func channelAuthorization() async throws -> [String: Any] {
        let result = try await api("/live/v3/common/token/get-channel-token", params: [:])
        guard let token = result as? [String:Any], let value = token["channelToken"] as? String else { throw AppError.message("互动授权失败") }
        return ["channelId": targetChannel, "channelToken": value, "expireTime": token["expireTime"] ?? 0, "appId": preferences.appID, "timestamp": Int(Date().timeIntervalSince1970 * 1000)]
    }
}

extension ChatGateway {
    // Matches @polyv/chat-sdk official assistant demo getRoomSign and pc-client-embed sendKick.
    // This is a protocol constant, not an account credential or App Secret.
    static func roomSignature(_ roomID: String) -> String {
        Insecure.MD5.hash(data: Data(("polyv_room_sign" + roomID).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func kick(_ userID: String, restore: Bool) async throws -> Any {
        guard isConnected, !roomID.isEmpty else { throw AppError.message("聊天室未连接") }
        let sign = Self.roomSignature(roomID)
        if restore {
            var c = URLComponents(string: "https://apichat.polyv.net/admin/delKicked")!
            c.queryItems = ["roomId": roomID, "sign": sign, "type": "userId", "value": userID, "toGetSubRooms": "false"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let result = try await ProviderAPI.execute(URLRequest(url: c.url!))
            guard result["code"] as? Int == 200 || result["status"] as? String == "success" else { throw AppError.message("解除踢出未成功") }
            return result
        }
        let payload: [String:Any] = ["EVENT": "KICK", "roomId": roomID, "channelId": targetChannel, "sign": sign, "userId": userID, "type": "userId"]
        let raw = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let result = try await emitAcknowledged(event: "message", raw: raw)
        guard result as? String == "KICK" || (result as? [String:Any])?["code"] as? Int == 200 else { throw AppError.message("未确认踢出结果，请查看聊天室") }
        return ["success": true]
    }
}
