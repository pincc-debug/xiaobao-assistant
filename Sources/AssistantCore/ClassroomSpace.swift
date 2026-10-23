import Foundation

public enum LessonAssetStage: String, Codable, CaseIterable {
    case preparation = "备课", classroom = "课堂", review = "复盘"
    public var statusTitle: String { self == .classroom ? "上课中" : rawValue + "中" }
    public var groupTitle: String { self == .classroom ? "课堂记录" : rawValue }
}

public struct RoomSource: Codable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var text: String
    public var courseID: UUID?
    public init(id: String, title: String, text: String, courseID: UUID? = nil) {
        self.id = id; self.title = title; self.text = text; self.courseID = courseID
    }
}
public struct RoomMessage: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var lessonID: UUID?
    public var assetIDs: [UUID]?
    public var role: String
    public var text: String
    public var sources: [RoomSource] = []
    public var thinking: RoomThinking?
    public init(role: String, text: String, sources: [RoomSource] = [], lessonID: UUID? = nil) {
        self.lessonID = lessonID
        self.role = role; self.text = text; self.sources = sources
    }
}
/// User-visible progress and tool preambles, never private model reasoning or tool arguments.
public struct RoomThinking: Codable, Identifiable {
    public var id: UUID
    public var messageID: UUID
    public var started = Date()
    public var finished: Date?
    public var status = "思考中"
    public var steps: [RoomThinkingStep] = []
    public var preview = ""
    public init(id: UUID, messageID: UUID) { self.id = id; self.messageID = messageID }
}
public struct RoomThinkingStep: Codable, Identifiable {
    public var id = UUID()
    public var title: String
    public var detail: String
    public init(title: String, detail: String = "") { self.title = title; self.detail = detail }
}
public struct RoomMaterial: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public var title: String
    public var text: String
    public var lessonID: UUID?
    public var kind: String
    public var sources: [RoomSource]
    public var stage: LessonAssetStage?
    public var exercise: Exercise?
    public var updatedAt: Date?
    public var questionSaveState: String?
    public var priorQuestionIDs: [String]?
    public var documentID: UUID?
    public var libraryID: UUID?
    public init(title: String, text: String, kind: String, sources: [RoomSource], lessonID: UUID? = nil) {
        self.lessonID = lessonID
        self.title = title; self.text = text; self.kind = kind; self.sources = sources
    }
}
public struct RoomConversation: Codable, Identifiable {
    public var id: String { channel }
    public var channel: String
    public var name: String?
    public var preparations: [LessonPreparation]?
    public var messages: [RoomMessage] = []
    public var materials: [RoomMaterial] = []
    public var libraryIDs: [UUID] = []
    public init(channel: String) { self.channel = channel }
}
