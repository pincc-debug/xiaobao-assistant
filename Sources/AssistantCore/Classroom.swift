import Foundation

public struct ClassroomMessage: Codable, Identifiable, Equatable {
    public var id: String
    public var userID: String
    public var name: String
    public var text: String
    public var time: Date
    public var category: String?
    public init(id: String, userID: String, name: String, text: String, time: Date = Date()) {
        self.id = id; self.userID = userID; self.name = name; self.text = text; self.time = time
    }
}
public struct OperationRecord: Codable, Identifiable {
    public var id = UUID()
    public var question: String
    public var people: [String]
    public var answer: String
    public var time = Date()
    public var actor: String
    public var kind: String
    public var sourceMessageIDs: [String]
    public var sourceUserIDs: [String]
    /// Knowledge sources the answer was grounded on (labels from Knowledge.sourceLabels).
    public var sources: [String]?
    public init(question: String, people: [String] = [], answer: String, actor: String = "助教", kind: String = "question", sourceMessageIDs: [String] = [], sourceUserIDs: [String] = []) {
        self.question = question; self.people = people; self.answer = answer; self.actor = actor; self.kind = kind; self.sourceMessageIDs = sourceMessageIDs; self.sourceUserIDs = sourceUserIDs
    }
}
public struct TranscriptSegment: Codable, Identifiable {
    public var id = UUID()
    public var text: String
    public var time: Date
    public init(text: String, time: Date = Date()) { self.text = text; self.time = time }
}
public struct GroundedPoint: Codable, Identifiable {
    public var id = UUID()
    public var text: String
    public var evidence: String
    public init(text: String, evidence: String) { self.text = text; self.evidence = evidence }
}
public struct Exercise: Codable, Identifiable {
    public var id = UUID()
    public var question: String
    public var options: [String]
    public var correctIndices: [Int]
    public var explanation: String
    public var evidence: String
    public var platformID: String?
    public var sentAt: Date?
    public var platformSavePending: Bool?
    public init(question: String, options: [String], correctIndices: [Int], explanation: String, evidence: String) {
        self.question = question; self.options = options; self.correctIndices = correctIndices; self.explanation = explanation; self.evidence = evidence
    }
    public func isValid() -> Bool {
        !question.isEmpty && question.count <= 500 && (2...5).contains(options.count) && options.allSatisfy { !$0.isEmpty && $0.count <= 200 } && Set(options).count == options.count && !correctIndices.isEmpty && Set(correctIndices).count == correctIndices.count && correctIndices.allSatisfy { options.indices.contains($0) } && !explanation.isEmpty
    }
}

public struct AssistantActivity: Codable, Identifiable {
    public var id = UUID()
    public var time = Date()
    public var category: String
    public var title: String
    public var status: String
    public var source: String
    public var messageID: String?
    public init(category: String, title: String, status: String = "已完成", source: String = "", messageID: String? = nil) {
        self.category = category; self.title = title; self.status = status; self.source = source; self.messageID = messageID
    }
}
extension OperationRecord {
    public var categoryTitle: String {
        switch kind { case "question": return "答疑"; case "moderation": return "违规处置"; case "recap": return "欢迎总结"; case "quote": return "知识点发送"; case "material": return "资料发送"; case "viewed", "dismiss": return "提醒处理"; default: return "课堂操作" }
    }
}

extension OperationRecord {
    public var displayContent: String { ["recap", "quote", "material"].contains(kind) ? answer : question }
    public var resultTitle: String {
        switch kind {
        case "question": return "已回答"
        case "recap", "quote", "material": return "已发送"
        case "viewed": return "已查看"
        case "dismiss": return "已忽略"
        case "moderation":
            if answer.contains("解除禁言") { return "已解除禁言" }
            if answer.contains("解除踢出") { return "已解除踢出" }
            return answer.contains("禁言") ? "已禁言" : "已踢出"
        default: return "已完成"
        }
    }
}
