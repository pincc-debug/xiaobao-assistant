import Foundation

/// The classifier has its own serial lane. Slow work uses bounded, per-issue lanes.
@MainActor final class ClassroomWorkQueue {
    struct Job {
        let id = UUID()
        let key: String
        let question: String
        let run: @MainActor () async -> Void
    }
    let limit: Int
    private var waiting: [Job] = []
    private var active: [String: (UUID, String, Task<Void, Never>)] = [:]
    var count: Int { waiting.count + active.count }
    var groups: [(String, String)] {
        var seen = Set<String>()
        return (active.map { ($0.key, $0.value.1) } + waiting.map { ($0.key, $0.question) }).filter { seen.insert($0.0).inserted }
    }
    init(limit: Int = 4) { self.limit = max(1, limit) }
    func enqueue(key: String, question: String, run: @escaping @MainActor () async -> Void) {
        waiting.append(Job(key:key,question:question,run:run)); pump()
    }
    func cancel() {
        waiting.removeAll()
        for entry in active.values { entry.2.cancel() }
        active.removeAll()
    }
    private func pump() {
        while active.count < limit, let index = waiting.firstIndex(where: { active[$0.key] == nil }) {
            let job = waiting.remove(at:index)
            let task = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                await job.run()
                guard let self, self.active[job.key]?.0 == job.id else { return }
                self.active.removeValue(forKey:job.key); self.pump()
            }
            active[job.key] = (job.id,job.question,task)
        }
    }
}
