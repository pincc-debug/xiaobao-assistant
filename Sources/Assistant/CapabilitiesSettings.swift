import SwiftUI
import AssistantCore

struct CapabilitiesSettingsView: View {
    @ObservedObject var store: Store

    static let voiceExamples = ["发送课件", "发布公告：十分钟后开始答疑", "回答刚才的问题"]

    var body: some View {
        overview
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(CapabilityGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            GroupTitle(text: group.title)
                            if let rule = group.rule { Text(rule).font(.system(size: 11)).foregroundStyle(AppTheme.textHint) }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, capability in
                                if index > 0 { RowDivider() }
                                row(capability)
                                if capability == .courseArchive && store.enabled(.courseArchive) { archiveOptions }
                            }
                        }
                        .settingsCard(cornerRadius: 14, padding: 0)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 课程归档 sub-options (each toggle independent); outputs appear in 助教笔记.
    private var archiveOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ArchiveOutput.allCases) { o in
                Toggle(isOn: Binding(get: { store.saved.capabilities.isEnabled(o) }, set: {
                    store.saved.capabilities.set(o, enabled: $0); store.capabilityRevision = UUID(); store.persist()
                })) {
                    HStack(spacing: 6) {
                        Text(o.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Text(o.realtime ? "实时" : "课后")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .toggleStyle(.checkbox).controlSize(.small)
                .frame(height: 32)
            }
        }
        .padding(.leading, 52).padding(.trailing, 14).padding(.bottom, 8)
    }

    private func binding(_ capability: AssistantCapability) -> Binding<Bool> {
        Binding(get: { store.enabled(capability) }, set: { on in
            store.setCapability(capability, enabled: on)
        })
    }

    private func row(_ capability: AssistantCapability) -> some View {
        let isEnabled = store.enabled(capability)
        return HStack(spacing: 12) {
            Image(systemName: icon(for: capability))
                .font(.system(size: 15))
                .foregroundStyle(isEnabled ? AppTheme.accent : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(capability.title).font(.system(size: 13, weight: .medium))
                    if let tag = capability.tag {
                        Text(tag)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(AppTheme.accent.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(capability.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: binding(capability))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func icon(for capability: AssistantCapability) -> String {
        switch capability {
        case .questionRadar, .knowledgeAnswers: return "questionmark.bubble.fill"
        case .technicalAlerts: return "person.3.fill"
        case .messageDigest: return "text.bubble.fill"
        case .riskAlerts: return "exclamationmark.shield.fill"
        case .voiceInput: return "mic.fill"
        case .announcements: return "megaphone.fill"
        case .materials: return "doc.fill"
        case .welcomeRecap: return "hand.wave.fill"
        case .transcription: return "text.bubble.fill"
        case .quoteCards: return "quote.bubble.fill"
        case .courseArchive: return "archivebox.fill"
        }
    }
}

/// 「你可以这样说」 hint, shown in settings and in the 对助教说 card.
struct VoiceExamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("你可以这样说").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
            ForEach(CapabilitiesSettingsView.voiceExamples, id: \.self) { Text("「\($0)」").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary) }
        }
    }
}
