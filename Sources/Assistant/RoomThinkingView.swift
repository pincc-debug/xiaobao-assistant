import SwiftUI
import AssistantCore

struct RoomThinkingView: View {
    var process: RoomThinking
    @State private var expanded: Bool
    init(process: RoomThinking) {
        self.process = process
        _expanded = State(initialValue: process.finished == nil)
    }
    private var title: String {
        guard let end = process.finished else { return "思考中" }
        return process.status == "已完成" ? "已思考 \(max(1, Int(end.timeIntervalSince(process.started)))) 秒" : process.status
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    if process.finished == nil { ProgressView().controlSize(.mini) }
                    else { Image(systemName: process.status == "已完成" ? "checkmark.circle" : "pause.circle") }
                    Text(title).fontWeight(.medium)
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                    Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title + (expanded ? "，收起过程" : "，展开过程"))
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(process.steps) { step in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).fontWeight(.medium)
                                if !step.detail.isEmpty { ChatMarkdown(text: step.detail) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if process.finished == nil {
                            if process.steps.last?.title != process.status { Text(process.status) }
                            if !process.preview.isEmpty { ChatMarkdown(text: process.preview) }
                        } else if process.steps.isEmpty {
                            Text(process.status == "已完成" ? "回答已完成" : process.status)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(AppTheme.columnLine).frame(width: 1) }
            }
        }
        .font(.system(size: 12)).foregroundStyle(AppTheme.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 37)
        .onChange(of: process.finished) { _, end in if end != nil { expanded = false } }
    }
}
