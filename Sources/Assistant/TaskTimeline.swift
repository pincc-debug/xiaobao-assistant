import SwiftUI
import AssistantCore

extension Store {
    func activity(_ category: String, _ title: String, status: String = "已完成", source: String = "", messageID: String? = nil) {
        let item = AssistantActivity(category: category, title: title, status: status, source: source, messageID: messageID)
        activities.append(item)
        if let i = courseIndex { saved.courses[i].activities = activities; persist() }
    }
    func showPublicMessage(_ message: ClassroomMessage) {
        publicMessages.append(message); publicMessages = Array(publicMessages.suffix(20))
        publicExpiryTask?.cancel(); let lifetime = flowLifetime
        publicExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(lifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }; self?.publicMessages = []
        }
    }
}
struct TaskTimeline: View {
    var entries: [AssistantActivity]
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            if entries.isEmpty { Text("暂无助教记录").font(.system(size: 13)).foregroundStyle(AppTheme.textHint).frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20) }
            ForEach(entries.reversed()) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Text(entry.time.formatted(date: .omitted, time: .standard)).font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textSecondary).frame(width: 58, alignment: .leading)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(entry.category).font(.system(size: 11, weight: .medium)).foregroundStyle(AppTheme.accent)
                            Spacer()
                            Text(entry.status).font(.system(size: 11)).foregroundStyle(entry.status == "失败" ? AppTheme.danger : .secondary)
                        }
                        Text(entry.title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        if !entry.source.isEmpty { Text(entry.source).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.bottom, 8).overlay(alignment: .bottom) { Divider().opacity(0.45) }
            }
        }
    }
}
