import Foundation

public enum AssistantCapability: String, Codable, CaseIterable, Identifiable {
    case questionRadar, knowledgeAnswers, technicalAlerts, riskAlerts, messageDigest
    case voiceInput, announcements, materials, welcomeRecap
    case transcription, quoteCards, courseArchive
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .questionRadar: return "智能答疑"
        case .knowledgeAnswers: return "智能答疑"
        case .technicalAlerts: return "直播异常提醒"
        case .riskAlerts: return "违规消息"
        case .messageDigest: return "消息聚合"
        case .voiceInput: return "对助教说"
        case .announcements: return "发布公告"
        case .materials: return "发送课件"
        case .welcomeRecap: return "欢迎总结"
        case .transcription: return "实时转写"
        case .quoteCards: return "知识点提炼"
        case .courseArchive: return "课程归档"
        }
    }
    public var detail: String {
        switch self {
        case .questionRadar, .knowledgeAnswers: return "优先依据知识库自动回复常见问题，无把握时转交主讲确认"
        case .technicalAlerts: return "多人提出相同问题或反馈卡顿时提醒"
        case .riskAlerts: return "自动识别违规言论，支持一键禁言或踢出"
        case .messageDigest: return "汇总聊天室热议话题，帮助主讲掌握互动氛围"
        case .voiceInput: return "点击形象下方的「对助教说」，即可下达指令"
        case .announcements: return "用「对助教说」发布公告"
        case .materials: return "用「对助教说」发送课件"
        case .welcomeRecap: return "新观众进入直播间时，自动生成前情回顾"
        case .transcription: return "将讲课内容实时转为文字"
        case .quoteCards: return "提炼课堂知识点，自动发送至聊天室"
        case .courseArchive: return "课中随堂提炼笔记与问答，下课后自动生成完整档案"
        }
    }
    /// Always on, not listed as switches (voice commands).
    public var alwaysOn: Bool { self == .technicalAlerts || self == .voiceInput || self == .announcements || self == .materials || self == .transcription }   // 实时转写: always on (needs speech API)
    /// Off unless the user opts in.
    public var defaultEnabled: Bool { self != .welcomeRecap && self != .quoteCards }   // auto-send features are opt-in
    /// Small tag next to the row title.
    public var tag: String? { nil }
    public var dependencies: [Self] {
        switch self {
        case .knowledgeAnswers: return [.questionRadar]
        case .quoteCards: return []
        default: return []
        }
    }
}
/// High-frequency alert: fires once when a cluster of viewers saying the same thing reaches the threshold.
public enum HighFrequency {
    public static let threshold = 3
    public static func crossed(from before: Int, to after: Int) -> Bool { before < threshold && after >= threshold }
}
/// Settings page groups. 智能答疑 (.knowledgeAnswers row) covers questionRadar + knowledgeAnswers.
public enum CapabilityGroup: String, CaseIterable, Identifiable {
    case watch, reply, wrapUp
    public var id: String { rawValue }
    public var title: String {
        switch self { case .watch: return "互动管理"; case .reply: return "智能回复"; case .wrapUp: return "课程沉淀" }
    }
    public var rule: String? {
        switch self {
        case .watch: return nil
        case .reply: return nil
        case .wrapUp: return nil
        }
    }
    public var rows: [AssistantCapability] {
        switch self {
        case .watch: return [.riskAlerts, .messageDigest]
        case .reply: return [.knowledgeAnswers, .welcomeRecap, .quoteCards]
        case .wrapUp: return [.courseArchive]
        }
    }
}
public struct CapabilitySelection: Codable, Equatable {
    public var values: [String: Bool] = [:]
    public init() {}
    public func isEnabled(_ capability: AssistantCapability) -> Bool {
        if capability.alwaysOn { return true }
        // 智能答疑 is one switch: collecting questions only runs together with knowledge answers.
        if capability == .questionRadar { return raw(.questionRadar) && raw(.knowledgeAnswers) }
        return raw(capability) && capability.dependencies.allSatisfy { isEnabled($0) }
    }
    private func raw(_ capability: AssistantCapability) -> Bool {
        values[capability.rawValue] ?? capability.defaultEnabled
    }
    public mutating func set(_ capability: AssistantCapability, enabled: Bool) {
        values[capability.rawValue] = enabled
        if enabled { for dependency in capability.dependencies { set(dependency, enabled: true) } }
        else {
            for dependent in AssistantCapability.allCases where dependent.dependencies.contains(capability) { set(dependent, enabled: false) }
        }
    }
}
