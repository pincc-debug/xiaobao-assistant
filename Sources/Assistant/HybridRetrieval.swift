import Foundation
import CryptoKit
import AssistantCore

/// Content-addressed cache: source text and credentials are never persisted here.
actor RetrievalIndex {
    static let shared = RetrievalIndex()
    let url: URL
    private var vectors: [String: [Double]] = [:]
    private var pending: [String: Task<[[Double]], Error>] = [:]
    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/retrieval-v1.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode([String:[Double]].self, from: data) { vectors = stored }
    }
    func cached(_ texts: [String]) -> [[Double]?] { texts.map { vectors[Self.key($0)] } }
    static func key(_ text: String) -> String {
        SHA256.hash(data: Data(("text-embedding-v4:1024:" + text).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func embed(_ texts: [String], using fetch: @escaping ([String]) async throws -> [[Double]]) async throws -> [[Double]] {
        let missing = Array(Set(texts.filter { vectors[Self.key($0)] == nil })).sorted()
        for start in stride(from: 0, to: missing.count, by: 10) {
            try Task.checkCancellation()
            let batch = Array(missing[start..<min(start + 10, missing.count)])
            let batchKey = Self.key(batch.joined(separator: "\u{0}"))
            let task: Task<[[Double]], Error>
            if let existing = pending[batchKey] { task = existing }
            else { task = Task { try await fetch(batch) }; pending[batchKey] = task }
            do {
                let result = try await task.value
                guard result.count == batch.count, result.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isFinite) && $0.contains(where: { $0 != 0 }) }), Set(result.map(\.count)).count == 1 else { throw AppError.message("检索向量格式无效") }
                for (text, vector) in zip(batch, result) { vectors[Self.key(text)] = vector }
                pending[batchKey] = nil
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(vectors).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { pending[batchKey] = nil; throw error }
        }
        return try texts.map { guard let value = vectors[Self.key($0)] else { throw AppError.message("检索索引未就绪") }; return value }
    }
}

extension ModelsClient {
    func embeddings(_ texts: [String]) async throws -> [[Double]] {
        if let embeddingOverride { return try await embeddingOverride(texts) }
        let result = try await Self.post(URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings")!, key: dashKey, body: ["model":"text-embedding-v4", "input":texts, "dimensions":1024, "encoding_format":"float"])
        guard let data = result["data"] as? [[String:Any]], data.count == texts.count else { throw AppError.message("检索向量返回无效") }
        var ordered = Array<[Double]?>(repeating: nil, count: texts.count)
        for row in data {
            guard let i = row["index"] as? Int, ordered.indices.contains(i), ordered[i] == nil, let vector = row["embedding"] as? [Double], vector.count == 1024 else { throw AppError.message("检索向量返回无效") }
            ordered[i] = vector
        }
        return ordered.compactMap { $0 }
    }
    func rerank(_ question: String, passages: [Passage]) async throws -> [Int] {
        if let rerankOverride { return try await rerankOverride(question, passages) }
        let result = try await Self.post(URL(string: "https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank")!, key: dashKey, body: ["model":"gte-rerank-v2", "input":["query":String(question.prefix(2000)), "documents":passages.map { $0.title + "\n" + $0.text }], "parameters":["top_n":min(6, passages.count), "return_documents":false]])
        guard let output = result["output"] as? [String:Any], let rows = output["results"] as? [[String:Any]] else { throw AppError.message("检索排序返回无效") }
        let indices = rows.compactMap { $0["index"] as? Int }
        guard !indices.isEmpty, indices.count == rows.count, Set(indices).count == indices.count, indices.allSatisfy({ passages.indices.contains($0) }) else { throw AppError.message("检索排序返回无效") }
        return indices
    }
    func prepareKnowledge(_ library: KnowledgeBase) async throws {
        guard !dashKey.isEmpty || embeddingOverride != nil else { return }
        _ = try await retrievalIndex.embed(Knowledge.chunks(in: library).map { $0.title + "\n" + $0.text }, using: embeddings)
    }
    func retrieve(_ question: String, library: KnowledgeBase, trace: (@MainActor (String, [String:Any]) -> Void)?) async throws -> [Passage] {
        let chunks = Knowledge.chunks(in: library)
        guard !chunks.isEmpty else { return [] }
        let lexical = Knowledge.rank(question, passages: chunks, limit: 20)
        var rankings = [lexical]
        if !dashKey.isEmpty || embeddingOverride != nil {
            do {
                let texts = chunks.map { $0.title + "\n" + $0.text }
                let vectors = await retrievalIndex.cached(texts)
                if vectors.contains(where: { $0 == nil }) {
                    await trace?("retrieval_fallback", ["reason":"部分资料正在建立索引，先结合关键词与课堂上下文查找"])
                }
                let indexed = chunks.indices.filter { vectors[$0] != nil }
                let query = indexed.isEmpty ? [] : try await embeddings([String(question.prefix(2000))])
                let q = query.first ?? []
                guard indexed.allSatisfy({ vectors[$0]!.count == q.count }) else { throw AppError.message("检索向量维度不一致") }
                let semantic = indexed.sorted { Knowledge.cosine(q, vectors[$0]!) > Knowledge.cosine(q, vectors[$1]!) }.prefix(20).map { chunks[$0] }
                rankings.append(semantic)
                await trace?("semantic", ["count":semantic.count])
            } catch is CancellationError { throw CancellationError() }
            catch { await trace?("retrieval_fallback", ["reason":"语义检索不可用，使用关键词与课堂上下文", "error":error.localizedDescription]) }
        } else { await trace?("retrieval_fallback", ["reason":"未配置百炼密钥，使用关键词与课堂上下文"]) }
        var candidates = Knowledge.fuse(rankings, limit: 24)
        if candidates.count < 24 {
            for p in chunks where candidates.count < 24 && !candidates.contains(where: { $0.id == p.id }) { candidates.append(p) }
        }
        // Reserve recent live context even when its index has not yet caught up.
        let recent = Array(chunks.filter { $0.title == "本场课堂转写" }.suffix(2))
        for p in recent where !candidates.contains(where: { $0.id == p.id }) { candidates.append(p) }
        var chosen = Array(candidates.prefix(6))
        if !candidates.isEmpty, !dashKey.isEmpty || rerankOverride != nil {
            do {
                let order = try await rerank(question, passages: candidates)
                guard !order.isEmpty, Set(order).count == order.count, order.allSatisfy({ candidates.indices.contains($0) }) else { throw AppError.message("检索排序返回无效") }
                chosen = order.prefix(6).map { candidates[$0] }
            } catch is CancellationError { throw CancellationError() }
            catch { await trace?("retrieval_fallback", ["reason":"相关性排序不可用，使用合并结果", "error":error.localizedDescription]) }
        }
        for p in recent where !chosen.contains(where: { $0.id == p.id }) { chosen.append(p) }
        return chosen
    }
}

