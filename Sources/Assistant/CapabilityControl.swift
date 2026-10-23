import Foundation
import AppKit
import AssistantCore

extension Store {
    func enabled(_ capability: AssistantCapability) -> Bool { saved.capabilities.isEnabled(capability) }
    func setCapability(_ capability: AssistantCapability, enabled value: Bool) {
        saved.capabilities.set(capability, enabled: value)
        capabilityRevision = UUID()
        if value, capability == .welcomeRecap { uncertainActions.remove("recap") }
        if value, capability == .quoteCards { uncertainActions.remove("quote") }
        if !enabled(.transcription) { liveVoice.cancel(); pausedLiveForCommand = false }
        // Drop cards whose capability was just switched off.
        messages.removeAll { m in
            if let required = m.requiredCapability, !enabled(required) { return true }
            switch m.kind {
            case .question: return !enabled(.questionRadar) && m.requiredCapability == nil
            case .technical: return !enabled(.technicalAlerts)
            case .risk: return !enabled(.riskAlerts)
            default: return m.requiredCapability.map { !enabled($0) } ?? false
            }
        }

        persist()
    }
    func require(_ capability: AssistantCapability) -> Bool {
        guard enabled(capability) else { error = "「\(capability.title)」还没打开，去设置 › 助教能力里打开就能用"; return false }
        return true
    }
    func handlesCategory(_ category: String) -> Bool {
        switch category {
        case "question": return enabled(.questionRadar)
        case "technical": return enabled(.technicalAlerts)
        case "blocked": return enabled(.riskAlerts)
        default: return false
        }
    }
}

extension Store {
    func applyAppearance() {
        switch saved.preferences.appearance {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
}
