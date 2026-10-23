import SwiftUI
import AssistantCore

enum NotebookSection: String, CaseIterable, Identifiable {
    case interactions = "课堂互动", transcript = "课堂转写", quotes = "课堂要点", questions = "练习题", keyPoints = "知识点总结", faq = "问答", summary = "课程总结", outline = "课程大纲", handout = "课后笔记", knowledge = "知识库"
    var id: String { rawValue }
    var output: ArchiveOutput? {
        switch self { case .questions: return .questions; case .keyPoints: return .keyPoints; case .faq: return .faq; case .summary: return .summary; case .outline: return .outline; case .handout: return .handout; case .knowledge: return .faqToKnowledge; default: return nil }
    }
    static func enabled(in settings: CapabilitySelection) -> [Self] {
        allCases.filter { section in
            // 课堂转写 is no longer a sub-tab (the transcript is still stored; its latest sentence shows as the 工作台 caption).
            if section == .transcript { return false }
            if section == .interactions { return true }
            if section == .quotes { return settings.isEnabled(.quoteCards) }
            guard let output = section.output else { return false }
            return output.realtime && settings.isEnabled(.courseArchive) && settings.isEnabled(output)
        }
    }
    static func available(in course: CourseSession) -> [Self] {
        allCases.filter { section in
            switch section {
            case .interactions: return !(course.interactions ?? []).isEmpty
            case .transcript: return true
            case .quotes: return !(course.quotes ?? []).isEmpty || !course.cards.isEmpty
            case .questions: return !(course.exercises ?? []).isEmpty
            case .knowledge: return course.knowledgeDocumentID != nil
            default: return section.output.flatMap { course.outputs?[$0.rawValue] }.map { !$0.isEmpty } ?? false
            }
        }
    }
}
struct NotebookTabs: View {
    var sections: [NotebookSection]
    @Binding var selection: NotebookSection
    var body: some View {
        ScrollView(.horizontal) {
            // Underline tabs: no background / pill; selected = accent text + 2pt accent underline.
            HStack(spacing: 20) {
                ForEach(sections) { section in
                    let on = selection == section
                    Button { selection = section } label: {
                        Text(section.rawValue).font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? AppTheme.accent : AppTheme.textSecondary)
                            .padding(.vertical, 6)
                            .overlay(alignment: .bottom) { Capsule().fill(on ? AppTheme.accent : .clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.scrollIndicators(.hidden).frame(maxWidth: .infinity, alignment: .leading)
        .mask(HStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24) })   // right-end fade
    }
}
struct NotebookContent: View {
    @ObservedObject var store: Store
    var course: CourseSession
    var section: NotebookSection
    var live: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch section {
            case .interactions: InteractionRecords(store: store, course: course)
            case .transcript:
                if live { LiveAudioStatus(voice: store.liveVoice) }
                text(course.transcript, empty: "暂无课堂转写")
            case .quotes:
                let quotes = Array(Set((course.quotes ?? []) + course.cards.map(\.quote))).sorted()
                if quotes.isEmpty { text("", empty: "暂无课堂要点") }
                ForEach(quotes, id: \.self) { quote in text(quote) }
            case .questions: ExerciseList(store: store, course: course, canSend: live)
            case .knowledge:
                text((course.knowledgePoints ?? []).map { "- " + $0.text }.joined(separator: "\n"), empty: "暂无知识点")
            default:
                if let output = section.output {
                    text(course.outputs?[output.rawValue] ?? "", empty: output.realtime ? "暂无内容" : "课后生成")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    func text(_ value: String, empty: String = "暂无内容") -> some View {
        Text(value.isEmpty ? empty : value).font(.system(size: 13)).foregroundStyle(value.isEmpty ? .secondary : .primary)
            .lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            .padding(14).modifier(BigCardItem())
    }
}

private struct LiveAudioStatus: View {
    @ObservedObject var voice: VoiceSession
    var body: some View {
        if !voice.phase.isEmpty {
            Text(voice.phase).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct LiveMessageStream: View {
    @ObservedObject var store: Store
    var compact = false
    /// Big card footer: 18pt badges, 11pt regular secondary text, one line each.
    var quiet = false
    /// Bubble: keeps more lines and receives wheel/trackpad so its enclosing ScrollView scrolls.
    var scrollable = false
    /// How many recent stream rows to show (newest at the bottom). Bubble stays tight (2); workbench quiet footer can show 3.
    var limit: Int = 2
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { time in
            let feed = Store.recentStreamMessages(store.messages, now: time.date, lifetime: store.flowLifetime, limit: limit)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(feed) { activity in
                    HStack(alignment: .top, spacing: 6) {
                        MessageTypeBadge(type: activity.typeBadge, compact: true, side: quiet ? 18 : nil)
                        VStack(alignment: .leading, spacing: 2) {
                            // Reply lines already carry nickname · question; other stream rows may still have a detail.
                            Text(activity.assistantVoiceTitle).font(.system(size: 11, weight: quiet ? .regular : .medium)).foregroundStyle(quiet ? AppTheme.textSecondary : Color.primary).lineLimit(1).truncationMode(.tail)
                            if let echo = activity.commandEcho {
                                Text(echo).font(.system(size: 11)).foregroundStyle(AppTheme.textHint).lineLimit(2)
                            } else if !activity.question.isEmpty && !quiet && !activity.assistantVoiceTitle.contains(activity.question) {
                                Text(activity.question).font(.system(size: 11)).foregroundStyle(Ink.secondary).lineLimit(1).truncationMode(.tail)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.15), value: feed.map(\.id))
        }
        .allowsHitTesting(scrollable)   // no buttons inside; bubble needs hit-testing for scroll events
        .accessibilityElement(children: .combine)
    }
}

struct SettingsFooter: View {
    @ObservedObject var store: Store
    /// Collapsed sidebar: the three appearance buttons stack vertically, 连接与模型 last.
    var vertical = false
    private let modes = [("light", "sun.max", "亮色"), ("dark", "moon", "暗色"), ("system", "circle.lefthalf.filled", "跟随系统")]
    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        let modeLayout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            modeLayout {
                ForEach(modes, id: \.0) { mode in
                    let isSelected = store.saved.preferences.appearance == mode.0
                    Button { store.saved.preferences.appearance = mode.0 } label: {
                        Image(systemName: mode.1)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                            .frame(maxWidth: vertical ? 32 : .infinity)
                            .frame(height: 28)
                            .background(
                                isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .shadow(color: isSelected ? Color.black.opacity(0.06) : Color.clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help(mode.2)
                    .accessibilityLabel(mode.2)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: vertical ? 16 : 1, height: vertical ? 1 : 16)
                .padding(vertical ? .vertical : .horizontal, 2)
            
            let isConfig = store.settingsPage == "连接与模型"
            Button { store.settingsPage = "连接与模型"; store.error = "" } label: {
                Image(systemName: "network")
                    .font(.system(size: 13, weight: isConfig ? .semibold : .regular))
                    .foregroundStyle(isConfig ? AppTheme.accent : .secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        isConfig ? AppTheme.accent.opacity(0.12) : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help("连接与模型")
            .accessibilityLabel("连接与模型")
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.75)
        )
    }
}

/// Shared, quiet empty state. The containing panel supplies the available height.
struct NotebookEmptyState: View {
    /// The PNG (1536×1024) has wide transparent margins; crop to the drawing (+16px) so 64pt is the art itself, not the canvas.
    static let artRect = CGRect(x: 410, y: 180, width: 706, height: 666)
    private static let picture: NSImage? = {
        guard let url = Bundle.module.url(forResource: "empty-notebook-v1", withExtension: "png"), let image = NSImage(contentsOf: url) else { return nil }
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width == 1536, cg.height == 1024, let art = cg.cropping(to: artRect) else { return image }
        return NSImage(cgImage: art, size: NSSize(width: art.width, height: art.height))
    }()
    static let message = "上课后，笔记会自动生成"
    var body: some View {
        VStack(spacing: 10) {
            if let picture = Self.picture { Image(nsImage: picture).resizable().interpolation(.high).scaledToFit().frame(width: 64, height: 64) }
            Text(Self.message).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine).accessibilityLabel("暂无内容，" + Self.message)
    }
}
