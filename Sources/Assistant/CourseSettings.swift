import SwiftUI
import AppKit
import AssistantCore

struct CourseHistoryView: View {
    var channelFilter: String? = nil
    var initialCourseID: UUID? = nil
    @ObservedObject var store: Store
    @State private var selected: UUID?
    @State private var choosing = false
    @State private var deletionSelection: Set<UUID> = []
    @State private var tab = CommandLine.arguments.contains("--preview-course-qa") ? "课堂问答" : CommandLine.arguments.contains("--preview-course-transcript") ? "助教记录" : "课程笔记"
    @State private var note = NotebookSection.transcript
    @State private var questions = "已回答"
    @State private var recordView = CommandLine.arguments.contains("--preview-course-transcript") ? "课堂转写" : "处理记录"
    @State private var category = "全部"
    @State private var pickCategory = DropdownPreview.isOpen("category")
    /// Dev: --preview-course-qa opens the first course on 课堂问答 (screenshots).
    private func previewOpen() { if selected == nil, CommandLine.arguments.contains("--preview-course-qa") || CommandLine.arguments.contains("--preview-course-transcript"), let id = courses.first?.id { DispatchQueue.main.async { selected = id } } }
    private var courses: [CourseSession] { store.saved.courses.filter { channelFilter == nil || $0.channel == channelFilter } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let _ = previewOpen()
            if let id = selected, let course = courses.first(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    Button {
                        selected = nil
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("返回列表")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4.5)
                        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    
                    Text("频道 \(course.channel)").font(.system(size: 15, weight: .bold))
                    Text(course.started.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary)
                    
                    Spacer()
                    
                }
                HStack {
                    Spacer()
                    PillSegments(items: ["课程笔记", "课堂问答", "数据", "助教记录"].map { ($0, $0) }, selection: $tab)
                    Spacer()
                }
                if tab == "课程笔记" {
                    NotebookTabs(sections: NotebookSection.available(in: course).filter { $0 != .faq }, selection: $note)
                    ScrollView { NotebookContent(store: store, course: course, section: note, live: false).padding(6) }
                } else if tab == "课堂问答" {
                    PillSegments(items: [("已回答", "已回答"), ("未回答", "未回答")], selection: $questions)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if questions == "已回答" {
                                if course.answers.isEmpty { Text("本场暂无已回答的问题").foregroundStyle(AppTheme.textSecondary) }
                                ForEach(course.answers.reversed()) { answer in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(answer.question).font(.system(size: 15, weight: .medium))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(answer.answer).font(.system(size: 13)).textSelection(.enabled)
                                            if let s = answer.sources, !s.isEmpty { SourceLine(text: "依据：" + s) }
                                        }
                                        if let evidence = answer.spokenEvidence {
                                            Text("原话：" + evidence).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled)
                                            if let time = answer.spokenAt { Text(time.formatted(date: .omitted, time: .standard)).font(.system(size: 11)).foregroundStyle(AppTheme.textHint) }
                                        }
                                        Text("\(answer.actor ?? "助教") · \(answer.date.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).settingsCard(cornerRadius: 10, padding: 12)
                                }
                            } else {
                                if course.unanswered.isEmpty { Text("本场未遗留未回答问题").foregroundStyle(AppTheme.textSecondary) }
                                ForEach(Array(course.unanswered.enumerated()), id: \.offset) { _, text in Text(text).font(.system(size: 13)).padding(10) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if tab == "数据" {
                    ScrollView { CourseDataView(store: store, course: course, live: false) }
                        .task(id: course.id) { store.scheduleCourseDataSync(course.id) }
                } else {
                    let records = (course.operations ?? []).filter { $0.kind != "question" }
                    PillSegments(items: [("处理记录", "处理记录"), ("课堂转写", "课堂转写")], selection: $recordView)
                    if recordView == "课堂转写" {
                        ScrollView { TranscriptRecords(course: course).padding(6) }
                    } else {
                    HStack {
                        let categories = ["全部"] + Array(Set(records.map(\.categoryTitle))).sorted()
                        DropdownField(prefix: "类型", value: category, accessibilityName: "类型", isOpen: pickCategory, compact: true) { DropdownGate.toggle($pickCategory) }
                            .background(DropdownPanelAnchor(isPresented: $pickCategory, items: categories.map { title in
                                DropdownItem(id: title, title: title, selected: category == title) { category = title }
                            }))
                        Spacer()
                    }
                    OperationHistoryTable(records: records.filter { category == "全部" || $0.categoryTitle == category })
                    }
                }
            } else {
                HStack {
                    if !store.lastDeletedCourses.isEmpty { Button("撤销删除") { store.undoDeleteCourses() } }
                    Spacer()
                    if choosing {
                        Button("删除课程记录 (\(deletionSelection.count))", role: .destructive) {
                            store.deleteCourses(deletionSelection); deletionSelection = []; choosing = false
                        }.disabled(deletionSelection.isEmpty)
                            .buttonStyle(.plain).foregroundStyle(AppTheme.danger.opacity(deletionSelection.isEmpty ? 0.4 : 1)).font(.system(size: 13, weight: .medium))   // red text, never the default button
                    }
                    Button(choosing ? "取消" : "选择") { choosing.toggle(); deletionSelection = [] }
                        .buttonStyle(.plain).foregroundStyle(AppTheme.accent).font(.system(size: 13, weight: .medium))
                        .disabled(courses.isEmpty)
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if courses.isEmpty {
                            VStack(spacing: 8) {
                                Text("暂无课程记录").font(.system(size: 15, weight: .semibold))
                                Text("上课并下课后，课堂笔记、转写与问答记录将自动归档于此")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(40)
                        }
                        ForEach(courses.sorted { $0.started > $1.started }) { course in
                            Button {
                                if choosing {
                                    if deletionSelection.contains(course.id) { deletionSelection.remove(course.id) } else { deletionSelection.insert(course.id) }
                                } else { selected = course.id; note = .transcript; tab = "课程笔记"; category = "全部" }
                            } label: {
                                HStack(spacing: 14) {
                                    if choosing { Image(systemName: deletionSelection.contains(course.id) ? "checkmark.square.fill" : "square").foregroundStyle(AppTheme.accent) }
                                    ZStack {
                                        Color.clear.frame(width: 28, height: 44)
                                        Image(systemName: "video.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text("频道 \(course.channel)").font(.system(size: 15, weight: .semibold))
                                            if course.id == store.currentCourseID {
                                                StatusTag(text: "进行中", color: AppTheme.success, isLive: true)
                                            }
                                        }
                                        HStack(spacing: 6) {
                                            Text(course.started.formatted(date: .abbreviated, time: .shortened))
                                                .font(.system(size: 13))
                                                .foregroundStyle(AppTheme.textSecondary)
                                            if course.startTimeVerified != true {
                                                Text("·").foregroundStyle(AppTheme.textHint)
                                                Text("接入时间").font(.system(size: 11)).foregroundStyle(AppTheme.textHint)
                                            }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.textHint)
                                }
                                .padding(14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(choosing && course.id == store.currentCourseID)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.cardFill)
                            )
                        }
                    }
                }
            }
        }.padding(28).onAppear { if let initialCourseID { selected = initialCourseID } }
    }
}

struct OperationHistoryTable: View {
    var records: [OperationRecord]
    var body: some View {
        Table(records.sorted { $0.time > $1.time }) {
            TableColumn("时间") { row in Text(row.time.formatted(date: .omitted, time: .standard)).monospacedDigit() }.width(65)
            TableColumn("类型") { row in Text(row.categoryTitle) }.width(75)
            TableColumn("内容") { row in Text(row.displayContent).lineLimit(2).help(row.displayContent) }.width(min: 140, ideal: 220, max: .infinity)
            TableColumn("处理人") { row in Text(row.actor) }.width(65)
            TableColumn("结果") { row in Text(row.resultTitle).lineLimit(1).help(row.answer) }.width(85)
        }.overlay { if records.isEmpty { Text("暂无助教记录").foregroundStyle(AppTheme.textSecondary) } }
    }
}

struct ExerciseList: View {
    @ObservedObject var store: Store
    var course: CourseSession
    var canSend: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if (course.exercises ?? []).isEmpty { Text("暂无练习题").foregroundStyle(AppTheme.textSecondary) }
            ForEach(course.exercises ?? []) { exercise in
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise.question).font(.system(size: 15, weight: .medium))
                    ForEach(Array(exercise.options.enumerated()), id: \.offset) { i, option in Text("\(String(UnicodeScalar(65+i)!)). \(option)").font(.system(size: 13)) }
                    Text("参考答案：" + exercise.correctIndices.map { String(UnicodeScalar(65+$0)!) }.joined(separator: "、")).font(.system(size: 13, weight: .medium))
                    Text(exercise.explanation).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary)
                    if canSend {
                        ExerciseSendControl(store: store, exercise: exercise)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).modifier(BigCardItem())
            }
        }
    }
}

