import SwiftUI
import AssistantCore

enum MessageType: String {
    case question = "问", exercise = "题", checkin = "签", notice = "告", survey = "卷", rush = "抢", timer = "时", feedback = "报", lag = "卡", screen = "屏", sound = "声", analysis = "析", assistant = "助", chat = "聊", material = "资", risk = "规"
    var title: String {
        switch self {
        case .question: return "待答问题"; case .exercise: return "答题"; case .checkin: return "签到"; case .notice: return "公告"
        case .survey: return "问卷"; case .rush: return "抢答"; case .timer: return "倒计时"
        case .feedback: return "课堂反馈"; case .lag: return "卡顿反馈"; case .screen: return "画面反馈"; case .sound: return "声音反馈"
        case .analysis: return "分析结果"; case .assistant: return "助教动态"; case .chat: return "公屏消息"; case .material: return "资料"; case .risk: return "违规消息"
        }
    }
    /// Badge fill: only the colour differs; chrome is the same rounded square for every type.
    var color: Color {
        switch self {
        case .question: return AppTheme.dyn(0x2469F3, 0x5AA2FF)          // blue
        case .material: return AppTheme.dyn(0x0B9E9A, 0x3DCDC8)          // teal / cyan
        case .feedback, .lag, .screen, .sound: return AppTheme.dyn(0xB25E00, 0xFF9F0A) // orange
        case .exercise, .analysis: return AppTheme.dyn(0x8E44D6, 0xC97DF5) // purple
        case .timer: return AppTheme.dyn(0xC48A00, 0xFFCC00)             // yellow
        case .rush: return AppTheme.dyn(0xD92D20, 0xFF6961)              // red
        case .survey: return AppTheme.dyn(0x1F9D55, 0x34C759)            // green
        case .risk: return AppTheme.dyn(0xD92D20, 0xFF6961)
        case .checkin: return AppTheme.success
        case .notice: return AppTheme.dyn(0x0B7D93, 0x40C8E0)
        case .assistant: return AppTheme.accent
        case .chat: return AppTheme.dyn(0x6B7078, 0x98989F)
        }
    }
    var symbol: String {
        switch self {
        case .question: return "questionmark"
        case .material: return "doc.text.fill"
        case .feedback: return "megaphone.fill"
        case .lag: return "wifi.exclamationmark"
        case .sound: return "speaker.wave.2.fill"
        case .screen: return "display"
        case .risk: return "exclamationmark.shield.fill"
        case .checkin: return "hand.raised.fill"
        case .exercise: return "checklist"
        case .analysis: return "chart.bar.xaxis"
        case .notice: return "megaphone.fill"
        case .survey: return "list.bullet.clipboard.fill"
        case .rush: return "bolt.fill"
        case .timer: return "timer"
        case .assistant: return "sparkles"
        case .chat: return "bubble.left.fill"
        }
    }
}
/// Unified badge chrome: rounded square + white SF Symbol; only the fill colour differs by type.
/// 「助」 shows the 形象与风格 persona head when known. Sizes: list/card ~28, compact ~20, activity ~16.
struct MessageTypeBadge: View {
    var type: MessageType
    var compact = false
    var side: CGFloat? = nil
    @Environment(\.assistantPet) private var assistantPet
    /// Shared corner radius relative to side (continuous rounded square for every type).
    static func corner(_ side: CGFloat) -> CGFloat { side * 0.28 }
    var body: some View {
        let d = side ?? (compact ? 20 : 28)
        if type == .assistant, let pet = assistantPet {
            AssistantAvatar(pet: pet, size: d).fixedSize().accessibilityLabel(type.title).help(type.title)
        } else {
            Image(systemName: type.symbol)
                .font(.system(size: d * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: d, height: d)
                .background(type.color, in: RoundedRectangle(cornerRadius: Self.corner(d), style: .continuous))
                .fixedSize()
                .accessibilityLabel(type.title)
                .help(type.title)
        }
    }
}

private struct AssistantPetKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    /// Persona id from 形象与风格; set on the bubble / big card root so 「助」 badges show the persona's head.
    var assistantPet: String? { get { self[AssistantPetKey.self] } set { self[AssistantPetKey.self] = newValue } }
}
extension PendingMessage {
    var audienceCount: Int { sourceMessages.isEmpty ? people.count : Set(sourceMessages.map(\.userID)).count }
    var typeBadge: MessageType {
        if let messageType { return messageType }
        switch kind {
        case .question: return .question
        case .material: return .material
        case .risk: return .risk
        case .notice: return .assistant
        case .technical:
            let text = title + question
            if text.contains("黑屏") || text.contains("画面") { return .screen }
            if text.contains("声音") || text.contains("无声") || text.contains("听不到") { return .sound }
            if text.contains("卡") || text.contains("延迟") { return .lag }
            return .feedback
        }
    }
}
extension LiveInteraction.Kind {
    var badge: MessageType {
        switch self { case .answer: return .exercise; case .checkin: return .checkin; case .notice: return .notice; case .questionnaire: return .survey; case .rush: return .rush; case .timer: return .timer }
    }
}
