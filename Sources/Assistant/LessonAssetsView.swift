import SwiftUI
import AssistantCore

struct LessonAssetEditor: View {
    @ObservedObject var store: Store
    var channel: String
    @State var asset: RoomMaterial
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text(asset.exercise == nil ? "编辑文档" : "编辑答题卡").font(.system(size: 15, weight: .semibold))
            if asset.exercise != nil {
                TextField("题干",text:Binding(get:{asset.exercise!.question},set:{asset.exercise!.question=$0}))
                ForEach(asset.exercise!.options.indices,id:\.self) { index in
                    HStack {
                        Toggle("\(String(UnicodeScalar(65+index)!))",isOn:Binding(get:{asset.exercise!.correctIndices.contains(index)},set:{ on in
                            asset.exercise!.correctIndices.removeAll { $0 == index }; if on { asset.exercise!.correctIndices.append(index) }
                        })).toggleStyle(.checkbox).frame(width:50)
                        TextField("选项",text:Binding(get:{asset.exercise!.options[index]},set:{asset.exercise!.options[index]=$0}))
                    }
                }
                Text("勾选正确答案").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                TextEditor(text:Binding(get:{asset.exercise!.explanation},set:{asset.exercise!.explanation=$0})).font(.system(size:13)).frame(height:140)
            } else {
                TextField("文档名称",text:$asset.title)
                TextEditor(text:$asset.text).font(.system(size:13)).frame(height:280)
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.stopRed) }
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(ModernSecondaryButtonStyle(size: .regular)).keyboardShortcut(.cancelAction); Button("保存") {
                do {
                    if let e=asset.exercise {
                        _ = try store.createQuestionAsset(["asset_id":asset.id.uuidString,"question":e.question,"options":e.options,"correct_indices":e.correctIndices,"explanation":e.explanation,"evidence":e.evidence,"source_ids":asset.sources.map(\.id)],channel:channel,lessonID:asset.lessonID,stage:asset.stage ?? .review,sources:asset.sources)
                    } else { try store.updateDocumentAsset(asset,channel:channel) }
                    dismiss()
                } catch { self.error=error.localizedDescription }
            }.buttonStyle(ModernPrimaryButtonStyle(size: .regular)) }
        }.textFieldStyle(FilledFieldStyle()).padding(22).frame(width:560)
    }
}


private enum ClassroomAssetCategory: String, CaseIterable, Identifiable {
    case exercises = "陪练练习", answers = "课堂问答", points = "知识点", transcript = "口播原文"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .exercises: return AppTheme.segPractice
        case .answers: return AppTheme.segQA
        case .points: return AppTheme.segKP
        case .transcript: return AppTheme.segScript
        }
    }
}

