import SwiftUI
import AppKit
import AssistantCore

enum BroadcastDestination {
    case client, web
}

/// Launch credentials are fetched on demand and never persisted or logged.
struct PolyvBroadcastLaunch {
    var transport: (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }

    func link(channel: String, account: PolyvChannelOwnership.Account, destination: BroadcastDestination) async throws -> URL {
        guard !channel.isEmpty, channel.allSatisfy({ $0.isASCII && $0.isNumber }),
              !account.appID.isEmpty, !account.secret.isEmpty else {
            throw AppError.message("请检查频道号和保利威凭据")
        }
        let path = destination == .web ? "/live/v3/channel/common/token-login-url" : "/live/v2/channels/\(channel)/get"
        var fields = ["appId": account.appID, "channelId": channel, "timestamp": String(Int(Date().timeIntervalSince1970 * 1000))]
        fields["sign"] = ChatGateway.signature(fields, secret: account.secret)
        var query = URLComponents()
        query.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        let encoded = query.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B")
        var request = URLRequest(url: URL(string: "https://api.polyv.net\(path)" + (destination == .client ? "?\(encoded)" : ""))!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = destination == .web ? "POST" : "GET"
        if destination == .web {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(encoded.utf8)
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw AppError.message("获取开播信息失败，请重试") }
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["code"] as? Int == 200 else {
            throw AppError.message("获取开播信息失败，请检查账号权限")
        }
        if destination == .web {
            // Official documentation shows both a string and a data.token object.
            let raw = json["data"] as? String ?? (json["data"] as? [String: Any])?["token"] as? String
            guard let raw, let url = URL(string: raw), url.scheme == "https",
                  let host = url.host, host == "polyv.net" || host.hasSuffix(".polyv.net"),
                  url.user == nil, url.password == nil else {
                throw AppError.message("免密链接无效，请重试")
            }
            return url
        }
        guard let detail = json["data"] as? [String: Any],
              String(describing: detail["channelId"] ?? "") == channel,
              let password = detail["channelPasswd"] as? String, !password.isEmpty else {
            throw AppError.message("未获取到频道密码，请检查频道配置")
        }
        var url = URLComponents(string: "polyvlive://start")!
        url.queryItems = [
            .init(name: "pdn", value: "api.polyv.net"),
            .init(name: "channelId", value: channel),
            .init(name: "passwd", value: password)
        ]
        return url.url!
    }
}

struct BroadcastLaunchMenu: View {
    @ObservedObject var store: Store
    let channel: String
    let lessonID: UUID
    @State private var error: String?

    var body: some View {
        Menu {
            Button("客户端开播") { launch(.client) }
            Button("网页开播") { launch(.web) }
        } label: {
            if store.broadcastLaunching { ProgressView().controlSize(.mini) }
            else { Label(store.connected && store.channel == channel ? "上课中" : "开播", systemImage: "video").font(.system(size: 12)) }
        }
        .menuStyle(.borderlessButton).fixedSize().disabled(store.broadcastLaunching)
        .padding(.horizontal, 3)
        .alert("无法打开开播端", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    @MainActor private func launch(_ destination: BroadcastDestination) {
        Task { @MainActor in
            do { try await store.launchBroadcast(channel: channel, lessonID: lessonID, destination: destination) }
            catch { self.error = error.localizedDescription }
        }
    }
}

extension Store {
    func launchBroadcast(channel: String, lessonID: UUID, destination: BroadcastDestination) async throws {
        guard !broadcastLaunching else { return }
        broadcastLaunching = true
        defer { broadcastLaunching = false }
        let account = channelAccount
        let workspace = NSWorkspace.shared
        let app: URL
        if destination == .web {
            guard let chrome = workspace.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
                throw AppError.message("请先安装 Google Chrome")
            }
            app = chrome
        } else {
            guard let client = workspace.urlForApplication(toOpen: URL(string: "polyvlive://start")!) else {
                throw AppError.message("请先安装保利威直播客户端")
            }
            app = client
        }
        try await channelOwnership.validate(channel: channel, account: account)
        let url = try await PolyvBroadcastLaunch().link(channel: channel, account: account, destination: destination)
        guard channelAccount == account else { throw AppError.message("账号已变更，请重试") }
        try await startBroadcastClass(channel: channel, lessonID: lessonID)
        guard channelAccount == account else { throw AppError.message("账号已变更，请重试") }
        do {
            _ = try await workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } catch { throw AppError.message("打开失败，请重试") }
        showBroadcastDesktop?()
    }
    /// Uses local lesson context only; nothing here waits for the lecturer to start streaming.
    func configureBroadcastClass(channel target: String, lessonID: UUID) throws -> Bool {
        guard !busy else { throw AppError.message("正在连接，请稍候") }
        if connected {
            guard channel == target, currentCourseID == lessonID ||
                    currentCourse?.candidatePreparationID == lessonID ||
                    preparations(target).contains(where: { $0.id == lessonID && $0.usedByCourseID == currentCourseID }) else {
                throw AppError.message("请先结束当前课程")
            }
            return false
        }
        if let currentCourse {
            guard currentCourse.channel == target,
                  currentCourse.id == lessonID || currentCourse.preparation?.id == lessonID ||
                    currentCourse.candidatePreparationID == lessonID else {
                throw AppError.message("请先结束当前课程")
            }
            channel = target
            selectedPreparationID = nil
            return true
        }
        guard roomRunIDs[target] == nil else { throw AppError.message("请等待备课处理完成") }
        guard let plan = preparations(target).first(where: { $0.id == lessonID && $0.usedByCourseID == nil }) else {
            throw AppError.message("请新建课程后开播")
        }
        channel = target
        selectedPreparationID = lessonID
        focus = plan.title
        return true
    }

    func startBroadcastClass(channel target: String, lessonID: UUID) async throws {
        guard try configureBroadcastClass(channel: target, lessonID: lessonID) else { return }
        connect()
        let attempt = connectionAttempt
        await connectionTask?.value
        for _ in 0..<150 {
            guard connectionAttempt == attempt, channel == target else { throw AppError.message("开课已取消，请重试") }
            if connected {
                bindPreparationToCurrentCourse(requirePlatformSession: false)
                guard currentCourse != nil else { throw AppError.message("课程记录创建失败，请重试") }
                return
            }
            if !error.isEmpty { throw AppError.message(error) }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        stop()
        throw AppError.message("连接超时，请重试")
    }
}
