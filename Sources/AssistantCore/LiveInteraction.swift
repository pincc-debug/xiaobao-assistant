import Foundation

public struct InteractionSnapshot: Codable, Equatable {
    public var time = Date()
    public var count: Int
    public var correct: Int?
    public var options: [Int]
    public init(count: Int, correct: Int? = nil, options: [Int] = []) { self.count = count; self.correct = correct; self.options = options }
    public var signature: String { "\(count)|\(correct ?? -1)|\(options)" }
}
public struct InteractionAttendee: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}
public struct LiveInteraction: Codable, Identifiable {
    public enum Kind: String, Codable { case answer, checkin, notice, questionnaire, rush, timer
        public var title: String { switch self { case .answer: return "答题"; case .checkin: return "签到"; case .notice: return "公告"; case .questionnaire: return "问卷"; case .rush: return "抢答"; case .timer: return "倒计时" } }
        public var endTitle: String { switch self { case .answer: return "结束答题"; case .checkin: return "结束签到"; case .notice: return "撤下公告"; case .questionnaire: return "结束问卷"; case .rush: return "结束抢答"; case .timer: return "结束倒计时" } }
        /// 问卷 / 抢答 / 倒计时: the platform gives no live statistics, so the card only tracks running → ended.
        public var statusOnly: Bool { self == .questionnaire || self == .rush || self == .timer }
    }
    public var id = UUID()
    public var kind: Kind
    public var platformID: String
    public var content: String
    public var exerciseID: UUID?
    public var started = Date()
    public var deadline: Date?
    public var ended: Date?
    public var finalized = false
    /// Answer cards stay pinned until the lecturer publishes results on the card.
    public var resultPublished = false
    /// Timer was paused via Timer.stop; card stays until「结束倒计时」.
    public var timerPaused = false
    public var snapshots: [InteractionSnapshot] = []
    public var attendees: [InteractionAttendee] = []
    public var rosterComplete = false
    public var analysis = ""
    public var analysisSignature: String?
    public var analysisAt: Date?
    public var error: String?
    public var pinned: Bool { ended == nil || !finalized }
    public init(kind: Kind, platformID: String, content: String, exerciseID: UUID? = nil) {
        self.kind = kind; self.platformID = platformID; self.content = content; self.exerciseID = exerciseID
    }
    enum CodingKeys: String, CodingKey {
        case id, kind, platformID, content, exerciseID, started, deadline, ended, finalized
        case resultPublished, timerPaused, snapshots, attendees, rosterComplete
        case analysis, analysisSignature, analysisAt, error
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(Kind.self, forKey: .kind)
        platformID = try c.decode(String.self, forKey: .platformID)
        content = try c.decode(String.self, forKey: .content)
        exerciseID = try c.decodeIfPresent(UUID.self, forKey: .exerciseID)
        started = try c.decodeIfPresent(Date.self, forKey: .started) ?? Date()
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        ended = try c.decodeIfPresent(Date.self, forKey: .ended)
        finalized = try c.decodeIfPresent(Bool.self, forKey: .finalized) ?? false
        resultPublished = try c.decodeIfPresent(Bool.self, forKey: .resultPublished) ?? false
        timerPaused = try c.decodeIfPresent(Bool.self, forKey: .timerPaused) ?? false
        snapshots = try c.decodeIfPresent([InteractionSnapshot].self, forKey: .snapshots) ?? []
        attendees = try c.decodeIfPresent([InteractionAttendee].self, forKey: .attendees) ?? []
        rosterComplete = try c.decodeIfPresent(Bool.self, forKey: .rosterComplete) ?? false
        analysis = try c.decodeIfPresent(String.self, forKey: .analysis) ?? ""
        analysisSignature = try c.decodeIfPresent(String.self, forKey: .analysisSignature)
        analysisAt = try c.decodeIfPresent(Date.self, forKey: .analysisAt)
        error = try c.decodeIfPresent(String.self, forKey: .error)
    }
    public var summary: String {
        guard kind != .notice else { return ended == nil ? "已发布" : "已撤下" }
        guard !kind.statusOnly else {
            if kind == .timer, timerPaused, ended == nil { return "已暂停" }
            return ended == nil ? "进行中" : "已结束"
        }
        guard let data = snapshots.last else { return "等待数据" }
        if kind == .checkin { return "已签到 \(data.count) 人" }
        var text = "已答 \(data.count) 人"
        if data.count > 0, let correct = data.correct { text += " · 正确率 \(Int((Double(correct) / Double(data.count) * 100).rounded()))%" }
        return text
    }
}
public extension LiveInteraction {
    /// 问卷 / 抢答 / 倒计时 with a deadline end on their own once it passes.
    mutating func expireIfDue(now: Date = Date()) -> Bool {
        guard kind.statusOnly, ended == nil, let deadline, now >= deadline else { return false }
        ended = deadline; finalized = true; return true
    }
}
