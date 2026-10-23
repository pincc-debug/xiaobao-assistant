import Foundation
import AssistantCore

extension Store {
    func deleteCourses(_ ids: Set<UUID>) {
        let removed = saved.courses.filter { ids.contains($0.id) && $0.id != currentCourseID }
        guard !removed.isEmpty else { return }
        do {
            let directory = file.url.deletingLastPathComponent().appendingPathComponent("DeletedCourses")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let backup = directory.appendingPathComponent(UUID().uuidString + ".json")
            try JSONEncoder().encode(removed).write(to: backup, options: .atomic)
            var updated = saved
            let removedIDs = Set(removed.map(\.id)); updated.courses.removeAll { removedIDs.contains($0.id) }
            try file.write(updated)
            saved = updated; lastDeletedCourses = removed; deletedCoursesBackup = backup
        } catch { self.error = "删除失败：" + error.localizedDescription }
    }
    func undoDeleteCourses() {
        guard !lastDeletedCourses.isEmpty else { return }
        do {
            var updated = saved
            let existing = Set(updated.courses.map(\.id))
            updated.courses += lastDeletedCourses.filter { !existing.contains($0.id) }
            updated.courses.sort { $0.started > $1.started }
            try file.write(updated); saved = updated
            lastDeletedCourses = []
            if let deletedCoursesBackup { try? FileManager.default.removeItem(at: deletedCoursesBackup) }
            deletedCoursesBackup = nil
        } catch { self.error = "恢复失败：" + error.localizedDescription }
    }
}
