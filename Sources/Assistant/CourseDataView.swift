import SwiftUI
import Charts
import AssistantCore

struct CourseDataView: View {
    @ObservedObject var store: Store
    var course: CourseSession
    var live: Bool
    /// When embedded in CourseWorkbenchPanel the outer chrome already shows title/refresh.
    var reshapeEmbedded: Bool = false
    @State private var selectedTime: Date?
    @State private var chatSearch = ""
    @State private var chatLimit = 30
    @State private var chatOpen = false

    private var analytics: CourseAnalytics { course.analytics ?? CourseAnalytics() }
    private var chat: [PublicChatRecord] { CourseData.chats(course) }
    private var students: [PublicChatRecord] { chat.filter(\.isStudent) }
    private var plotted: [PlotPoint] {
        let historical = analytics.points.filter { $0.source == "历史" }
        let lastHistory = historical.last?.time ?? .distantPast
        let points = (historical + analytics.points.filter { $0.source == "实时" && $0.time > lastHistory }).sorted { $0.time < $1.time }
        let visible = live ? points.filter { $0.time >= Date().addingTimeInterval(-1800) } : points
        var segment = 0
        return visible.enumerated().map { i, p in
            if i > 0 && (p.time.timeIntervalSince(visible[i - 1].time) > 90 || p.source != visible[i - 1].source) { segment += 1 }
            return PlotPoint(id: p.id, time: p.time, count: p.count, segment: String(segment))
        }
    }
    private var minutes: [MinuteCount] {
        Dictionary(grouping: students) { CourseData.calendar.dateInterval(of: .minute, for: $0.time)!.start }
            .map { MinuteCount(time: $0.key, count: $0.value.count) }.sorted { $0.time < $1.time }
    }
    private var frequent: [(String, Int)] {
        let questions = course.answers.map(\.question) + course.unanswered + (course.events ?? []).filter { $0.category == "question" }.map(\.text)
        var counts = Dictionary(grouping: (course.events ?? []).filter { $0.category == "question" }, by: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }).mapValues { Set($0.map(\.id)).count }
        for q in questions where counts[q] == nil { counts[q] = 1 }
        let values: [(String, Int)] = counts.map { ($0.key, $0.value) }
        return Array(values.sorted { a, b in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }.prefix(5))
    }
    private static func hm(_ d: Date) -> String { CourseData.format(d, pattern: "HH:mm") }
    private var platformRange: String? {
        guard let m = analytics.metrics, let a = m.start, let b = m.end else { return nil }
        return Self.hm(a) + "–" + Self.hm(b)
    }
    private var syncLine: String {
        var parts: [String] = []
        if let through = analytics.chatSyncedThrough {
            let from = analytics.chatSyncedFrom ?? analytics.metrics?.start ?? course.started
            parts.append("公聊已同步 " + Self.hm(from) + "–" + Self.hm(through))
        } else { parts.append("公聊尚未同步") }
        parts.append("\(chat.count) 条")
        if let fetched = [analytics.metrics?.fetchedAt, analytics.lastHistoryAt, analytics.lastRealtimeAt].compactMap({ $0 }).max() {
            parts.append("获取于 " + Self.hm(fetched))
        }
        return parts.joined(separator: " · ")
    }
    private var answeredCount: Int { course.answers.count }
    private var unansweredCount: Int { course.unanswered.count }
    private var speakerCount: Int { Set(students.map(\.userID)).count }
    private var exerciseTypeCounts: (single: Int, multi: Int) {
        let all = course.exercises ?? []
        let multi = all.filter { $0.correctIndices.count > 1 }.count
        return (all.count - multi, multi)
    }
    private var interactions: [LiveInteraction] {
        Array((course.interactions ?? []).reversed())
    }
    private var platformAllZero: Bool {
        guard let m = analytics.metrics else { return true }
        return [m.viewers, m.views, m.peak, m.averageMinutes, m.totalMinutes].allSatisfy { ($0 ?? 0) == 0 }
    }

    @ViewBuilder private func endedBanner(_ now: Date) -> some View {
        if live, store.connected, course.ended == nil, let end = analytics.metrics?.end,
           CourseData.platformEndedEarly(metricsEnd: end, live: true, now: now) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 16)).foregroundStyle(AppTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("平台显示推流已于 \(Self.hm(end)) 结束").font(.system(size: 13, weight: .medium)).foregroundStyle(AppTheme.textStrong)
                    Text("如果你还在直播，去直播后台看看这一场的时长").font(.system(size: 12)).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(AppTheme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 15)) { time in endedBanner(time.date) }

            if !reshapeEmbedded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(live ? "本场数据" : "课程数据")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.textStrong)
                        Spacer()
                        if store.dataSyncBusy.contains(course.id) { ProgressView().controlSize(.small) }
                        Button { store.scheduleCourseDataSync(course.id) } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 12))
                                .frame(width: 24, height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(AppTheme.textSecondary).help("更新数据")
                        .disabled(store.dataSyncBusy.contains(course.id))
                    }
                    Text(syncLine).font(.system(size: 11)).foregroundStyle(AppTheme.textHint).lineLimit(1)
                    if let error = store.dataErrors[course.id] ?? analytics.syncError {
                        Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.danger)
                    }
                }
            } else if let error = store.dataErrors[course.id] ?? analytics.syncError {
                Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.danger)
            }

            // KPI 四格
            TimelineView(.periodic(from: .now, by: 15)) { time in
                let last = analytics.points.last(where: { $0.source == "实时" })
                let fresh = last.map { time.date.timeIntervalSince($0.time) <= 90 } ?? false
                let online = live ? (fresh ? last.map { String($0.count) } : nil) : analytics.metrics?.viewers.map(String.init)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ReshapeKPICell(title: live ? "当前在线" : "观看人数", value: online ?? "—")
                    ReshapeKPICell(title: "发言人数", value: "\(speakerCount)")
                    if !live {
                        ReshapeKPICell(title: "已答问答", value: "\(answeredCount)")
                        ReshapeKPICell(title: "未答问题", value: "\(unansweredCount)", warn: unansweredCount > 0)
                    }
                }
            }

            // 完成弧 + 题型条
            if !live {
                HStack(alignment: .top, spacing: 7) {
                    ReshapeTile(title: "答题完成") {
                        ReshapeCompletionArc(answered: answeredCount, unanswered: unansweredCount)
                    }
                    ReshapeTile(title: "题型占比", meta: "按正确选项数") {
                        let t = exerciseTypeCounts
                        if t.single + t.multi == 0 {
                            Text("暂无题目").font(.system(size: 11)).foregroundStyle(AppTheme.emptyText)
                        } else {
                            ReshapeTypeBar(single: t.single, multi: t.multi)
                        }
                    }
                }
            }

            // 在线趋势
            ReshapeTile(title: live ? "在线趋势 · 近 30 分钟" : "在线趋势") {
                if plotted.allSatisfy({ $0.count == 0 }) {
                    ReshapeTrendPlaceholder(height: 110)
                } else {
                    Chart {
                        ForEach(plotted) { point in
                            AreaMark(x: .value("时间", point.time), y: .value("在线", point.count), series: .value("连续区间", point.segment))
                                .foregroundStyle(AppTheme.accentBright.opacity(0.18))
                            LineMark(x: .value("时间", point.time), y: .value("在线", point.count), series: .value("连续区间", point.segment))
                                .foregroundStyle(AppTheme.accentBright)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                            PointMark(x: .value("时间", point.time), y: .value("在线", point.count))
                                .symbolSize(8).foregroundStyle(AppTheme.accentBright)
                        }
                        if let selectedTime {
                            RuleMark(x: .value("所选时间", selectedTime)).foregroundStyle(AppTheme.textHint.opacity(0.35))
                        }
                    }
                    .chartXSelection(value: $selectedTime)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(AppTheme.chartGrid)
                            AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(AppTheme.textHint)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(AppTheme.chartGrid)
                            AxisValueLabel().foregroundStyle(AppTheme.textHint)
                        }
                    }
                    .chartYScale(domain: 0...max(1, plotted.map(\.count).max() ?? 1))
                    .frame(height: 110)
                }
                if let selectedTime, let point = plotted.min(by: { abs($0.time.timeIntervalSince(selectedTime)) < abs($1.time.timeIntervalSince(selectedTime)) }) {
                    Text("\(point.time.formatted(date: .omitted, time: .shortened)) · \(point.count) 人在线")
                        .font(.system(size: 11)).foregroundStyle(AppTheme.accentBright)
                    if let segment = (course.transcriptSegments ?? []).last(where: { $0.time <= point.time && point.time.timeIntervalSince($0.time) < 180 }) {
                        Text(segment.text).font(.system(size: 12)).foregroundStyle(AppTheme.textBody).lineLimit(4).textSelection(.enabled)
                    }
                }
            }

            // 每分钟发言
            ReshapeTile(title: "每分钟学生发言") {
                let shown = live ? minutes.filter { $0.time >= Date().addingTimeInterval(-1800) } : minutes
                if shown.isEmpty {
                    Text(live ? "近 30 分钟没有学生发言" : "暂无发言记录")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.emptyText)
                        .frame(maxWidth: .infinity).frame(height: 72)
                } else {
                    Chart(shown) { point in
                        BarMark(x: .value("时间", point.time, unit: .minute), y: .value("发言", point.count))
                            .foregroundStyle(LinearGradient(colors: [AppTheme.barTop, AppTheme.barBot], startPoint: .top, endPoint: .bottom))
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                            AxisGridLine().foregroundStyle(AppTheme.chartGrid)
                            AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(AppTheme.textHint)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(AppTheme.chartGrid)
                            AxisValueLabel().foregroundStyle(AppTheme.textHint)
                        }
                    }
                    .frame(height: 90)
                }
            }

            // 高频问题
            ReshapeTile(title: "高频问题") {
                if frequent.isEmpty {
                    Text("暂无高频问题").font(.system(size: 11)).foregroundStyle(AppTheme.emptyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    let maxCount = max(frequent.map(\.1).max() ?? 1, 1)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(frequent.enumerated()), id: \.element.0) { n, item in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("\(n + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.textHint).monospacedDigit().frame(width: 12, alignment: .leading)
                                    Text(item.0).font(.system(size: 11)).foregroundStyle(AppTheme.textBody).lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text("\(item.1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textHint).monospacedDigit()
                                }
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(AppTheme.hfBar.opacity(0.85))
                                        .frame(width: max(6, geo.size.width * CGFloat(item.1) / CGFloat(maxCount)), height: 5)
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
            }

            // 课堂互动（始终渲染；空则一行提示。勿用 reversed() as Array — 会运行时 trap，吞掉后续平台概况）
            ReshapeTile(title: "课堂互动", meta: interactions.isEmpty ? nil : "\(interactions.count)") {
                if interactions.isEmpty {
                    Text("暂无课堂互动")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppTheme.emptyText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(interactions) { item in
                            interactionRow(item)
                        }
                    }
                }
            }

            // 平台概况：上课中整块不显示；课后全 0 → 一行；有非 0 → 全列
            if !live {
                ReshapeTile(title: "平台概况", meta: platformRange) {
                    if analytics.metrics == nil || platformAllZero {
                        Text("平台暂未回传观看数据")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.emptyText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let metrics = analytics.metrics {
                        VStack(spacing: 6) {
                            platformRow("观看人数", metrics.viewers)
                            platformRow("观看次数", metrics.views)
                            platformRow("最高并发", metrics.peak)
                            platformRow("人均观看", metrics.averageMinutes, suffix: " 分钟")
                            platformRow("总观看时长", metrics.totalMinutes, suffix: " 分钟")
                        }
                    }
                }
            }

            // 公聊
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { chatOpen.toggle() }
                } label: {
                    HStack {
                        Text("公聊记录 · \(chat.count)").font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.textBody)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .rotationEffect(.degrees(chatOpen ? 90 : 0))
                    }
                    .frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if chatOpen {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("搜索发言", text: $chatSearch).textFieldStyle(FilledFieldStyle())
                        let filtered = chat.filter {
                            chatSearch.isEmpty
                                || $0.text.localizedCaseInsensitiveContains(chatSearch)
                                || $0.name.localizedCaseInsensitiveContains(chatSearch)
                        }
                        ForEach(Array(filtered.suffix(chatLimit))) { record in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.name + " · " + record.time.formatted(date: .omitted, time: .standard))
                                    .font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                                Text(record.text).font(.system(size: 12)).foregroundStyle(AppTheme.textBody).textSelection(.enabled)
                                if let quote = record.quote, !quote.isEmpty {
                                    Text("引用：" + quote).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).lineLimit(4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if filtered.count > chatLimit {
                            Button("查看更多") { chatLimit += 50 }
                                .font(.system(size: 12)).foregroundStyle(AppTheme.link)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func interactionRow(_ item: LiveInteraction) -> some View {
        HStack(alignment: .top, spacing: 8) {
            MessageTypeBadge(type: item.kind.badge, side: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.kind.title + " · " + Self.hm(item.started))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.textStrong)
                if !item.content.isEmpty {
                    Text(item.content).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            rateBadge(for: item)
        }
    }

    @ViewBuilder private func rateBadge(for item: LiveInteraction) -> some View {
        let snap = item.snapshots.last
        if let snap, snap.count > 0, let correct = snap.correct {
            let pct = Int((Double(correct) / Double(snap.count) * 100).rounded())
            VStack(alignment: .trailing, spacing: 1) {
                Text("已答 \(snap.count)").font(.system(size: 10)).foregroundStyle(AppTheme.rateFg)
                Text("\(pct)%")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppTheme.rateFg)
                    .monospacedDigit()
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(AppTheme.rateBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.rateBorder, lineWidth: 1))
        } else {
            Text(item.summary).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
        }
    }

    private func platformRow(_ title: String, _ value: Int?, suffix: String = "") -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Text(value.map { String($0) + suffix } ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.textStrong)
                .monospacedDigit()
        }
    }

    private struct PlotPoint: Identifiable { var id: String; var time: Date; var count: Int; var segment: String }
    private struct MinuteCount: Identifiable { var id: Date { time }; var time: Date; var count: Int }
}

struct ClassroomDataPanel: View {
    @ObservedObject var store: Store
    var channel: String
    var lessonID: UUID? = nil
    var reshapeEmbedded: Bool = false
    @State private var selection: UUID?
    @State private var pickCourse = DropdownPreview.isOpen("course-data")
    private static func label(_ course: CourseSession) -> String {
        course.title + " · " + course.started.formatted(date: .abbreviated, time: .shortened)
    }
    private var courses: [CourseSession] { store.roomCourses(channel) }
    private var course: CourseSession? {
        courses.first { $0.id == (selection ?? lessonID) } ?? (lessonID == nil ? courses.first : nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let course {
                if !reshapeEmbedded {
                    DropdownField(value: Self.label(course), accessibilityName: "课程", isOpen: pickCourse) {
                        DropdownGate.toggle($pickCourse)
                    }
                    .background(DropdownPanelAnchor(isPresented: $pickCourse, items: courses.map { item in
                        DropdownItem(id: item.id.uuidString, title: Self.label(item), selected: item.id == course.id) {
                            selection = item.id
                        }
                    }))
                }
                CourseDataView(store: store, course: course, live: course.id == store.currentCourseID && course.ended == nil, reshapeEmbedded: reshapeEmbedded)
            } else {
                Text("暂无课程数据").foregroundStyle(AppTheme.textSecondary)
            }
        }
        .onChange(of: lessonID) { _, _ in selection = nil }
        .task(id: course?.id) { if let id = course?.id { store.scheduleCourseDataSync(id) } }
    }
}
