import Foundation
import AssistantCore

extension Store {
    static let builtinPreparationShortcuts: [PreparationShortcut] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "教学大纲", prompt: "请结合当前课程的讨论和关联资料，整理教学大纲，包括学习目标、知识点、案例与教学顺序，保存为本课文档。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "生成讲义", prompt: "请根据当前课程的讨论和关联资料生成学员讲义，包含知识点讲解与案例，保存为本课文档。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "课堂练习", prompt: "请围绕当前课程的知识点生成5道课堂练习，包含答案和解析，保存为本课答题卡草稿，不发送给学生。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "整理问答", prompt: "请结合当前课程的讨论和关联资料，整理常见问题与参考回答，保存为本课问答文档。")
    ]
    static let builtinReviewShortcuts: [PreparationShortcut] = [
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "课堂总结", prompt: "请根据本课实际课堂转写与记录整理课堂总结，保存为本课复盘文档。区分实际讲授内容与备课计划，缺失记录如实说明。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, name: "整理问答", prompt: "请整理本课实际课堂提问、回答与未解决问题，保留来源，保存为本课复盘问答文档。不要把建议答案当作老师实际回答。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, name: "答题分析", prompt: "请查看本课练习与互动记录，分析学生答题情况和薄弱知识点，保存为本课复盘文档。没有答题数据时如实说明，不推测学生表现。"),
        .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!, name: "教学改进", prompt: "请结合本课课堂转写、学生反馈与互动结果，整理有依据的教学改进建议，保存为本课复盘文档。区分观察事实与改进建议。")
    ]
    var preparationShortcuts: [PreparationShortcut] { Self.builtinPreparationShortcuts + saved.preparationShortcuts }
    func savePreparationShortcut(_ shortcut: PreparationShortcut) throws {
        guard !persistenceBlocked else { throw AppError.message("数据文件异常，请先恢复备份") }
        var value = shortcut
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.prompt = value.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, value.name.count <= 20, !value.prompt.isEmpty, value.prompt.count <= 12000 else {
            throw AppError.message("名称限20字，指令限12000字")
        }
        guard !Self.builtinPreparationShortcuts.contains(where: { $0.id == value.id }) else { return }
        var next = saved
        if let index = next.preparationShortcuts.firstIndex(where: { $0.id == value.id }) { next.preparationShortcuts[index] = value }
        else { next.preparationShortcuts.append(value) }
        try file.write(next); saved = next
    }
    func deletePreparationShortcut(_ id: UUID) throws {
        guard !persistenceBlocked else { throw AppError.message("数据文件异常，请先恢复备份") }
        var next = saved; next.preparationShortcuts.removeAll { $0.id == id }
        try file.write(next); saved = next
    }
    func renameClassroomItem(channel: String, lessonID: UUID?, title: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw AppError.message("名称限1至120字") }
        try commitRoom(channel) { room, state in
            if let lessonID {
                let pi = room.preparations?.firstIndex { $0.id == lessonID || $0.usedByCourseID == lessonID }
                let ci = state.courses.firstIndex { $0.channel == channel && $0.id == lessonID }
                guard pi != nil || ci != nil else { throw AppError.message("课程已不存在") }
                if let pi { room.preparations?[pi].title = title; room.preparations?[pi].updatedAt = Date() }
                if let ci { state.courses[ci].title = title }
            } else { room.name = title }
        }
    }
    func canDeleteClassroomItem(channel: String, lessonID: UUID?) -> Bool {
        if currentCourse?.channel == channel || ((connected || busy) && self.channel == channel) { return false }
        if roomRunIDs[channel] != nil { return false }
        return !room(channel).materials.contains { ($0.lessonID == lessonID || lessonID == nil) && (questionBankTasks[$0.id] != nil || savingQuestions.contains($0.id)) }
    }
    func deleteClassroomItem(channel: String, lessonID: UUID?) throws {
        guard !persistenceBlocked else { throw AppError.message("数据文件异常，请先恢复备份") }
        guard canDeleteClassroomItem(channel: channel, lessonID: lessonID) else { throw AppError.message("请先结束上课或等待任务完成") }
        var next = saved
        var ids = Set<UUID>()
        if let lessonID {
            ids.insert(lessonID)
            for plan in preparations(channel) where plan.id == lessonID || plan.usedByCourseID == lessonID {
                ids.insert(plan.id); if let used = plan.usedByCourseID { ids.insert(used) }
            }
            if let ri = next.rooms.firstIndex(where: { $0.channel == channel }) {
                next.rooms[ri].preparations?.removeAll { ids.contains($0.id) || $0.usedByCourseID.map(ids.contains) == true }
                next.rooms[ri].messages.removeAll { $0.lessonID.map(ids.contains) == true }
                next.rooms[ri].materials.removeAll { $0.lessonID.map(ids.contains) == true }
            }
            next.courses.removeAll { $0.channel == channel && ids.contains($0.id) }
        } else {
            ids.formUnion(next.courses.filter { $0.channel == channel }.map(\.id))
            ids.formUnion(preparations(channel).map(\.id))
            next.rooms.removeAll { $0.channel == channel }
            next.courses.removeAll { $0.channel == channel }
        }
        // Preserve a local recovery copy before atomically publishing the deletion.
        let backup = file.url.deletingLastPathComponent().appendingPathComponent("DeletedClassrooms")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try StateFile(url: backup.appendingPathComponent(UUID().uuidString + ".json")).write(saved)
        try file.write(next); saved = next
        for id in ids { dataSyncTasks[id]?.cancel(); dataSyncTasks[id] = nil; finalDataSyncTasks[id]?.cancel(); finalDataSyncTasks[id] = nil }
        if let selectedPreparationID, ids.contains(selectedPreparationID) { self.selectedPreparationID = nil }
        lastDeletedCourses.removeAll { $0.channel == channel && (lessonID == nil || ids.contains($0.id)) }
        roomErrors[channel] = nil
    }
}
