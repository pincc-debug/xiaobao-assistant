import Foundation
import CoreFoundation
import AssistantCore

/// Read-only verification; never cache ownership across accounts or connection attempts.
struct PolyvChannelOwnership {
    struct Account: Equatable {
        let appID: String
        let userID: String
        let secret: String
    }
    var transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    func validate(channel: String, account: Account) async throws {
        guard !account.appID.isEmpty, !account.userID.isEmpty, !account.secret.isEmpty else {
            throw AppError.message("请先配置保利威接入凭据")
        }
        var params = ["appId": account.appID, "channelId": channel,
                      "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))]
        params["sign"] = ChatGateway.signature(params, secret: account.secret)
        var url = URLComponents(string: "https://api.polyv.net/live/v4/channel/basic/get")!
        url.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AppError.message("频道校验失败，请稍后重试") }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw AppError.message("频道校验失败，请稍后重试") }
        guard http.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["code"] as? Int == 200, result["status"] as? String == "success",
              let detail = result["data"] as? [String: Any] else {
            throw AppError.message("无法验证频道，请检查频道号和账号凭据")
        }
        // v4 exposes the account in userCategory and authSettings, not a top-level userId.
        func channelID(_ value: Any?) -> String? {
            if let value = value as? String { return value }
            if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.stringValue }
            return nil
        }
        guard channelID(detail["channelId"]) == channel else { throw AppError.message("频道校验失败，请重试") }
        var owners: [String] = []
        if let category = detail["userCategory"] as? [String: Any], let owner = category["userId"] as? String { owners.append(owner) }
        if let settings = detail["authSettings"] as? [[String: Any]] {
            for setting in settings {
                guard channelID(setting["channelId"]) == channel, let owner = setting["userId"] as? String else {
                    throw AppError.message("无法确认频道归属，请重试")
                }
                owners.append(owner)
            }
        }
        guard !owners.isEmpty, owners.allSatisfy({ !$0.isEmpty }) else { throw AppError.message("无法确认频道归属，请重试") }
        guard owners.allSatisfy({ $0 == account.userID }) else { throw AppError.message("该频道不属于当前保利威账号") }
    }
}

extension Store {
    var channelAccount: PolyvChannelOwnership.Account {
        .init(appID: saved.preferences.appID.trimmingCharacters(in: .whitespacesAndNewlines),
              userID: saved.preferences.userID.trimmingCharacters(in: .whitespacesAndNewlines),
              secret: polyvSecret.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func validateChannelOwnership(_ channel: String) async throws {
        let account = channelAccount
        try await channelOwnership.validate(channel: channel, account: account)
        try Task.checkCancellation()
        guard channelAccount == account else { throw AppError.message("账号已变更，请重试") }
    }
    func createValidatedPreparation(channel: String, title: String) async throws -> UUID {
        guard let channel = normalizedClassroomChannel(channel) else { throw AppError.message("请输入有效频道号") }
        try await validateChannelOwnership(channel)
        return try createPreparation(channel: channel, title: title)
    }
}
