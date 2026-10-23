import Foundation

public enum PetAction: Int, CaseIterable, Codable {
    case idle, listening, thinking, typing, searching, puzzled, alert, done
    public var title: String { ["待机", "聆听", "思考", "打字", "找资料", "疑惑", "提醒", "完成"][rawValue] }
}
public struct Document: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var text: String
    public var sourceKind: String?
    public var courseID: UUID?
    public var recordedAt: Date?
    public init(id: UUID = UUID(), name: String, text: String, sourceKind: String? = nil, courseID: UUID? = nil, recordedAt: Date? = nil) {
        self.id = id; self.name = name; self.text = text
        self.sourceKind = sourceKind; self.courseID = courseID; self.recordedAt = recordedAt
    }
}
public struct KnowledgeBase: Identifiable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var documents: [Document]
    public init(id: UUID = UUID(), name: String, documents: [Document] = []) { self.id = id; self.name = name; self.documents = documents }
}
public struct Preferences: Codable {
    public var nickname = "小保"
    public var pet = "female"
    public var style = "回答尽量一两句，用短句，不铺垫。"
    public var appID = ""
    public var userID = ""
    public var model = "qwen-plus"
    public var region = "cn-beijing"
    /// system | light | dark
    public var appearance = "system"
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case nickname, pet, style, appID, userID, model, region, appearance
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? "小保"
        pet = try c.decodeIfPresent(String.self, forKey: .pet) ?? "female"
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "回答尽量一两句，用短句，不铺垫。"
        appID = try c.decodeIfPresent(String.self, forKey: .appID) ?? ""
        userID = try c.decodeIfPresent(String.self, forKey: .userID) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "qwen-plus"
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "cn-beijing"
        appearance = try c.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
    }
}
public struct SavedState: Codable {
    public var preferences = Preferences()
    public var libraries: [KnowledgeBase] = []
    public var providers: [ModelProvider] = []
    public var defaultProviderID: UUID?
    public var capabilities = CapabilitySelection()
    public var speech = SpeechSettings()
    public var courses: [CourseSession] = []
    public var rooms: [RoomConversation] = []
    public var preparationShortcuts: [PreparationShortcut] = []
    /// Knowledge bases used for live answers. nil = never chosen (defaults to the first library).
    public var selectedLibraryIDs: [UUID]?
    public init() {}
    private enum CodingKeys: String, CodingKey { case preferences, libraries, providers, defaultProviderID, speech, courses, capabilities, selectedLibraryIDs, libraryID, rooms, preparationShortcuts }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        libraries = try c.decodeIfPresent([KnowledgeBase].self, forKey: .libraries) ?? []
        providers = try c.decodeIfPresent([StoredModelProvider].self, forKey: .providers)?.compactMap(\.value) ?? []
        defaultProviderID = try c.decodeIfPresent(UUID.self, forKey: .defaultProviderID)
        if !providers.contains(where: { $0.id == defaultProviderID }) { defaultProviderID = providers.first?.id }
        capabilities = try c.decodeIfPresent(CapabilitySelection.self, forKey: .capabilities) ?? CapabilitySelection()
        speech = try c.decodeIfPresent(SpeechSettings.self, forKey: .speech) ?? SpeechSettings()
        courses = try c.decodeIfPresent([CourseSession].self, forKey: .courses) ?? []
        rooms = try c.decodeIfPresent([RoomConversation].self, forKey: .rooms) ?? []
        preparationShortcuts = try c.decodeIfPresent([PreparationShortcut].self, forKey: .preparationShortcuts) ?? []
        if let ids = try c.decodeIfPresent([UUID].self, forKey: .selectedLibraryIDs) { selectedLibraryIDs = ids }
        else if let legacy = try c.decodeIfPresent(UUID.self, forKey: .libraryID) { selectedLibraryIDs = [legacy] }  // migrate old single choice
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preferences, forKey: .preferences); try c.encode(libraries, forKey: .libraries); try c.encode(providers, forKey: .providers)
        try c.encodeIfPresent(defaultProviderID, forKey: .defaultProviderID); try c.encode(capabilities, forKey: .capabilities); try c.encode(speech, forKey: .speech)
        try c.encode(preparationShortcuts, forKey: .preparationShortcuts)
        try c.encode(rooms, forKey: .rooms); try c.encode(courses, forKey: .courses); try c.encodeIfPresent(selectedLibraryIDs, forKey: .selectedLibraryIDs)
    }
    /// Merges the chosen libraries into one searchable base (documents keep their ids).
    public static func merged(_ libraries: [KnowledgeBase]) -> KnowledgeBase? {
        guard !libraries.isEmpty else { return nil }
        if libraries.count == 1 { return libraries[0] }
        return KnowledgeBase(name: libraries.map(\.name).joined(separator: "、"), documents: libraries.flatMap(\.documents))
    }
}
public struct StateFile {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func read() throws -> SavedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SavedState() }
        return try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
    }
    public func write(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
public struct Passage: Identifiable {
    public let id: String
    public let documentID: UUID
    public let title: String
    public let text: String
    public let sourceKind: String?
    public let courseID: UUID?
    public let recordedAt: Date?
}
public enum Knowledge {
    /// Display labels for the passages an answer was grounded on: 「《文档》」 or 「FAQ · 问题」 (FAQ chunks start with 问：/Q:). Deduped, order kept.
    public static func sourceLabels(_ passages: [Passage]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for p in passages {
            let t = p.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var label = "《\(p.title)》"
            if let r = t.range(of: "^(?:问[：:]|Q[：:])\\s*", options: .regularExpression) {
                let q = t[r.upperBound...].split(separator: "\n", maxSplits: 1).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                if !q.isEmpty { label = "FAQ · " + q }
            }
            if seen.insert(label).inserted { out.append(label) }
        }
        return out
    }
    /// 「依据：…」 or nil when there is no source.
    public static func sourceLine(_ labels: [String]) -> String? { labels.isEmpty ? nil : "依据：" + labels.joined(separator: "、") }
    public static func chunks(in library: KnowledgeBase) -> [Passage] {
        var output: [Passage] = []
        for doc in library.documents {
            // Keep FAQ question/answer pairs together; ordinary prose follows sentence boundaries.
            let faq = doc.text.range(of: "(?m)^\\s*(?:问[：:]|Q[：:])", options: .regularExpression) != nil
            let units: [String]
            if faq {
                units = doc.text.replacingOccurrences(of: "(?m)(?=^\\s*(?:问[：:]|Q[：:]))", with: "\u{001E}", options: .regularExpression).components(separatedBy: "\u{001E}")
            } else {
                units = doc.text.replacingOccurrences(of: "([。！？!?\\n])", with: "$1\u{001E}", options: .regularExpression).components(separatedBy: "\u{001E}")
            }
            var buffer = "", ordinal = 0
            func emit() {
                let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { output.append(Passage(id: "\(doc.id)_\(ordinal)", documentID: doc.id, title: doc.name, text: text, sourceKind: doc.sourceKind, courseID: doc.courseID, recordedAt: doc.recordedAt)); ordinal += 1 }
                buffer = ""
            }
            for unit in units where !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !buffer.isEmpty && (faq || buffer.count + unit.count > 900) { emit() }
                // Oversized units repeat the question as context instead of orphaning the answer.
                if unit.count > 1800 {
                    let chars = Array(unit), prefix = faq ? String(unit.prefix(300)) + "\n" : ""
                    for start in stride(from: 0, to: chars.count, by: 1200) {
                        buffer = prefix + String(chars[start..<min(start + 1400, chars.count)]); emit()
                    }
                } else { buffer += unit }
            }
            emit()
        }
        return output
    }
    public static func retrieve(_ query: String, in library: KnowledgeBase) -> [Passage] {
        rank(query, passages: chunks(in: library), limit: 6)
    }
    public static func rank(_ query: String, passages: [Passage], limit: Int) -> [Passage] {
        let normalized = Array(query.lowercased().filter { $0.isLetter || $0.isNumber })
        guard !normalized.isEmpty else { return [] }
        var grams = Set<String>()
        for length in 1...min(normalized.count, 8) where length > 1 || normalized.count == 1 {
            for offset in 0...(normalized.count - length) { grams.insert(String(normalized[offset..<(offset + length)])) }
        }
        let bodies = passages.map { ($0.title + $0.text).lowercased().filter { $0.isLetter || $0.isNumber } }
        let weights = Dictionary(uniqueKeysWithValues: grams.map { term in
            (term, log(1 + Double(passages.count) / Double(1 + bodies.filter { $0.contains(term) }.count)) * Double(term.count * term.count))
        })
        let scores = bodies.map { body in grams.reduce(0.0) { $0 + (body.contains($1) ? weights[$1, default: 0] : 0) } }
        return passages.indices.filter { scores[$0] > 0 }.sorted { scores[$0] == scores[$1] ? passages[$0].id < passages[$1].id : scores[$0] > scores[$1] }.prefix(limit).map { passages[$0] }
    }
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        let norm = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
        return norm > 0 ? zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } / norm : -1
    }
    public static func fuse(_ rankings: [[Passage]], limit: Int) -> [Passage] {
        var scores: [String:Double] = [:], items: [String:Passage] = [:]
        for ranking in rankings {
            var seen = Set<String>()
            for (i, p) in ranking.enumerated() where seen.insert(p.id).inserted {
                scores[p.id, default: 0] += 1 / Double(60 + i + 1); items[p.id] = p
            }
        }
        return items.values.sorted { scores[$0.id] == scores[$1.id] ? $0.id < $1.id : scores[$0.id, default: 0] > scores[$1.id, default: 0] }.prefix(limit).map { $0 }
    }
    public static func validatedAnswer(_ result: [String: Any], passages: [Passage]) -> String? {
        guard result["answerable"] as? Bool == true, let answer = result["answer"] as? String,
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, answer.count <= 2000,
              let sources = result["source_ids"] as? [String], !sources.isEmpty,
              sources.allSatisfy({ key in passages.contains { $0.id == key } }) else { return nil }
        let evidence = passages.filter { sources.contains($0.id) }.map(\.text).joined(separator: "\n")
        let regex = try! NSRegularExpression(pattern: "[0-9]+(?:\\.[0-9]+)?")
        let ns = answer as NSString
        guard regex.matches(in: answer, range: NSRange(location: 0, length: ns.length)).allSatisfy({ evidence.contains(ns.substring(with: $0.range)) }) else { return nil }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
public enum Decision {
    public static func category(_ answers: [String: Any]) -> (String, String)? {
        guard let item = answers["category"] as? [String: Any], let choice = item["choice"] as? String,
              ["question", "technical", "feedback", "chat", "blocked"].contains(choice) else { return nil }
        guard let confidence = item["confidence"] as? Double, confidence >= 0.6 else { return (choice == "blocked" ? "uncertain" : choice, "none") }
        let same = answers["same_as"] as? [String: Any] ?? [:]
        let group = (same["confidence"] as? Double ?? 0) >= 0.6 ? same["choice"] as? String ?? "none" : "none"
        return (choice, group)
    }
}

/// Decode the retired local provider only to discard it without losing courses or API services.
private struct StoredModelProvider: Decodable {
    let value: ModelProvider?
    private enum CodingKeys: String, CodingKey { case kind }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decodeIfPresent(String.self, forKey: .kind) == "本机 Codex" { value = nil }
        else { value = try ModelProvider(from: decoder) }
    }
}
