import SwiftUI
import AssistantCore

/// 课堂 ① 进行中卡片 (README §3.2 / §7.1): 20pt type avatar + 「类型 · 第 N 轮」 + status; the type colour is on the avatar only
/// (cards are never tinted). Neutral 28pt capsule: 「结束…」 while running, 「重试」 only after a failed sync, nothing while syncing. Goes compact (no distribution bars / analysis) while questions are waiting.
struct ActiveInteractions: View {
    @ObservedObject var store: Store
    var compact = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dense = compact || store.classroomQuestionCount > 0
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.pinnedInteractions) { item in card(item, dense: dense) }
        }
    }
    enum Status: Equatable { case running, paused, awaitingPublish, syncing, failed }
    static func status(_ item: LiveInteraction, busy: Bool) -> Status {
        if syncFailed(item) && !busy { return .failed }
        if busy { return .syncing }
        // Ended answer with stats waits for「公布结果」instead of looking like a sync spinner.
        if item.kind == .answer, item.ended != nil, !item.resultPublished, item.snapshots.last != nil { return .awaitingPublish }
        if item.ended != nil { return .syncing }
        if item.kind == .timer, item.timerPaused { return .paused }
        return .running
    }
    /// The error the runtime records when the statistics were saved but only the AI analysis failed.
    static let analysisUnavailableError = "统计已保存，分析暂不可用"
    /// Display only: stats are present and the only problem is the analysis → normal status, stats + bars as usual,
    /// a grey 「分析暂不可用」 line in place of the analysis. Red 「同步失败」 is reserved for stats that weren't saved.
    static func analysisOnlyFailure(_ item: LiveInteraction) -> Bool { item.error == analysisUnavailableError && item.snapshots.last != nil }
    static func syncFailed(_ item: LiveInteraction) -> Bool { item.error != nil && !analysisOnlyFailure(item) }
    /// Only the cause of a failed sync, e.g. 「结果同步失败：网络连接中断」 → 「网络连接中断」; nil when nothing is left beyond
    /// 「…失败」/「可重试」 (the status and the 重试 button already say that).
    static func failureReason(_ error: String?) -> String? {
        guard var text = error?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let r = text.range(of: "："), text[..<r.lowerBound].hasSuffix("失败") { text = String(text[r.upperBound...]) }
        for tail in ["，可重试", "，请稍后重试", "，请重试"] where text.hasSuffix(tail) { text.removeLast(tail.count) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty || text.hasSuffix("失败") { return nil }
        return text
    }
    /// 「第 N 题」/「第 N 轮」 among this course's interactions of the same kind.
    static func round(_ item: LiveInteraction, in all: [LiveInteraction]) -> String {
        let n = (all.filter { $0.kind == item.kind }.firstIndex { $0.id == item.id } ?? 0) + 1
        return item.kind == .answer ? "第 \(n) 题" : "第 \(n) 轮"
    }
    /// Distribution bars show which option is correct only once the quiz has ended.
    static func revealsCorrect(_ item: LiveInteraction) -> Bool { item.ended != nil }
    @ViewBuilder private func card(_ item: LiveInteraction, dense: Bool) -> some View {
        let busy = store.interactionBusy.contains(item.id)
        let status = Self.status(item, busy: busy)
        let tint = item.kind.badge.color
        let analysisFailed = Self.analysisOnlyFailure(item)
        let hasAction = Self.action(item, status: status) != nil || (status == .running && item.kind == .timer && !item.timerPaused)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                MessageTypeBadge(type: item.kind.badge, side: 28)
                Text(item.kind.title + " · " + Self.round(item, in: store.currentCourse?.interactions ?? [])).font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.textSecondary)
                Spacer(minLength: 6)
                statusView(status)
            }
            if !item.content.isEmpty { Text(item.content).font(.system(size: 13, weight: .semibold)).lineLimit(compact ? 1 : 2) }
            if dense {   // compact: result and action share one row
                // (with 「分析暂不可用」 the action moves down into that line's row instead)
                HStack(alignment: .center) { result(item); Spacer(minLength: 8); if !analysisFailed, hasAction { actionButtons(item, status: status) } }
            } else { result(item) }
            if !dense, item.kind == .answer, let data = item.snapshots.last, !data.options.isEmpty { bars(item, data: data, tint: tint) }
            if analysisFailed {   // in place of the analysis line (also in the compact / bubble card); shares the action row: text leading, button trailing
                HStack(alignment: .center) {
                    AnalysisUnavailableLine(retry: store.currentCourseID.map { courseID in { store.analyzeInteraction(item.id, courseID: courseID, generation: store.epoch) } },
                                            disabled: store.interactionAnalysisBusy.contains(item.id))
                    Spacer(minLength: 8)
                    if hasAction { actionButtons(item, status: status) }
                }
            } else if !dense, !item.analysis.isEmpty {
                Text("✦ " + item.analysis).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).lineLimit(2)
            }
            // Failed: the top-right 「同步失败」 already says what happened; the card only adds the reason, 12pt grey.
            if status == .failed, let reason = Self.failureReason(item.error) { Text(reason).font(.system(size: 12)).foregroundStyle(AppTheme.textSecondary).lineLimit(2) }
            if !dense, !analysisFailed, hasAction { HStack { Spacer(); actionButtons(item, status: status) } }
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.liveCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    /// Running/paused → 「结束…」; awaitingPublish → 「公布结果」; failed → 「重试」; syncing → no button.
    static func action(_ item: LiveInteraction, status: Status) -> String? {
        switch status {
        case .running, .paused: return item.kind.endTitle
        case .awaitingPublish: return "公布结果"
        case .failed: return "重试"
        case .syncing: return nil
        }
    }
    @ViewBuilder private func actionButtons(_ item: LiveInteraction, status: Status) -> some View {
        HStack(spacing: 8) {
            if status == .running, item.kind == .timer, !item.timerPaused {
                Button("暂停") { store.pauseTimer(item.id) }
                    .buttonStyle(QuietFillButtonStyle(fontSize: 12))
                    .disabled(!store.connected)
            }
            if let title = Self.action(item, status: status) {
                if status == .awaitingPublish {
                    Button(title) { store.publishAnswerResult(item.id) }
                        .buttonStyle(ModernPrimaryButtonStyle(size: .small, horizontalPadding: 12))
                        .disabled(!store.connected)
                } else {
                    Button(title) { store.endInteraction(item.id) }
                        .buttonStyle(QuietFillButtonStyle(fontSize: 12))
                        .disabled(!store.connected)
                }
            }
        }
    }
    @ViewBuilder private func statusView(_ status: Status) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .running: Circle().fill(AppTheme.success).frame(width: 6, height: 6); Text("进行中").foregroundStyle(AppTheme.textSecondary)
            case .paused: Circle().fill(AppTheme.textHint).frame(width: 6, height: 6); Text("已暂停").foregroundStyle(AppTheme.textSecondary)
            case .awaitingPublish: Circle().fill(AppTheme.accent).frame(width: 6, height: 6); Text("待公布").foregroundStyle(AppTheme.textSecondary)
            case .syncing: ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 10, height: 10); Text("结果同步中").foregroundStyle(AppTheme.textHint)
            case .failed: Text("同步失败").foregroundStyle(AppTheme.danger)
            }
        }.font(.system(size: 11, weight: .medium))
    }
    @ViewBuilder private func result(_ item: LiveInteraction) -> some View {
        if item.kind == .timer, item.timerPaused, item.ended == nil {
            Text("已暂停").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
        } else if item.kind.statusOnly || item.kind == .checkin, item.ended == nil, let deadline = item.deadline {
            TimelineView(.periodic(from: .now, by: 1)) { time in
                let left = max(0, Int(deadline.timeIntervalSince(time.date)))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if item.kind == .checkin, let data = item.snapshots.last { number("\(data.count)", unit: "人已签到 ·") }
                    number(String(format: "%d:%02d", left / 60, left % 60), unit: "剩余")
                }
            }
        } else if let data = item.snapshots.last, item.kind == .answer || item.kind == .checkin {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                number("\(data.count)", unit: item.kind == .answer ? "人已答" : "人已签到")
                if item.kind == .answer, data.count > 0, let correct = data.correct, Self.revealsCorrect(item) {
                    Text("· 正确率").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    Text("\(Int((Double(correct) / Double(data.count) * 100).rounded()))%").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
            }
        } else if item.kind == .questionnaire {
            Text("学员填写中，结束后到直播后台查看结果").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
        } else if item.kind != .notice {
            Text("等待数据").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
        }
    }
    private func number(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text(unit).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
        }
    }
    private func bars(_ item: LiveInteraction, data: InteractionSnapshot, tint: Color) -> some View {
        let exercise = store.currentCourse?.exercises?.first { $0.id == item.exerciseID }
        let correct = Set(Self.revealsCorrect(item) ? exercise?.correctIndices ?? [] : [])
        let top = max(1, data.options.max() ?? 1)
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(data.options.enumerated()), id: \.offset) { index, count in
                HStack(spacing: 8) {
                    Text(String(UnicodeScalar(65 + index)!)).font(.system(size: 11, weight: correct.contains(index) ? .semibold : .regular)).foregroundStyle(correct.contains(index) ? AnyShapeStyle(tint) : AnyShapeStyle(AppTheme.textSecondary)).frame(width: 12, alignment: .leading)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(AppTheme.dyn(0x000000, 0xFFFFFF, 0.06, 0.10))
                            Capsule().fill(correct.contains(index) ? AnyShapeStyle(tint) : AnyShapeStyle(AppTheme.dyn(0x000000, 0xFFFFFF, 0.22, 0.32)))
                                .frame(width: g.size.width * CGFloat(count) / CGFloat(top))
                        }
                    }.frame(height: 6)
                    Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(AppTheme.textSecondary).frame(minWidth: 18, alignment: .trailing)
                }
            }
        }
    }
}
struct InteractionRecords: View {
    @ObservedObject var store: Store
    var course: CourseSession
    @Environment(\.colorScheme) private var scheme
    private static func hm(_ d: Date) -> String { CourseData.format(d, pattern: "HH:mm") }
    /// 7.2 card: black 3.5% / white 5%, radius 12, padding L14 R12 V12; header = 20pt type avatar + 「类型 · 开始时间」 + status.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if (course.interactions ?? []).isEmpty { Text("暂无互动记录").foregroundStyle(AppTheme.textSecondary) }
            ForEach((course.interactions ?? []).reversed()) { item in card(item) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func status(_ item: LiveInteraction) -> String { ActiveInteractions.syncFailed(item) ? "同步失败" : item.finalized ? "已结束" : item.ended != nil ? "结果待同步" : course.ended != nil ? "结束状态未确认" : "进行中" }
    private func timeLine(_ item: LiveInteraction) -> String {
        let start = item.started.formatted(date: .omitted, time: .standard)
        let end = item.ended.map { "–" + $0.formatted(date: .omitted, time: .standard) } ?? ""
        return start + end + " · " + item.summary
    }
    @ViewBuilder private func card(_ item: LiveInteraction) -> some View {
        let status = status(item)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        MessageTypeBadge(type: item.kind.badge, side: 28)
                        Text(item.kind.title + " · " + Self.hm(item.started)).font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            if status == "进行中" { Circle().fill(AppTheme.success).frame(width: 6, height: 6) }
                            Text(status).font(.system(size: 11, weight: .medium)).foregroundStyle(status == "同步失败" ? AnyShapeStyle(AppTheme.danger) : status == "进行中" ? AnyShapeStyle(AppTheme.textSecondary) : AnyShapeStyle(Ink.group))
                        }
                    }
                    if !item.content.isEmpty { Text(item.content).font(.system(size: 13, weight: .semibold)).lineLimit(2) }
                    Text(timeLine(item))
                        .font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    if let data = item.snapshots.last, !data.options.isEmpty {
                        Text(data.options.enumerated().map { "\(String(UnicodeScalar(65 + $0.offset)!))：\($0.element) 人" }.joined(separator: "  ")).font(.system(size: 11))
                    }
                    if item.kind == .checkin, !item.attendees.isEmpty {
                        Text("签到名单 · \(item.attendees.count)：" + item.attendees.map(\.name).joined(separator: "、")).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).lineLimit(3)
                        if !item.rosterComplete { Text("名单尚未同步完整").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary) }
                    }
                    // 签到 analysis only restates the count already in the summary line (「暂无签到」/「已签到 N 人」); not repeated here.
                    let analysisFailed = ActiveInteractions.analysisOnlyFailure(item)
                    if analysisFailed {   // stats saved, only the analysis failed: grey line in place of the analysis
                        // Retry only under the former 「重试分析」 condition (current course, 答题, ended); otherwise just the text.
                        AnalysisUnavailableLine(retry: course.id == store.currentCourseID && item.kind == .answer && item.finalized
                                                ? { store.analyzeInteraction(item.id, courseID: course.id, generation: store.epoch) } : nil)
                    } else if item.kind != .checkin, !item.analysis.isEmpty {
                        Text("✦ " + (item.analysisSignature == item.snapshots.last?.signature ? "助教分析" : "上次分析")).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                        Text(item.analysis).font(.system(size: 13))
                    }
                    // Sync failed: the red 「同步失败」 is top-right; here only the reason, 12pt grey. No retry in the history.
                    if !analysisFailed, let reason = ActiveInteractions.failureReason(item.error) {
                        Text(reason).font(.system(size: 12)).foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.liveCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
}

/// Analysis-only failure, one 12pt line: grey 「分析暂不可用 · 」 + accent 「重试」 (plain text, no button fill, 28pt tap target).
/// Without a retry it reads just 「分析暂不可用」.
struct AnalysisUnavailableLine: View {
    var retry: (() -> Void)?
    var disabled = false
    static func text(retry: Bool) -> String { retry ? "分析暂不可用 · 重试" : "分析暂不可用" }
    var body: some View {
        HStack(spacing: 0) {
            Text(retry == nil ? "分析暂不可用" : "分析暂不可用 · ").foregroundStyle(AppTheme.textSecondary)
            if let retry {
                Button(action: retry) {
                    Text("重试").foregroundStyle(AppTheme.accent).frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.5 : 1)
            }
        }
        .font(.system(size: 12))
        .frame(minHeight: retry == nil ? nil : 28)
    }
}
