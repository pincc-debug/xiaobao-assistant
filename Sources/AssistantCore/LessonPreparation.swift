import Foundation

public struct LessonPreparation: Codable, Identifiable {
    public var id = UUID()
    public var contextDocumentID = UUID()
    public var createdAt = Date()
    public var updatedAt = Date()
    public var title: String
    public var audience = ""
    public var goals = ""
    public var notes = ""
    public var documents: [Document] = []
    public var exercises: [Exercise]?
    public var exerciseSources: [RoomSource]?
    public var libraryIDs: [UUID] = []
    public var confirmedAt: Date?
    public var usedByCourseID: UUID?
    public var knowledgeDocumentID: UUID?
    public var ready: Bool { confirmedAt != nil && usedByCourseID == nil }
    public init(title: String) { self.title = title }
    public var text: String {
        "课程：\(title)\n面向：\(audience)\n目标：\(goals)\n备课内容：\n\(notes)"
    }
}
public struct ClassroomLesson: Identifiable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var status: String
    public init(id:UUID,title:String,date:Date,status:String) { self.id=id; self.title=title; self.date=date; self.status=status }
}