struct RecordingControls: View {
    @ObservedObject var store: Store
    @ObservedObject var voice: VoiceSession
    
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if voice.active {
                    WaveformVisualizer(active: true, barCount: 4, color: AppTheme.danger)
                    Text("实时语音识别中 · \(voice.phase)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppTheme.danger)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text("实时讲课记录")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            
            Spacer()
            
            // No manual 开始/停止记录: recording starts automatically in class when speech recognition is configured.
            if store.currentCourseID != nil {
                Button("结束本场课程") {
                    store.stop()
                }
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(voice.active ? AppTheme.danger.opacity(0.06) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(voice.active ? AppTheme.danger.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ExerciseSendControl: View {
    @ObservedObject var store: Store
    var exercise: Exercise
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button { store.sendExercise(exercise) } label: {
                HStack(spacing: 6) {
                    if store.sendingExercises.contains(exercise.id) { ProgressView().controlSize(.mini) }
                    Text(exercise.sentAt != nil ? "已发送" : store.sendingExercises.contains(exercise.id) ? "发送中…" : store.exerciseSendErrors[exercise.id] == nil ? "发送题目" : "重试发送")
                }
            }.buttonStyle(SmallAccentButtonStyle())
                .disabled(exercise.sentAt != nil || store.sendingExercises.contains(exercise.id))
            if let error = store.exerciseSendErrors[exercise.id], exercise.sentAt == nil {
                Text(error).font(.caption).foregroundStyle(AppTheme.danger).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