struct LessonAssetsPanel: View {
    @ObservedObject var store: Store
    var channel: String
    var lessonID: UUID?
    var focusStage: LessonAssetStage? = nil
    var focusRequest = UUID()
    var onSelect: (UUID) -> Void
    @Binding var stage: LessonAssetStage
    @State private var editing: RoomMaterial?
    @State private var expandedAsset: UUID?
    @State private var expandedOutput: ArchiveOutput?
    @State private var expandedExercise: UUID?
    @State private var expandedAnswer: String?
    @State private var expandedPoint: String?
    @State private var expandedSegment: String?
    @State private var prepEditing: LessonPreparation?
    private var course: CourseSession? { store.roomCourses(channel).first { $0.id == lessonID } }
    private var assets: [RoomMaterial] { store.lessonConversation(channel, lessonID: lessonID).materials.filter { ($0.stage ?? .review) == stage } }
    private var recordedExercises: [Exercise] {
        (course?.exercises ?? []).filter { exercise in !assets.contains { $0.exercise?.id == exercise.id } }
    }
    private var prepDocuments: [RoomMaterial] { assets.filter { $0.exercise == nil } }
    private var prepQuestions: [RoomMaterial] { assets.filter { $0.exercise != nil } }
    private var plan: LessonPreparation? {
        guard let lessonID else { return nil }
        return store.preparationForLesson(lessonID, channel: channel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch stage {
            case .preparation: preparationContent
            case .classroom: classroomContent
            case .review: reviewContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: stage == .classroom ? .infinity : nil, alignment: .top)
        // 不在 onAppear 里写 stage：课堂记录与其它页布局不同，切 tab 会拆掉再建本视图，
        // onAppear 若再套 lessonAssetStage（已下课=复盘），会把用户刚点的「课堂记录」打回去。
        // 初始/聚焦由 CourseWorkbenchPanel 根据 focusRequest、lessonID 写入。
        .onChange(of: lessonID) { _, _ in
            expandedAsset = nil; expandedExercise = nil; expandedAnswer = nil; expandedPoint = nil; expandedSegment = nil; expandedOutput = nil
        }
        .sheet(item: $editing) { asset in LessonAssetEditor(store: store, channel: channel, asset: asset) }
        .sheet(item: $prepEditing) { value in PreparationEditor(store: store, channel: channel, plan: value) }
    }

    // MARK: - 备课

    @ViewBuilder private var preparationContent: some View {
        let docs = prepDocuments
        let questions = prepQuestions
        if let plan {
            VStack(alignment: .leading, spacing: 0) {
                Text("本场备课")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppTheme.textStrong)
                    .padding(.bottom, 10)
                ForEach(Array(plan.documents.prefix(4))) { document in
                    HStack(alignment: .top, spacing: 8) {
                        let kind = Self.docAvatar(for: document.name)
                        ReshapeGlyph(text: kind.text, image: kind.image, bg: AppTheme.badgeBg, fg: AppTheme.badgeFg)
                        Text((plan.title.isEmpty ? "" : plan.title + " · ") + document.name)
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.textBody)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { Rectangle().fill(AppTheme.borderDefault).frame(height: 1).opacity(plan.documents.first?.id == document.id ? 0 : 1) }
                }
                if plan.documents.isEmpty {
                    Text(plan.title.isEmpty ? "本节课未填写备课资料" : plan.title)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.textMuted)
                        .padding(.bottom, 4)
                }
                if plan.confirmedAt != nil {
                    SaveToKnowledgeDropdown(store: store, saved: store.preparationIsSaved(plan.id, channel: channel)) {
                        store.savePreparationToKnowledge(plan.id, channel: channel, libraryID: $0)
                    }
                    .padding(.top, 10)
                } else if plan.usedByCourseID == nil {
                    Button("编辑备课") { editingPrep() }
                        .buttonStyle(ModernPrimaryButtonStyle(size: .small))
                        .padding(.top, 10)
                }
            }
            .padding(12)
            .background(
                LinearGradient(colors: [AppTheme.bgHeaderTop, AppTheme.bgPanel], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.borderAccent, lineWidth: 1))
        } else {
            Text("本节课未备课")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.bgTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.borderDefault, lineWidth: 1))
        }

        ReshapeSectionCard(title: "文档", color: AppTheme.segPractice, count: docs.count) {
            VStack(spacing: 0) {
                ForEach(Array(docs.enumerated()), id: \.element.id) { index, asset in
                    VStack(alignment: .leading, spacing: 0) {
                        ReshapeListRow(title: asset.title, showsChevron: true, striped: index % 2 == 1) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                expandedAsset = expandedAsset == asset.id ? nil : asset.id
                            }
                        }
                        if expandedAsset == asset.id { assetDetail(asset) }
                    }
                }
            }.padding(.horizontal, 6).padding(.vertical, 4)
        }

        ReshapeSectionCard(title: "练习题", color: AppTheme.segQA, count: questions.count) {
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.element.id) { index, asset in
                    let tag = (asset.exercise?.correctIndices.count ?? 0) > 1 ? "多选" : "单选"
                    VStack(alignment: .leading, spacing: 0) {
                        ReshapeListRow(title: asset.exercise?.question ?? asset.title, tag: tag, striped: index % 2 == 1) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                expandedAsset = expandedAsset == asset.id ? nil : asset.id
                            }
                        }
                        if expandedAsset == asset.id { assetDetail(asset) }
                    }
                }
            }.padding(.horizontal, 6).padding(.vertical, 4)
        }
    }

    private func editingPrep() {
        if let lessonID, let plan = store.preparationForLesson(lessonID, channel: channel) {
            prepEditing = plan
        }
    }

    // MARK: - 课堂记录

    private func count(_ value: ClassroomAssetCategory) -> Int {
        switch value {
        case .exercises: return recordedExercises.count + assets.filter { $0.exercise != nil }.count
        case .points: return course?.knowledgePoints?.count ?? 0
        case .answers: return (course?.answers.count ?? 0) + (course?.unanswered.count ?? 0)
        case .transcript: return course?.transcriptSegments?.count ?? (course?.transcript.isEmpty == false ? 1 : 0)
        }
    }

    @ViewBuilder private var classroomContent: some View {
        let slices: [ReshapeDonut.Slice] = [
            .init(value: count(.exercises), color: AppTheme.segPractice, label: "陪练练习"),
            .init(value: count(.answers), color: AppTheme.segQA, label: "课堂问答"),
            .init(value: count(.points), color: AppTheme.segKP, label: "知识点"),
            .init(value: count(.transcript), color: AppTheme.segScript, label: "口播原文"),
        ]
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ReshapeDonut(slices: slices)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(slices) { slice in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(slice.color).frame(width: 7, height: 7)
                            Text(slice.label).font(.system(size: 10.5)).foregroundStyle(AppTheme.textBody)
                            Spacer(minLength: 0)
                            Text("\(slice.value)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(AppTheme.textStrong).monospacedDigit()
                        }
                    }
                }
            }
            .padding(12)
            .background(
                LinearGradient(colors: [AppTheme.bgHeaderTop, AppTheme.bgPanel, AppTheme.badgeBg.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.borderAccent, lineWidth: 1))

            if course == nil {
                Text("暂无课堂记录").font(.system(size: 12)).foregroundStyle(AppTheme.textMuted).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                // 四区均分剩余高度，头始终露在一屏；区内各自滚（对齐稿子仪表密度）
                VStack(spacing: 7) {
                    classroomSection(.exercises)
                    classroomSection(.answers)
                    classroomSection(.points)
                    classroomSection(.transcript)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func classroomSection(_ category: ClassroomAssetCategory) -> some View {
        ReshapeSectionCard(title: category.rawValue, color: category.color, count: count(category)) {
            ScrollView {
                VStack(spacing: 0) {
                    switch category {
                    case .exercises:
                        let all = recordedExercises + assets.compactMap(\.exercise)
                        ForEach(Array(all.prefix(12).enumerated()), id: \.offset) { index, exercise in
                            let tag = exercise.correctIndices.count > 1 ? "多选" : "单选"
                            VStack(alignment: .leading, spacing: 0) {
                                ReshapeListRow(title: exercise.question, tag: tag, striped: index % 2 == 1) {
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        expandedExercise = expandedExercise == exercise.id ? nil : exercise.id
                                    }
                                }
                                if expandedExercise == exercise.id {
                                    LessonExerciseContent(exercise: exercise, showsQuestion: false)
                                        .padding(.horizontal, 10).padding(.bottom, 10)
                                    if let course, course.id == store.currentCourseID {
                                        Button(exercise.sentAt == nil ? "发送答题卡" : "已发送") { store.sendExercise(exercise) }
                                            .buttonStyle(QuietFillButtonStyle())
                                            .disabled(exercise.sentAt != nil || store.sendingExercises.contains(exercise.id))
                                            .padding(.horizontal, 10).padding(.bottom, 8)
                                    }
                                }
                            }
                        }
                    case .answers:
                        ForEach(Array((course?.answers ?? []).prefix(12).enumerated()), id: \.element.id) { index, qa in
                            VStack(alignment: .leading, spacing: 0) {
                                ReshapeListRow(title: qa.question, tag: "已答", striped: index % 2 == 1) {
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        expandedAnswer = expandedAnswer == qa.id.uuidString ? nil : qa.id.uuidString
                                    }
                                }
                                if expandedAnswer == qa.id.uuidString {
                                    ChatMarkdown(text: qa.answer).padding(.horizontal, 10).padding(.bottom, 10)
                                }
                            }
                        }
                        ForEach(Array((course?.unanswered ?? []).prefix(8).enumerated()), id: \.offset) { index, question in
                            ReshapeListRow(title: question, tag: "未答", warn: true, striped: ((course?.answers.count ?? 0) + index) % 2 == 1)
                        }
                    case .points:
                        let points = course?.knowledgePoints ?? []
                        ForEach(Array(points.prefix(12).enumerated()), id: \.element.id) { index, point in
                            VStack(alignment: .leading, spacing: 0) {
                                ReshapeListRow(title: point.text, tag: "要点", striped: index % 2 == 1) {
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        expandedPoint = expandedPoint == point.id.uuidString ? nil : point.id.uuidString
                                    }
                                }
                                if expandedPoint == point.id.uuidString, !point.evidence.isEmpty {
                                    Text(point.evidence).font(.system(size: 12)).foregroundStyle(AppTheme.textMuted)
                                        .textSelection(.enabled)
                                        .padding(.horizontal, 10).padding(.bottom, 10)
                                }
                            }
                        }
                    case .transcript:
                        let segments = course?.transcriptSegments ?? []
                        ForEach(Array(segments.prefix(12).enumerated()), id: \.element.id) { index, segment in
                            VStack(alignment: .leading, spacing: 0) {
                                ReshapeListRow(title: segment.text, tag: "口播", striped: index % 2 == 1) {
                                    withAnimation(.easeOut(duration: 0.14)) {
                                        expandedSegment = expandedSegment == segment.id.uuidString ? nil : segment.id.uuidString
                                    }
                                }
                                if expandedSegment == segment.id.uuidString {
                                    Text(segment.time.formatted(date: .omitted, time: .standard))
                                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(AppTheme.textMuted)
                                        .padding(.horizontal, 10).padding(.bottom, 8)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 6).padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 复盘

    @ViewBuilder private var reviewContent: some View {
        // 头像槽：优先读 Resources/asset-*.png，没图时用旧的单字小方块兜底
        let entries: [(ArchiveOutput, String, String, Color, Color, String)] = [
            (.summary, "总", "asset-summary", AppTheme.badgeBg, AppTheme.badgeFg, "结论、补充和备课改动"),
            (.outline, "纲", "asset-outline", AppTheme.icoCyanBg, AppTheme.icoCyanFg, "章节和时间"),
            (.handout, "记", "asset-notes", AppTheme.icoPurpleBg, AppTheme.icoPurpleFg, "问答、口播要点、待办"),
        ]
        VStack(spacing: 10) {
            ForEach(entries, id: \.0) { output, glyph, image, bg, fg, fallbackDetail in
                let text = course?.outputs?[output.rawValue] ?? ""
                let has = !text.isEmpty
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        expandedOutput = expandedOutput == output ? nil : output
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            ReshapeGlyph(text: glyph, image: image, bg: bg, fg: fg, size: 40, radius: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(output.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppTheme.textStrong)
                                Text(has ? String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ") : fallbackDetail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text("›").font(.system(size: 18)).foregroundStyle(AppTheme.textFaint)
                        }
                        .padding(16)
                        if expandedOutput == output {
                            Group {
                                if has { ChatMarkdown(text: text) }
                                else { Text("暂无此产出").font(.system(size: 12)).foregroundStyle(AppTheme.textFaint) }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.bgTile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AppTheme.borderDefault, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // also surface other review materials if any
        let extras = assets.filter { $0.exercise == nil }
        if !extras.isEmpty {
            ReshapeSectionCard(title: "其他复盘文档", color: AppTheme.segKP, count: extras.count) {
                VStack(spacing: 0) {
                    ForEach(Array(extras.enumerated()), id: \.element.id) { index, asset in
                        ReshapeListRow(title: asset.title, striped: index % 2 == 1) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                expandedAsset = expandedAsset == asset.id ? nil : asset.id
                            }
                        }
                        if expandedAsset == asset.id { assetDetail(asset) }
                    }
                }.padding(.horizontal, 6).padding(.vertical, 4)
            }
        }
    }

    // MARK: - Shared detail

    @ViewBuilder private func assetDetail(_ asset: RoomMaterial) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let exercise = asset.exercise {
                LessonExerciseContent(exercise: exercise, showsQuestion: false)
                if !(stage == .preparation && course != nil), exercise.sentAt == nil {
                    Button("编辑") { editing = asset }.buttonStyle(QuietFillButtonStyle())
                }
            } else {
                ChatMarkdown(text: asset.text)
                if stage != .preparation || course == nil {
                    Button("编辑") { editing = asset }.buttonStyle(QuietFillButtonStyle())
                }
                SaveToKnowledgeDropdown(store: store, saved: store.roomMaterialSaved(asset)) {
                    store.saveRoomMaterial(asset.id, channel: channel, libraryID: $0)
                }
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
    }

}

extension LessonAssetsPanel {
    /// 备课资料行的头像：单字兜底 + 图片名（Resources/<image>.png）
    static func docAvatar(for name: String) -> (text: String, image: String) {
        if name.contains("大纲") { return ("纲", "asset-outline") }
        if name.contains("讲义") || name.contains("笔记") { return ("义", "asset-handout") }
        if name.contains("练习") || name.contains("题") { return ("练", "asset-exercise") }
        return ("档", "asset-document")
    }
}

// MARK: - Unified workbench（资产侧 / 数据侧由右侧栏切换）

struct CourseWorkbenchPanel: View {
    @ObservedObject var store: Store
    var channel: String
    var lessonID: UUID?
    var focusStage: LessonAssetStage? = nil
    var focusRequest = UUID()
    var onSelectLesson: (UUID) -> Void
    var onCopyCourse: () -> Void
    @Binding var mode: ReshapeMode
    @State private var stage: LessonAssetStage = .preparation

    private var course: CourseSession? { store.roomCourses(channel).first { $0.id == lessonID } }
    private var headerTitle: String {
        switch mode {
        case .analysis: return "数据"
        case .assets:
            switch stage {
            case .preparation: return "备课"
            case .classroom: return "课堂记录"
            case .review: return "复盘"
            }
        }
    }
    private var planTitle: String? {
        guard let lessonID else { return nil }
        return store.preparationForLesson(lessonID, channel: channel)?.title
    }
    /// 副标题：课程名 · 上课日期时间（没开过课就只有课程名）。四个页面一致，不再拼两个课程名。
    private var headerSubtitle: String? {
        let name = course?.title ?? planTitle
        let when = course.map { $0.started.formatted(date: .abbreviated, time: .shortened) }
        let parts = [name, when].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReshapePanelHeader(
                title: headerTitle,
                subtitle: headerSubtitle,
                stage: mode == .assets ? $stage : nil,
                trailing: mode == .analysis ? AnyView(refreshButton) : nil
            )
            // 课堂记录：不用外层 ScrollView，四区均分高度、区内自滚；其余页保持整页滚动
            if mode == .assets, stage == .classroom, !store.classroomLessons(channel).isEmpty {
                LessonAssetsPanel(
                    store: store, channel: channel, lessonID: lessonID,
                    focusStage: focusStage, focusRequest: focusRequest,
                    onSelect: onSelectLesson, stage: $stage
                )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    Group {
                        if mode == .assets {
                            if store.classroomLessons(channel).isEmpty {
                                Text("暂无课程产出")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textMuted)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                LessonAssetsPanel(
                                    store: store, channel: channel, lessonID: lessonID,
                                    focusStage: focusStage, focusRequest: focusRequest,
                                    onSelect: onSelectLesson, stage: $stage
                                )
                            }
                        } else {
                            ClassroomDataPanel(store: store, channel: channel, lessonID: lessonID, reshapeEmbedded: true)
                        }
                    }
                    .padding(12)
                }
            }
            if mode == .assets, lessonID != nil {
                ReshapeCopyFooter(action: onCopyCourse)
            }
        }
        .background(AppTheme.bgPanel)
        .onAppear { applyStageFocus() }
        .onChange(of: focusRequest) { _, _ in applyStageFocus() }
        .onChange(of: lessonID) { _, _ in
            stage = store.lessonAssetStage(channel: channel, lessonID: lessonID)
        }
    }

    private func applyStageFocus() {
        stage = focusStage ?? store.lessonAssetStage(channel: channel, lessonID: lessonID)
    }

    @ViewBuilder private var refreshButton: some View {
        if let id = lessonID ?? course?.id {
            HStack(spacing: 4) {
                if store.dataSyncBusy.contains(id) { ProgressView().controlSize(.small) }
                Button { store.scheduleCourseDataSync(id) } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.textMuted)
                .help("更新数据")
                .disabled(store.dataSyncBusy.contains(id))
            }
        }
    }
}

private struct LessonExerciseContent: View {
    var exercise: Exercise
    var showsQuestion = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exercise.correctIndices.count > 1 ? "多选" : "单选")
                Spacer()
                if exercise.sentAt != nil { Text("已发送") }
            }.font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
            if showsQuestion { Text(exercise.question).font(.system(size: 13, weight: .medium)).textSelection(.enabled) }
            ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                HStack(alignment: .top, spacing: 8) {
                    Text(String(UnicodeScalar(65 + index)!)).fontWeight(.medium)
                    Text(option).frame(maxWidth: .infinity, alignment: .leading)
                    if exercise.correctIndices.contains(index) { Image(systemName: "checkmark") }
                }.font(.system(size: 12)).foregroundStyle(exercise.correctIndices.contains(index) ? AppTheme.success : .primary)
                    .padding(9).background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 7)).textSelection(.enabled)
            }
            Text("答案：" + exercise.correctIndices.map { String(UnicodeScalar(65 + $0)!) }.joined(separator: "、"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.success).textSelection(.enabled)
            if !exercise.explanation.isEmpty { ChatMarkdown(text: exercise.explanation) }
            if !exercise.evidence.isEmpty { DisclosureGroup("出题依据") { Text(exercise.evidence).font(.system(size: 12)).textSelection(.enabled) } }
        }
    }
}

struct LessonAssetDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    configuration.label.font(.system(size: 13, weight: .medium)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textSecondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0)).padding(.top, 3)
                }.foregroundStyle(.primary).padding(12).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "已展开" : "已收起")
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 10) { configuration.content }
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 10))
    }
}
