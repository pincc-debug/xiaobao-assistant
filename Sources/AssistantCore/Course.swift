import Foundation
public struct SpeechSettings: Codable {
    public static let fixedModel = "qwen3-asr-flash-realtime"
    public static let fixedHost = "dashscope.aliyuncs.com"
    public static let fixedRegion = "cn-beijing"
    public var model = fixedModel
    public var autoRecord = false
    public init() {}
}
public struct CourseAnswer: Codable, Identifiable {
    public var id = UUID()
    public var question: String
    public var answer: String
    public var date = Date()
    public var actor: String?
    public var sourceMessageIDs: [String]?
    public var sources: String?
    public var spokenEvidence: String?
    public var spokenSegmentIDs: [UUID]?
    public var spokenAt: Date?
    public init(question: String, answer: String) { self.question = question; self.answer = answer }
}
public struct QuoteCard: Codable, Identifiable {
    public var id = UUID()
    public var title: String
    public var quote: String
    public var path: String
    public var sent = false
    public init(title: String, quote: String, path: String) { self.title = title; self.quote = quote; self.path = path }
}
public struct CourseSession: Codable, Identifiable {
    public var id = UUID()
    public var title: String
    public var channel: String
    public var started = Date()
    public var ended: Date?
    public var transcript = ""
    public var answers: [CourseAnswer] = []
    public var unanswered: [String] = []
    public var cards: [QuoteCard] = []
    public var recordingPath: String?
    /// 课程归档 outputs keyed by ArchiveOutput.rawValue (optional so older saved courses still decode).
    public var outputs: [String: String]?
    public var logDirectories: [String]?
    public var platformSessionID: String?
    public var startTimeVerified: Bool?
    public var events: [ClassroomMessage]?
    public var classroomIssues: [ClassroomIssue]?
    public var operations: [OperationRecord]?
    public var activities: [AssistantActivity]?
    public var interactions: [LiveInteraction]?
    public var exercises: [Exercise]?
    public var knowledgePoints: [GroundedPoint]?
    public var transcriptSegments: [TranscriptSegment]?
    public var notebookOffset: Int?
    public var notebookAnswerCount: Int?
    public var notebookError: String?
    public var knowledgeLibraryID: UUID?
    public var knowledgeDocumentID: UUID?
    public var quotes: [String]?
    public var publicLibraryIDs: [UUID]?
    public var candidatePreparationID: UUID?
    public var candidatePreparationUpdatedAt: Date?
    public var preparation: LessonPreparation?
    public var analytics: CourseAnalytics?
    public var publicChat: [PublicChatRecord]?

    public init(title: String, channel: String) { self.title = title; self.channel = channel }
}

/// 课程归档 sub-options, each toggleable; generated after class from the transcript with the default model.
public enum ArchiveOutput: String, CaseIterable, Identifiable, Codable {
    case questions = "生成题目", summary = "课程总结", keyPoints = "知识点总结", faq = "高频问答整理"
    case outline = "课程大纲", handout = "课后笔记稿", faqToKnowledge = "FAQ 补充"
    public var id: String { rawValue }
    public var title: String { self == .faqToKnowledge ? "知识点补充到知识库" : self == .questions ? "练习题及参考答案" : self == .handout ? "课后笔记" : rawValue }
    public var realtime: Bool { [.questions, .keyPoints, .faq, .faqToKnowledge].contains(self) }
    public var detail: String {
        switch self {
        case .questions: return "基于讲课转写实时生成随堂练习及解析"
        case .summary: return "提炼全场核心内容与主讲摘要"
        case .keyPoints: return "梳理本节课的知识要点清单"
        case .faq: return "汇总课堂问答记录，整理常见问题解答"
        case .outline: return "按讲课时间轴梳理课程章节与大纲"
        case .handout: return "整理可直接导出交付给学员的讲义笔记"
        case .faqToKnowledge: return "将本场验证的知识点自动沉淀入知识库"
        }
    }
    /// Writing into the knowledge base is opt-in; the rest default on.
    public var defaultEnabled: Bool { self != .faqToKnowledge }
    var key: String { "archive." + String(describing: self) }
    public var prompt: String {
        switch self {
        case .questions: return "写给学员做。题目只考课上讲过的内容，答案和解析分开写。根据课堂转写出 3-5 道练习题（含参考答案），只考讲过的内容。"
        case .summary: return "写给主讲复盘看。讲了什么、学员卡在哪、下节课要接上什么。用 150 字以内总结这节课讲了什么。"
        case .keyPoints: return "写给学员课后复习看。一条一个点，用学员听得懂的话。列出这节课的知识点，每条一行，以「- 」开头。"
        case .faq: return "写给学员看。问题用学员的原话，回答只依据课上的内容。根据课上的问答记录，合并相同问题，整理成「问：…\n答：…」列表。"
        case .outline: return "写给主讲备下一轮课用，按讲的顺序排，不展开细节。按讲课时间顺序列出课程大纲（知识点时间线），每条一行。"
        case .handout: return "写给没来上课的学员看，要能单独读懂；资料里有例子就保留例子，没有就不编。写一份可以直接发给学员的课后笔记，结构清晰，语气友好，不超过 600 字。"
        case .faqToKnowledge: return ""
        }
    }
}
extension CapabilitySelection {
    public func isEnabled(_ output: ArchiveOutput) -> Bool { values[output.key] ?? output.defaultEnabled }
    public mutating func set(_ output: ArchiveOutput, enabled: Bool) { values[output.key] = enabled }
}
