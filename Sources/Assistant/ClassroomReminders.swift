import SwiftUI
import AssistantCore

struct ClassroomReminder: Identifiable {
    enum Destination: Equatable { case exercise(UUID), analysis(UUID) }
    var id = UUID()
    var courseID: UUID
    var destination: Destination
    var title: String
    var detail: String
}
extension Store {
    var currentReminders: [ClassroomReminder] { classroomReminders.filter { $0.courseID == currentCourseID } }
    func remind(_ destination: ClassroomReminder.Destination, title: String, detail: String, courseID: UUID) {
        guard currentCourseID == courseID else { return }
        if let i = classroomReminders.firstIndex(where: { $0.courseID == courseID && $0.destination == destination }) {
            classroomReminders[i].title = title; classroomReminders[i].detail = detail
        } else { classroomReminders.append(ClassroomReminder(courseID:courseID,destination:destination,title:title,detail:detail)) }
    }
    func openReminder(_ reminder: ClassroomReminder) {
        guard reminder.courseID == currentCourseID else { return }
        switch reminder.destination { case .exercise: requestedNotebookSection = .questions; case .analysis: requestedNotebookSection = .interactions }
        notebookNavigationPending = true
        setDetail(true)
        notebookNavigationID = UUID()
        classroomReminders.removeAll { $0.id == reminder.id }
    }
    func announceClassStarted() {
        guard connected, let id = currentCourseID, greetedCourses.insert(id).inserted else { return }
        flow("开课啦，我来帮你留意提问、整理重点。")
    }
}
struct ClassroomRemindersView: View {
    @ObservedObject var store: Store
    @State private var expandedExercises: Set<UUID> = []
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            ForEach(store.currentReminders) { reminder in
                VStack(alignment: .leading, spacing: 8) {
                HStack(alignment:.top,spacing:8) {
                    MessageTypeBadge(type: { if case .exercise = reminder.destination { return .exercise }; return .analysis }(), compact:true)
                    VStack(alignment:.leading,spacing:3) {
                        Text(reminder.title).font(.system(size:12,weight:.medium))
                        Text(reminder.detail).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength:2)
                    VStack(spacing:8) {
                        Button("查看") {
                            if case .exercise(let id) = reminder.destination {
                                if !expandedExercises.insert(id).inserted { expandedExercises.remove(id) }
                            } else { store.openReminder(reminder) }
                        }
                        Button("忽略") { store.classroomReminders.removeAll { $0.id == reminder.id } }.foregroundStyle(.secondary)
                    }.font(.system(size:11)).buttonStyle(.plain)
                }
                if case .exercise(let id) = reminder.destination,
                   let exercise = store.currentCourse?.exercises?.first(where: { $0.id == id }) {
                    if expandedExercises.contains(id) {
                        Text(exercise.question).font(.system(size: 12, weight: .medium))
                        ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                            Text("\(String(UnicodeScalar(65 + index)!)). \(option)").font(.system(size: 12))
                        }
                        Text("参考答案：" + exercise.correctIndices.map { String(UnicodeScalar(65 + $0)!) }.joined(separator: "、")).font(.system(size: 12))
                        Text(exercise.explanation).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    ExerciseSendControl(store: store, exercise: exercise)
                }
                }.padding(8)
            }
        }
    }
}


extension PendingMessage {
    /// The instructor's original words while 「正在处理指令…」 is showing.
    var commandEcho: String? {
        guard title == Store.commandProcessingTitle else { return nil }
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : "「" + text + "」"
    }
    var assistantVoiceTitle: String {
        if title.hasPrefix("我") || title.hasPrefix("开课啦") { return title }
        // Reply feed lines are factual (`已回复 昵称 · 问题`), not first-person assistant speech.
        if title == "已回复" || title.hasPrefix("已回复 ") || title.hasPrefix("已回复 ·") { return title }
        if title.hasPrefix("已") || title.hasPrefix("正在") { return "我" + title }
        if title == "处理失败" { return "我刚才没能处理完成" }
        if title.contains("分析已更新") { return "我已更新答题分析" }
        if title.contains("结果已更新") { return "我已整理好" + title.replacingOccurrences(of: "已更新", with: "") }
        return "我有一条更新：" + title
    }
}
