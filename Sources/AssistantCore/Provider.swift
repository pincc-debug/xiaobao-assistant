import Foundation

public struct ModelProvider: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name = "新服务"
    public var kind = Kind.compatible
    public var baseURL = "https://api.openai.com/v1"
    public var model = ""
    public var cachedModels: [String]?
    public var cachedModelsContext: String?
    public var modelsRefreshedAt: Date?
    public var modelsContext: String { kind.rawValue + "|" + baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var availableCachedModels: [String] { cachedModelsContext == modelsContext ? cachedModels ?? [] : [] }
    public enum Kind: String, Codable, CaseIterable { case compatible = "OpenAI 兼容", anthropic = "Anthropic" }
    public init() {}
    public func endpoint(_ path: String) throws -> URL {
        guard var url = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme, let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)) else { throw ProviderError.invalidURL }
        url.path = "/" + [url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), path].filter { !$0.isEmpty }.joined(separator: "/")
        url.query = nil; url.fragment = nil
        guard let result = url.url else { throw ProviderError.invalidURL }; return result
    }
}
public enum ProviderError: LocalizedError {
    case invalidURL
    public var errorDescription: String? { "请使用 HTTPS 接口地址；本机服务可使用 HTTP" }
}
