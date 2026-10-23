import SwiftUI
import AssistantCore

/// Full stored class transcript (记录 › 课堂转写): time-stamped paragraphs, 13pt / 22pt line height, selectable.
struct TranscriptRecords: View {
    var course: CourseSession
    struct Paragraph: Identifiable, Equatable { var id: Int; var time: Date?; var text: String }
    /// Consecutive segments less than `gap` apart form one paragraph stamped with its first segment's time.
    /// Without segments (older courses) the raw transcript is split on line breaks.
    static func paragraphs(_ course: CourseSession, gap: TimeInterval = 60) -> [Paragraph] {
        let segments = (course.transcriptSegments ?? []).filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var out: [Paragraph] = []
        if segments.isEmpty {
            for line in course.transcript.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { out.append(Paragraph(id: out.count, time: nil, text: t)) }
            }
            return out
        }
        var last: Date?
        for seg in segments.sorted(by: { $0.time < $1.time }) {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let l = last, seg.time.timeIntervalSince(l) < gap, !out.isEmpty { out[out.count - 1].text += text }
            else { out.append(Paragraph(id: out.count, time: seg.time, text: text)) }
            last = seg.time
        }
        return out
    }
    static func header(_ course: CourseSession) -> String {
        let p = paragraphs(course)
        let chars = p.reduce(0) { $0 + $1.text.count }
        let times = p.compactMap(\.time)
        let range = times.first.map { a in CourseData.format(a, pattern: "HH:mm") + (times.last.map { "–" + CourseData.format($0, pattern: "HH:mm") } ?? "") } ?? ""
        return ["\(chars) 字", range].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    var body: some View {
        let items = Self.paragraphs(course)
        if items.isEmpty {
            Text("本场没有课堂转写").font(.system(size: 13)).foregroundStyle(AppTheme.textHint)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(Self.header(course)).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                ForEach(items) { p in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let t = p.time { Text(CourseData.format(t, pattern: "HH:mm")).font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textHint).frame(width: 40, alignment: .leading) }
                        Text(p.text).font(.system(size: 13)).lineSpacing(6).foregroundStyle(Ink.primary).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
