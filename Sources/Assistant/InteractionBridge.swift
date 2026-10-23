import Foundation
import WebKit

@MainActor final class InteractionBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var gateway: ChatGateway?
    var transportOverride: (([String:Any]) async throws -> Any)?
    private var web: WKWebView?
    private var ready = false
    private var calling = false
    var isBusy: Bool { calling }
    private var activeStamp: String?
    init(gateway: ChatGateway) { self.gateway = gateway; super.init() }
    func reset() { web?.configuration.userContentController.removeScriptMessageHandler(forName: "platform", contentWorld: .page); web = nil; ready = false }
    func prepare() async throws {
        if !ready {
            let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
            config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "platform")
            let view = WKWebView(frame: .zero, configuration: config); web = view
            view.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://localhost"))
            for _ in 0..<100 { if !view.isLoading { break }; try await Task.sleep(nanoseconds: 20_000_000) }
            // XHR is replaced before loading SDK so its transport uses the native adapter.
            let bridge = try String(contentsOf: Bundle.module.url(forResource: "interaction-bridge", withExtension: "js")!)
            _ = try await view.script(bridge + "\n;null")
            let sdk = try String(contentsOf: Bundle.module.url(forResource: "polyv-il-0.7.0", withExtension: "js")!)
            _ = try await view.script(sdk + "\n;null")
            ready = true
            gateway?.onRawEvent = { [weak self] event, raw in
                guard let view = self?.web else { return }
                Task { _ = try? await view.asyncScript("window.deliver(event,raw)", arguments: ["event": event, "raw": raw]) }
            }
        }
        guard let gateway, gateway.isConnected, let web else { throw AppError.message("聊天室未连接") }
        _ = try await web.asyncScript("window.configure(config)", arguments: ["config": ["channelId": gateway.targetChannel, "roomId": gateway.roomID, "sessionId": gateway.sessionID, "socketId": gateway.socket?.sid ?? ""]])
    }
    func call(_ module: String, _ method: String, _ args: [Any] = []) async throws -> Any {
        guard !calling else { throw AppError.message("上一项互动正在处理，请稍后重试") }
        calling = true; activeStamp = gateway?.connectionStamp
        defer { calling = false; activeStamp = nil }
        try await prepare()
        guard activeStamp == gateway?.connectionStamp else { throw AppError.message("场次已切换") }
        guard let web else { throw AppError.message("互动服务未就绪") }
        return try await web.asyncScript("return await Promise.race([window.invoke(module,method,args),new Promise((_,reject)=>setTimeout(()=>reject(Error('操作超时，请先查询状态')),20000))]);", arguments: ["module": module, "method": method, "args": args]) ?? NSNull()
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let gateway, activeStamp == gateway.connectionStamp else { replyHandler(nil, "无效请求"); return }
        Task {
            do {
                if let transportOverride { replyHandler(try await transportOverride(body), nil); return }
                let result: Any
                switch body["kind"] as? String {
                case "socket": result = try await gateway.emitAcknowledged(event: body["event"] as? String ?? "message", raw: body["raw"] as? String ?? "")
                case "authorization": result = try await gateway.channelAuthorization()
                case "http":
                    guard let raw = body["url"] as? String, let url = URL(string: raw), url.scheme == "https", ["api.polyv.net", "apichat.polyv.net"].contains(url.host ?? "") else { throw AppError.message("互动接口地址无效") }
                    var request = URLRequest(url: url); request.httpMethod = body["method"] as? String ?? "GET"; request.timeoutInterval = 15
                    for (k,v) in body["headers"] as? [String:String] ?? [:] { request.setValue(v, forHTTPHeaderField: k) }
                    if let text = body["body"] as? String, !text.isEmpty { request.httpBody = Data(text.utf8) }
                    let session = URLSession(configuration: .ephemeral, delegate: RejectRedirect(), delegateQueue: nil); defer { session.invalidateAndCancel() }
                    let (data, response) = try await session.data(for: request)
                    result = ["status": (response as? HTTPURLResponse)?.statusCode ?? 0, "text": String(data: data, encoding: .utf8) ?? ""]
                default: throw AppError.message("未知互动请求")
                }
                replyHandler(result, nil)
            } catch { replyHandler(nil, error.localizedDescription) }
        }
    }
}

@MainActor extension WKWebView {
    func script(_ code: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(code) { value, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: value) }
            }
        }
    }
    func asyncScript(_ code: String, arguments: [String:Any]) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            callAsyncJavaScript(code, arguments: arguments, in: nil, in: .page) { result in continuation.resume(with: result.map { Optional($0) }) }
        }
    }
}
