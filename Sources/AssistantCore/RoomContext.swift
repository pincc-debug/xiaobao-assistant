import Foundation

/// Budgets use serialized UTF-8 bytes, not a guessed tokens-per-character ratio.
/// The model's prompt/tools and output need additional room outside this input budget.
public enum RoomContext {
    public static let inputBudget = 64_000
    public static let resultBudget = 24_000
    public static func bytes(_ value: Any) -> Int {
        (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]).count) ?? Int.max
    }
    public static func message(_ item: RoomMessage) -> [String: Any] {
        ["id": item.id.uuidString, "role": item.role, "text": item.text, "date": item.date.ISO8601Format()]
    }
    public static func build(room: RoomConversation, results: [[String: Any]], courseContext: [String: Any] = [:]) -> [String: Any] {
        let latestSize = room.messages.last.map { bytes(message($0)) } ?? 0
        let availableResults = min(resultBudget, max(0, inputBudget - latestSize - bytes(courseContext) - 2_000))
        var keptResults: [[String: Any]] = []
        for result in results.reversed() {
            if bytes([result] + keptResults) > availableResults { break }
            keptResults.insert(result, at: 0)
        }
        var payload: [String: Any] = ["current_course":courseContext, "channel":room.channel, "messages":[], "recalled_messages":[], "results":keptResults,
                                     "history_count":room.messages.count, "omitted_messages":room.messages.count,
                                     "omitted_tool_results":results.count - keptResults.count]
        // Reserve space for relevant older messages; the current request is always whole.
        let recentBudget = max(40_500, inputBudget - bytes(payload) - 7_000)
        var recent: [RoomMessage] = []
        for item in room.messages.reversed() {
            let candidate = [item] + recent
            if bytes(candidate.map(message)) > recentBudget { break }
            recent = candidate
        }
        payload["messages"] = recent.map(message)
        payload["omitted_messages"] = room.messages.count - recent.count
        let recentIDs = Set(recent.map(\.id))
        let older = room.messages.filter { !recentIDs.contains($0.id) }
        let query = room.messages.last(where: { $0.role == "user" })?.text ?? ""
        let matches = search(query, messages: older)
        var recalled: [[String: Any]] = []
        for item in matches {
            var entry = message(item)
            entry["text"] = String(item.text.prefix(1800))
            entry["truncated"] = item.text.count > 1800
            var candidate = payload; candidate["recalled_messages"] = recalled + [entry]
            if bytes(candidate) <= inputBudget { recalled.append(entry) }
        }
        payload["recalled_messages"] = recalled
        // Tool results take priority over old conversation. No partial JSON or silent current-request truncation.
        while bytes(payload) > inputBudget, recent.count > 1 {
            recent.removeFirst(); payload["messages"] = recent.map(message)
            payload["omitted_messages"] = room.messages.count - recent.count
        }
        return payload
    }
    public static func search(_ query: String, messages: [RoomMessage]) -> [RoomMessage] {
        let documents = messages.map { Document(id:$0.id, name: $0.role == "user" ? "主讲聊天" : "助教聊天（非独立事实依据）", text:$0.text) }
        let passages = Knowledge.rank(query, passages:Knowledge.chunks(in:KnowledgeBase(name:"聊天",documents:documents)), limit:12)
        var ids = Set<UUID>()
        return passages.compactMap { passage in
            guard ids.insert(passage.documentID).inserted else { return nil }
            return messages.first { $0.id == passage.documentID }
        }.prefix(4).map { $0 }
    }
}
