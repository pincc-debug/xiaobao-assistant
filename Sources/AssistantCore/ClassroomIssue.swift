import Foundation

/// Durable classroom work, distinct from a transient UI card or a successful tool call.
public struct ClassroomIssue: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case question, technical, feedback }
    public enum Status: String, Codable { case open, waiting, partial, resolved, dismissed }
    public enum Relation: String, Codable { case new, merge, followup, recovered }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var status: Status = .open
    public var messages: [ClassroomMessage] = []
    public var recoveredUserIDs: Set<String> = []
    public var updatedAt: Date
    public var lastReceipt: String?
    public var relatedIssueID: UUID?
    public var participants: Set<String> { Set(messages.map(\.userID)) }
    public var activeParticipants: Set<String> { participants.subtracting(recoveredUserIDs) }
    public init(id: UUID = UUID(), kind: Kind, title: String, at: Date = Date()) {
        self.id = id; self.kind = kind; self.title = title; self.updatedAt = at
    }
    public mutating func receive(_ message: ClassroomMessage, relation: Relation) throws {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        if relation == .recovered {
            guard kind != .question, participants.contains(message.userID) else { throw IssueError.invalidRecovery }
            recoveredUserIDs.insert(message.userID)
        } else {
            recoveredUserIDs.remove(message.userID)
        }
        messages.append(message); updatedAt = message.time
        if relation == .recovered { status = activeParticipants.isEmpty ? .resolved : .partial }
        else if relation == .followup || relation == .new || kind != .question { status = .open }
        // A duplicate question does not claim a previously sent answer was seen or understood.
    }
    public mutating func recordReceipt(kind: String, text: String) {
        lastReceipt = text; updatedAt = Date()
        switch kind {
        case "question": status = .waiting // Sent is not proof of understanding.
        case "viewed": if status == .open { status = .waiting }
        case "dismiss": status = .dismissed
        default: break
        }
    }
}
public enum IssueError: Error { case invalidRecovery }
