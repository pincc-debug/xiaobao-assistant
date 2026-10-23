import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import AssistantCore

struct GiftEvent: Identifiable { var id = UUID(); var time = Date(); var name: String; var gift: String; var count: Int; var value: Int = 1
    var big: Bool { value * count >= 100 } }
struct MaterialItem: Identifiable { var id = UUID(); var name: String; var symbol = "doc.text"; var file: URL? }
struct LiveQuote: Identifiable { var id = UUID(); var time = Date(); var text: String; var cardPath: String? }
struct LogEntry: Identifiable { var id = UUID(); var time = Date(); var kind: Kind; var text: String
    enum Kind { case answer, material, dismiss }
    var icon: String { switch kind { case .answer: return "text.bubble"; case .material: return "doc.badge.arrow.up"; case .dismiss: return "eye.slash" } } }
typealias HandledQA = OperationRecord
struct PendingMessage: Identifiable {
    var id = UUID()
    var kind: Kind = .question
    var title: String
    var question: String
    var draft = ""
    var people: Set<String> = []
    var sourceMessages: [ClassroomMessage] = []
    var source = ""
    var sourceLabels: [String] = []
    var error = ""
    var suggestion: LecturerSuggestion?
    var suggestionLoading = false
    var messageType: MessageType?
    var spokenMatch: SpokenAnswer?
    var spokenAt: Date?
    var busy = false
    var evaluating = false
    var libraryID: UUID?
    var attachment: URL?
    var requiredCapability: AssistantCapability?
    var time = Date()
    var lastTime = Date()
    var isError = false
    /// System-generated hint (not the assistant speaking) → neutral system avatar in the stream.
    var isSystem = false
    /// Three explicit message types:
    /// .reply  需要回复 — accumulated / high-frequency / urgent questions, material requests → 「回复」 opens the reply UI (pinned on top)
    /// .view   仅需查看 — feedback such as 「网络不好」, risk alerts → tap shows who reported, how many, time range
    /// .stream 仅消息流 — assistant's own posts (welcome etc.) → plain row, no action
    enum ResponseType { case reply, view, stream, processing }
    var responseType: ResponseType { if evaluating { return .processing }; switch kind { case .question, .material: return .reply; case .technical, .risk: return .view; case .notice: return .stream } }
    var pinned: Bool { responseType == .reply || responseType == .view }
    enum Kind { case question, notice, technical, risk, material }
    var button: String { switch kind { case .question: return "回答"; case .material: return "预览"; default: return "查看" } }
    var icon: String { switch kind { case .question: return "bubble.left.and.text.bubble.right"; case .notice: return "paperplane"; case .technical: return "wifi.exclamationmark"; case .risk: return "exclamationmark.shield"; case .material: return "doc" } }
}
@MainActor final class Store: ObservableObject {
    @Published var saved = SavedState()
    @Published var classroomReminders: [ClassroomReminder] = []
    @Published var notebookNavigationID = UUID()
    var notebookNavigationPending = false
    @Published var courseListRequest: UUID?
    func requestCourseListFromStart() {
        settingsPage = "教室"
        courseListRequest = UUID()
    }
    var requestedNotebookSection: NotebookSection = .questions
    var greetedCourses = Set<UUID>()
    /// Last-viewed settings page, persisted; first launch opens 助教能力 (通用 was removed; appearance lives in the sidebar).
    @Published var settingsPage = Store.restoredSettingsPage(UserDefaults.standard.string(forKey: Store.settingsPageKey)) {
        didSet { if settingsPage != oldValue { UserDefaults.standard.set(settingsPage, forKey: Store.settingsPageKey) } }
    }
    static let settingsPageKey = "settingsPage"
    static let settingsPages = ["形象与风格", "助教能力", "知识库", "教室", "连接与模型"]
    static func restoredSettingsPage(_ saved: String?) -> String {
        let saved = ["课程沉淀", "课程回顾", "历史沉淀"].contains(saved ?? "") ? "教室" : saved
        let page = (saved == "助教" || saved == "形象") ? "形象与风格" : saved   // older keys for this page
        return page.flatMap { settingsPages.contains($0) ? $0 : nil } ?? "形象与风格"
    }
    @Published var messages: [PendingMessage] = [] {
        didSet { if messages.count > oldValue.count { streamCardArrived() } }
    }
    /// Stream cards: a new card pops open, then folds into the 消息 button after this delay (paused while hovered).
    var streamCollapseDelay: TimeInterval = 5
    var cardsHovered = false
    private var streamTask: Task<Void, Never>?
    /// Single small form = the bubble. A new message just makes it visible again (no auto-fold, no second card).
    func streamCardArrived() {}
    @Published var selected: UUID?
    @Published var viewedMessage: PendingMessage?
    @Published var publicMessages: [ClassroomMessage] = []
    @Published var activities: [AssistantActivity] = []
    var channelOwnership = PolyvChannelOwnership()
    var connectionTask: Task<Void, Never>?
    var connectionAttempt = UUID()
    var questionBankTasks: [UUID: Task<Void, Never>] = [:]
    @Published var savingQuestions: Set<UUID> = []
    var questionBankOverride: ((String,String,[String:String]) async throws -> Any)?
    var statisticsPolling: Task<Void, Never>?
    var dataSyncTasks: [UUID: Task<Void, Never>] = [:]
    var finalDataSyncTasks: [UUID: Task<Void, Never>] = [:]
    var lastDataSyncAttempt: [UUID: Date] = [:]
    @Published var dataSyncBusy: Set<UUID> = []
    @Published var dataErrors: [UUID: String] = [:]
    var statisticsOverride: ((String, [String:String]) async throws -> Any)?
    @Published var roomStreamingText: [String: String] = [:]
    @Published var roomThinking: [String: RoomThinking] = [:]
    var roomStreamIDs: [String: UUID] = [:]
    var roomStreamUpdated: [String: Date] = [:]
    @Published var roomProgress: [String: String] = [:]
    @Published var roomErrors: [String: String] = [:]
    var roomTasks: [String: Task<Void, Never>] = [:]
    var roomRunIDs: [String: UUID] = [:]
    var roomAgentOverride: ((Any) async throws -> [String: Any])?
    @Published var lastDeletedCourses: [CourseSession] = []
    var deletedCoursesBackup: URL?
    var flowExpiryTask: Task<Void, Never>?
    var publicExpiryTask: Task<Void, Never>?
    var flowLifetime: Double = 20
    /// An LLM service is configured. Preview: configured unless --preview-no-model.
    var hasModel: Bool { CommandLine.arguments.contains("--preview") ? !CommandLine.arguments.contains("--preview-no-model") : !saved.providers.isEmpty }
    var canTalkToAssistant: Bool { (connected && currentCourseID != nil && !demo) || (demo && CommandLine.arguments.contains("--preview")) }   // preview flags simulate a configured model
    var answeredItems: [HandledQA] { handled.filter { $0.kind == "question" } }
    @Published var action = PetAction.idle
    @Published var status = "未连接"
    @Published var connected = false
    @Published var avatars: [String: String] = [:]
    /// Errors (missing keys / config, failed sends…) are never popped up: each one is posted into the bubble stream
    /// as an assistant message (仅消息流, red text). Inline contexts may still read `error`.
    @Published var error = "" { didSet { if !error.isEmpty, error != oldValue { postError(error) } } }
    @Published var notice = ""
    @Published var channel = ""
    @Published var libraryIDs: Set<UUID> = [] { didSet { if oldValue != libraryIDs { saved.selectedLibraryIDs = saved.libraries.map(\.id).filter { libraryIDs.contains($0) }; persist() } } }
    var libraryID: UUID? { saved.libraries.first { libraryIDs.contains($0.id) }?.id }
    @Published var gifts: [GiftEvent] = []
    @Published var materials: [MaterialItem] = [] // TODO: wire to course material source (no API yet)
    @Published var liveQuotes: [LiveQuote] = []
    @Published var log: [LogEntry] = []
    @Published var answeredCount = 0
    @Published var liveStart: Date?
    @Published var detailExpanded = false
    var detailMaximized: Bool { false }
    var pendingCollapsed: Bool { !detailExpanded }
    /// × on bubble / big card hides the surface (items are kept); a new message or the 消息 button shows it again.
    var messagesHidden: Bool { false }
    var showLessonCards: Bool { currentCourseID != nil }
    @Published var detailBoardHeight: CGFloat = 676
    /// Big card width (window minus the 22pt shadow margins); the grow / shrink anchor is the tail tip at this width.
    var detailBoardWidth: CGFloat = 520
    var pendingIsCompact: Bool { !detailExpanded }
    @Published var focus = ""
    @Published var selectedPreparationID: UUID?
    @Published var roomRunLesson: [String: UUID] = [:]
    @Published var demo = false
    @Published var busy = false
    @Published var command = ""
    @Published var commandVoiceVisible = false
    @Published var jevKey = ""
    @Published var dashKey = ""
    @Published var polyvSecret = ""
    @Published var providerKeys: [UUID: String] = [:]
    let voice = VoiceSession()
    let liveVoice = VoiceSession()
    @Published var currentCourseID: UUID?
    @Published var recordingError = ""
    @Published var quoteBusy = false
    var quoteBuffer = ""
    var lastQuoteCheck = Date.distantPast
    var pausedLiveForCommand = false
    var spokenFollowupTask: Task<Void, Never>?
    var spokenFollowupBusy = false
    var spokenFollowupSignature = ""
    var spokenClientOverride: ModelsClient?
    var suggestionClientOverride: ModelsClient?
    var runtimeTask: Task<Void, Never>?
    var interactionPolling: Task<Void, Never>?
    @Published var interactionBusy = Set<UUID>()
    var interactionAnalysisBusy = Set<UUID>()
    var interactionCallOverride: ((String, String, [Any]) async throws -> Any)?
    var interactionAnalysisOverride: ((LiveInteraction) async throws -> String)?
    var notebookBusy = false
    var digestBusy = false
    var digestThrough = Date.distantPast
    var lastNotebookCheck = Date.distantPast
    var lastDigestCheck = Date.distantPast
    var joinedUsers = Set<String>()
    var notebookGenerate: ((String) async throws -> [String: Any])?
    var classroomRiskReviewOverride: ((ClassroomMessage) async throws -> [String: Any])?
    var classroomDecisionOverride: (([String: Any]) async throws -> [String: Any])?
    var classifyMessage: ((ClassroomMessage, [(String, String)]) async throws -> (String, String))?
    var replyOverride: ((String, ClassroomMessage?) async throws -> Void)?
    var toolOverride: ((String, [String: Any]) async throws -> Any)?
    var commandDecisionOverride: ((Any) async throws -> [String: Any])?
    var exerciseDraftOverride: ((String, [RoomSource]) async throws -> [String: Any])?
    var classroomCueClassifierOverride: ((String) async throws -> String)?
    var classroomPointOverride: ((String) async throws -> [String: Any])?
    var classroomCueTask: Task<Void, Never>?
    var classroomCueRun: UUID?
    var pendingClassroomCue: (text: String, courseID: UUID)?
    var lastClassroomCue: (courseID: UUID, text: String, time: Date)?
    @Published var sendingExercises = Set<UUID>()
    @Published var exerciseSendErrors: [UUID: String] = [:]
    var exerciseSendTasks: [UUID: Task<Void, Never>] = [:]
    var commandHistory: [[String: Any]] = []
    let gateway = ChatGateway()
    lazy var interactions = InteractionBridge(gateway: gateway)

    lazy var supportLog = SupportLog(root: file.url.deletingLastPathComponent().appendingPathComponent("Logs"))
    let previewMode: Bool
    let file: StateFile
    var showCard: (() -> Void)?
    var showStart: (() -> Void)?
    var showBroadcastDesktop: (() -> Void)?
    @Published var broadcastLaunching = false
    var persistenceBlocked = false
    var epoch = UUID()
    var capabilityRevision = UUID()
    var incoming: [ClassroomMessage] = []
    var processing = false
    let classroomWork = ClassroomWorkQueue(limit: 4)
    private var sourceQuestion: UUID?
    var voiceRequestID = UUID()
    private var infoTask: Task<Void, Never>?
    var selectedLibraries: [KnowledgeBase] { saved.libraries.filter { libraryIDs.contains($0.id) } }
    var currentLibrary: KnowledgeBase? { SavedState.merged(selectedLibraries) }
    var libraryLabel: String {
        let names = selectedLibraries.map(\.name)
        if names.isEmpty { return "选择知识库" }
        return names.count > 2 ? names.prefix(2).joined(separator: "、") + " 等 \(names.count) 个" : names.joined(separator: "、")
    }
    var roomName: String { demo ? "交互预览" : (channel.isEmpty ? "直播间" : "频道 \(channel)") }
    var elapsedText: String {
        guard let liveStart else { return "未开播" }
        let m = max(0, Int(Date().timeIntervalSince(liveStart) / 60)); return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(m) 分钟"
    }
    func addLog(_ kind: LogEntry.Kind, _ text: String) { complete(OperationRecord(question: text, answer: text, kind: kind == .answer ? "question" : "action")); flow(text) }
    func ignore(_ id: UUID) {
        guard let m = messages.first(where: { $0.id == id }) else { return }
        var record = OperationRecord(question: m.question, people: m.people.sorted(), answer: "已忽略", actor: "主讲", kind: "dismiss", sourceMessageIDs: m.sourceMessages.map(\.id), sourceUserIDs: m.sourceMessages.map(\.userID))
        record.id = m.id
        if !m.sourceLabels.isEmpty { record.sources = m.sourceLabels }
        complete(record); dismiss(id); flow("已忽略：\(m.title)")
    }
    func review(_ id: UUID) {
        guard let m = messages.first(where: { $0.id == id }) else { return }
        viewedMessage = m
        var record = OperationRecord(question: m.question, people: m.people.sorted(), answer: "已查看", actor: "主讲", kind: "viewed", sourceMessageIDs: m.sourceMessages.map(\.id), sourceUserIDs: m.sourceMessages.map(\.userID))
        record.id = m.id; complete(record); dismiss(id)
    }
    func sendText(_ text: String, log kind: LogEntry.Kind, note: String) {
        let generation = epoch
        Task { do { _ = try await performTool("send_chat_message", arguments: ["content": text], generation: generation) } catch { if generation == epoch { postError(error.localizedDescription) } } }
    }
    /// Socket REWARD/FLOWERS event: recorded in the gift list only (auto-thanks was removed).
    func receiveGift(name: String, gift: String, count: Int) {
        gifts.insert(GiftEvent(name: name, gift: gift, count: count), at: 0)
    }
    // MARK: 欢迎总结 — every recapInterval, if viewers joined since the last check and there is transcript, send a short recap.
    var newArrivals = 0
    var recapInterval: Double = 60
    var newArrivalTimes: [Date] = []
    var recapTask: Task<Void, Never>?
    var uncertainActions = Set<String>()
    var recapBusy = false
    var quoteSendBusy = false
    /// Test seams (mocks); nil → real model + chat gateway.
    var recapGenerate: ((String) async throws -> String)?
    var recapSend: ((String) async throws -> Void)?
    var archiveGenerate: ((ArchiveOutput, String, String) async throws -> String)?
    func startRecapLoop() {
        if recapTask != nil { return }
        let interval = recapInterval
        recapTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.connected { await self.recapTick() }
            }
        }
    }
    /// One check. Returns the sent text (nil = skipped).
    @discardableResult func recapTick() async -> String? {
        guard !recapBusy else { return nil }; recapBusy = true; defer { recapBusy = false }
        let generation = epoch; let revision = capabilityRevision
        diagnostic("timer.welcome.check", ["arrivals": newArrivals])
        let arrivals = newArrivalTimes.isEmpty ? newArrivals : newArrivalTimes.filter { Date().timeIntervalSince($0) <= recapInterval }.count
        newArrivals = 0; newArrivalTimes = []
        guard enabled(.welcomeRecap), !uncertainActions.contains("recap"), arrivals > 0 else { return nil }
        let transcript = (currentCourseID.flatMap { id in saved.courses.first { $0.id == id } }?.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return nil }
        let excerpt = transcript
        var sending = false
        do {
            let text: String
            if let recapGenerate { text = try await recapGenerate(excerpt) }
            else {
                let r = try await client.generate(system: AssistantPersona.prefix(style: saved.preferences.style) + "有新观众刚进入直播间。根据讲师到目前为止的讲课转写，写一段简短的欢迎+前情回顾，发到聊天室：先一句欢迎，再用 2-4 个要点概括已讲内容，总长不超过 120 字；只依据转写，不编造，不新增承诺。输出JSON：{\"message\":\"文本\"}。", input: ["transcript": excerpt])
                text = (r["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !text.isEmpty, generation == epoch, revision == capabilityRevision, enabled(.welcomeRecap) else { return nil }
            sending = true
            if let recapSend { try await recapSend(text) } else { try await gateway.send(text) }
            guard generation == epoch else { return nil }
            complete(OperationRecord(question: "欢迎总结", answer: text, kind: "recap"))
            flow("已发送欢迎总结", detail: text)
            return text
        } catch { guard generation == epoch else { return nil }; if sending { uncertainActions.insert("recap") }; postError("欢迎总结发送失败：\(error.localizedDescription)"); return nil }
    }
    // MARK: 知识点提炼 — check every minute without an additional initial offset. Legacy quote keys remain for saved-state compatibility.
    var quoteInterval: Double = 60
    var quotePhaseOffset: Double = 0
    var quoteLoopTask: Task<Void, Never>?
    var sentQuotes: [String] = []
    var quoteGenerate: ((String, [String]) async throws -> String)?
    var quoteSend: ((String) async throws -> Void)?
    func startQuoteLoop() {
        if quoteLoopTask != nil { return }
        let interval = quoteInterval; let offset = quotePhaseOffset
        quoteLoopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(offset * 1_000_000_000))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.connected { await self.quoteTick() }
            }
        }
    }
    @discardableResult func quoteTick() async -> String? {
        diagnostic("timer.quote.check", ["buffer_characters": quoteBuffer.count])
        guard enabled(.quoteCards), !uncertainActions.contains("quote"), !quoteSendBusy else { return nil }
        quoteSendBusy = true; defer { quoteSendBusy = false }
        let source = String(quoteBuffer.prefix(6000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.count >= 20 else { return nil }   // nothing new since last check
        let generation = epoch; let revision = capabilityRevision
        var sending = false
        do {
            let point: GroundedPoint
            if let quoteGenerate {
                let text = try await quoteGenerate(source, sentQuotes).trimmingCharacters(in: .whitespacesAndNewlines)
                guard (10...160).contains(text.count), source.contains(text) else { return nil }
                point = GroundedPoint(text: text, evidence: text)
            } else {
                guard let extracted = try await client.extractKnowledgePoint(source, alreadySent: sentQuotes) else { return nil }
                point = extracted
            }
            let quote = point.text
            guard !sentQuotes.contains(quote), generation == epoch, revision == capabilityRevision, enabled(.quoteCards) else { return nil }
            let text = "【知识点】\(quote)"
            sending = true
            if let quoteSend { try await quoteSend(text) } else { try await gateway.send(text) }
            guard generation == epoch else { return nil }
            if quoteBuffer.hasPrefix(source) { quoteBuffer = String(quoteBuffer.dropFirst(source.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            sentQuotes.append(quote)
            if let i = courseIndex {
                if saved.courses[i].quotes == nil { saved.courses[i].quotes = [] }
                saved.courses[i].quotes?.append(quote)
                if saved.courses[i].knowledgePoints == nil { saved.courses[i].knowledgePoints = [] }
                if saved.courses[i].knowledgePoints?.contains(where: { $0.text == point.text || $0.evidence == point.evidence }) != true { saved.courses[i].knowledgePoints?.append(point) }
            }
            complete(OperationRecord(question: "知识点提炼", answer: quote, kind: "quote"))
            liveQuotes.insert(LiveQuote(text: quote, cardPath: nil), at: 0)
            flow("已发送知识点", detail: quote)
            return text
        } catch { guard generation == epoch else { return nil }; if sending { uncertainActions.insert("quote") }; postError("知识点发送失败：\(error.localizedDescription)"); return nil }
    }
    func sendMaterial(_ m: MaterialItem) {
        let generation = epoch
        Task { do { _ = try await performTool("send_material", arguments: ["material_id": m.id.uuidString], generation: generation) } catch { if generation == epoch { postError(error.localizedDescription) } } }
    }
    func setDetail(_ on: Bool) { guard !on || showLessonCards else { return }; detailExpanded = on }
    func collapsePending() { detailExpanded = false }
    func maximizeDetail() { setDetail(true) }
    func restoreDetail() { setDetail(true) }
    func dismissMessages() { collapsePending() }
    var knowledgePreparation: Task<Void, Never>?
    var knowledgeFingerprint = ""
    var knowledgeRetryAfter = Date.distantPast

    func scheduleKnowledgePreparation() {
        guard !previewMode, !persistenceBlocked, !dashKey.isEmpty, Date() >= knowledgeRetryAfter else { return }
        let library = answerLibrary
        let fingerprint = RetrievalIndex.key(dashKey + library.documents.map { $0.id.uuidString + $0.name + $0.text }.joined(separator: "\u{0}"))
        guard fingerprint != knowledgeFingerprint else { return }
        knowledgeFingerprint = fingerprint
        knowledgePreparation?.cancel()
        let client = self.client
        knowledgePreparation = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                try await client.prepareKnowledge(library)
                try Task.checkCancellation()
                self?.diagnostic("knowledge.index_ready", ["documents": library.documents.count])
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled else { return }
                self?.knowledgeFingerprint = ""
                self?.knowledgeRetryAfter = Date().addingTimeInterval(60)
                self?.diagnostic("knowledge.index_failed", ["message": error.localizedDescription], error: true)
            }
        }
    }

    var client: ModelsClient {
        let provider = saved.providers.first { $0.id == saved.defaultProviderID } ?? saved.providers.first
        return ModelsClient(preferences: saved.preferences, jevKey: jevKey, dashKey: dashKey, provider: provider, providerKey: provider.flatMap { providerKeys[$0.id] } ?? "")
    }
    init(preview: Bool = false, storageURL: URL? = nil) {
        previewMode = preview
        let root = preview ? FileManager.default.temporaryDirectory.appendingPathComponent("LiveAssistant-Preview") : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveAssistant")
        file = StateFile(url: storageURL ?? root.appendingPathComponent("state.json"))
        do { saved = try file.read() } catch { persistenceBlocked = true; self.error = "无法读取本地资料：\(error.localizedDescription)" }
        if !preview { jevKey = Vault.read("jev"); dashKey = Vault.read("dashscope"); polyvSecret = Vault.read("polyv") }
        if !preview { for provider in saved.providers { providerKeys[provider.id] = Vault.read("provider." + provider.id.uuidString) } }
        libraryIDs = []
        saved.speech.model = SpeechSettings.fixedModel; saved.preferences.region = SpeechSettings.fixedRegion
        loadMaterials()
        gateway.onStatus = { [weak self] status, connected in self?.diagnostic("connection.status", ["status": status, "connected": connected]); self?.status = status; self?.connected = connected; if !connected { self?.voiceRequestID = UUID(); self?.voice.cancel(); self?.commandVoiceVisible = false }; if connected { self?.error = ""; if self?.liveStart == nil { self?.liveStart = Date() }; self?.ensureCourse(); self?.attachLogToCourse(); self?.autoRecord(); self?.startRecapLoop(); self?.startQuoteLoop(); self?.startRuntimeLoop(); self?.announceClassStarted() } }
        gateway.onPublicChat = { [weak self] in self?.collectPublicChat($0) }
        gateway.onAvatar = { [weak self] name, pic in self?.avatars[name] = pic }
        gateway.onMessage = { [weak self] message in self?.receive(message) }
        gateway.onSession = { [weak self] id, start in self?.adoptSession(id, started: start) }
        gateway.onGift = { [weak self] name, gift, count in self?.receiveGift(name: name, gift: gift, count: count) }
        gateway.onJoin = { [weak self] id in guard let self, self.joinedUsers.insert(id).inserted else { return }; self.newArrivals += 1; self.newArrivalTimes.append(Date()) }
        voice.onDiagnostic = { [weak self] event, fields in self?.diagnostic("command_voice." + event, fields) }
        liveVoice.onDiagnostic = { [weak self] event, fields in self?.diagnostic("class_voice." + event, fields) }
        voice.failure = { [weak self] text in self?.error = text; self?.action = .puzzled; self?.resumeLiveRecording() }
        voice.completion = { [weak self] text in self?.voiceFinished(text) }
        scheduleKnowledgePreparation()
    }
    func persist() {
        guard !persistenceBlocked else { error = "本地资料损坏，已保留原文件，请先恢复备份"; return }
        do { try file.write(saved); scheduleKnowledgePreparation() } catch { self.error = "保存失败：\(error.localizedDescription)" }
    }
    var polyvConfigured: Bool {
        [saved.preferences.userID, saved.preferences.appID, polyvSecret]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    func saveConnections(section: String? = nil) {
        guard !persistenceBlocked else { error = "本地资料损坏，已保留原文件，请先恢复备份"; return }
        error = ""
        let trimmed: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if section == "消息判断", trimmed(jevKey).isEmpty { error = "请输入 API Key"; return }
        if section == "语音转写", trimmed(dashKey).isEmpty { error = "请输入 API Key"; return }
        if section == "保利威", !polyvConfigured { error = "请完整填写保利威 User ID、App ID 和 App Secret"; return }
        if previewMode { persist(); return }
        do {
            if section == nil || section == "消息判断" { try Vault.write(trimmed(jevKey), name: "jev") }
            if section == nil || section == "语音转写" { try Vault.write(trimmed(dashKey), name: "dashscope") }
            if section == nil || section == "保利威" { try Vault.write(trimmed(polyvSecret), name: "polyv") }
            try file.write(saved)
            scheduleKnowledgePreparation()
        } catch { self.error = error.localizedDescription }
    }
    func connect() {
        guard !busy else { return }
        guard let normalized = normalizedClassroomChannel(channel) else { error = "请输入有效频道号"; return }
        channel = normalized
        if selectedPreparationID != nil, roomRunIDs[channel] != nil { error = "请等待备课处理完成后再上课"; return }
        if let id = selectedPreparationID, !preparations(channel).contains(where: { $0.id == id && $0.usedByCourseID == nil }) { error = "课程已开课或不存在，请重新选择"; return }
        let requestedChannel = channel, preparationID = selectedPreparationID
        let account = channelAccount
        let attempt = UUID(); connectionAttempt = attempt
        busy = true; error = ""
        connectionTask = Task {
            defer { if connectionAttempt == attempt { busy = false; connectionTask = nil } }
            var connecting = false
            do {
                try await validateChannelOwnership(requestedChannel)
                guard connectionAttempt == attempt else { return }
                guard channel == requestedChannel, selectedPreparationID == preparationID, channelAccount == account else {
                    throw AppError.message("开课信息已变更，请重试")
                }
                if let id = preparationID {
                    guard roomRunIDs[channel] == nil, preparations(channel).contains(where: { $0.id == id && $0.usedByCourseID == nil }) else {
                        throw AppError.message("备课已变更，请重新选择")
                    }
                }
                detailExpanded = false
                supportLog.start(channel: channel)
                diagnostic("configuration", ["capabilities": AssistantCapability.allCases.filter { enabled($0) }.map(\.rawValue), "speech_configured": speechConfigured, "decision_configured": !jevKey.isEmpty, "answer_model": client.provider?.model ?? ""])
                if let c = currentCourse, c.channel != channel { finishCourse() }
                // New class (even same channel): clear bubble live state immediately; adoptSession may restore only if the same unfinished session reconnects.
                resetLiveBubbleState()
                loadMaterials(); demo = false; epoch = UUID()
                var preferences = saved.preferences
                preferences.appID = account.appID; preferences.userID = account.userID
                connecting = true
                try await gateway.connect(channel: requestedChannel, preferences: preferences, secret: account.secret)
            } catch {
                guard connectionAttempt == attempt, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                if connecting { status = "未连接" }
            }
        }
    }

    func stop() { classroomWork.cancel(); connectionAttempt = UUID(); connectionTask?.cancel(); connectionTask = nil; busy = false; statisticsPolling?.cancel(); statisticsPolling=nil; detailExpanded = false; flowExpiryTask?.cancel(); publicExpiryTask?.cancel(); diagnostic("session.stop"); voiceRequestID = UUID(); publicMessages = []; viewedMessage = nil; spokenFollowupTask?.cancel(); spokenFollowupTask = nil; runtimeTask?.cancel(); runtimeTask = nil; interactionPolling?.cancel(); interactionPolling = nil; interactions.reset(); joinedUsers = []; commandHistory = []; uncertainActions = []; finishCourse(); epoch = UUID(); gateway.disconnect(); incoming = []; messages = []; selected = nil; demo = false; voice.cancel(); commandVoiceVisible = false; action = .idle; liveStart = nil; recapTask?.cancel(); recapTask = nil; quoteLoopTask?.cancel(); quoteLoopTask = nil; sentQuotes = []; handled = []; newArrivals = 0; gifts = []; materials = []; liveQuotes = []; log = []; answeredCount = 0 }
    func demoSession() {
        stop(); demo = true; status = "交互预览"
        liveStart = Date().addingTimeInterval(-42 * 60); answeredCount = 6
        let now = Date()
        gifts = [GiftEvent(time: now.addingTimeInterval(-60), name: "小林", gift: "火箭", count: 1, value: 200), GiftEvent(time: now.addingTimeInterval(-180), name: "阿晨", gift: "鲜花", count: 12, value: 1), GiftEvent(time: now.addingTimeInterval(-420), name: "小周", gift: "点赞", count: 3, value: 1), GiftEvent(time: now.addingTimeInterval(-900), name: "小许", gift: "跑车", count: 1, value: 520)]
        materials = [MaterialItem(name: "第三章课件.pdf", symbol: "doc.richtext"), MaterialItem(name: "优惠政策一览.png", symbol: "photo"), MaterialItem(name: "课后练习.pdf", symbol: "doc.text"), MaterialItem(name: "报名链接", symbol: "link")]
        liveQuotes = [LiveQuote(time: now.addingTimeInterval(-300), text: "真正理解一个概念，不只是能够重复它的定义，而是能够在新的问题里使用它。"), LiveQuote(time: now.addingTimeInterval(-1200), text: "先把一件小事做透，再去想下一件。")]
        log = [LogEntry(time: now.addingTimeInterval(-120), kind: .answer, text: "以「\(assistantName)」回答了“回放在哪里”"), LogEntry(time: now.addingTimeInterval(-600), kind: .material, text: "发送了资料“第二章课件.pdf”"), LogEntry(time: now.addingTimeInterval(-840), kind: .dismiss, text: "忽略了一条广告消息")]
        messages = [PendingMessage(title: "回放在哪里？", question: "今天的课程结束后，在哪里看回放？", draft: "回放会在直播结束后 2 小时内上传到课程主页的「回放」栏。", people: ["小林", "小陈", "小周"]), PendingMessage(kind: .technical, title: "观众反馈声音偏小", question: "老师声音有点小，可以调大一点吗？", people: ["阿晨"]), PendingMessage(title: "课件可以下载吗？", question: "讲完以后能下载今天的课件吗？", people: ["小许", "小张"])]
        if previewMode {
            var course = CourseSession(title: "变量与函数", channel: "123456")
            course.started = liveStart ?? now; course.platformSessionID = "preview-session"; course.startTimeVerified = true
            course.transcript = "变量用于存储数据，函数用于封装可复用的操作。学习编程需要通过实际操作理解概念。"
            course.exercises = [Exercise(question: "变量的主要作用是什么？", options: ["存储数据", "封装操作", "运行程序"], correctIndices: [0], explanation: "变量用于存储数据，函数用于封装可复用的操作。", evidence: "变量用于存储数据，函数用于封装可复用的操作")]
            course.knowledgePoints = [GroundedPoint(text: "变量存储数据，函数封装操作。", evidence: course.transcript)]
            course.outputs = [ArchiveOutput.keyPoints.rawValue: "变量存储数据，函数封装操作。", ArchiveOutput.faq.rawValue: "问：变量有什么用？\n答：变量用于存储数据。"]
            course.answers = [CourseAnswer(question: "变量有什么用？", answer: "变量用于存储数据。")]; course.answers[0].sources = "《Python 入门讲义》、FAQ · 变量有什么用？"
            course.operations = [OperationRecord(question: "变量有什么用？", people: ["小周"], answer: "变量用于存储数据。", actor: "助教")]; course.operations?[0].sources = ["《Python 入门讲义》", "FAQ · 变量有什么用？"]
            saved.courses = [course]; currentCourseID = course.id; handled = course.operations ?? []
            publicMessages = [ClassroomMessage(id: "preview-chat", userID: "preview-viewer", name: "小周", text: "我先把刚才的内容记下来。")]
            // One reply line for the default preview; harness can add more with --reply-feed.
            flow(Self.replyActivityTitle(nickname: "小周", question: "变量有什么用？"))
        }
        action = .alert
    }
    func open(_ id: UUID) { selected = id; error = ""; showCard?() }
    func dismiss(_ id: UUID) { messages.removeAll { $0.id == id }; if selected == id { selected = nil }; if messages.isEmpty { action = .idle } }
    /// First item of the message stream on launch (replaces opening Settings and the launch toast).
    func postError(_ text: String) {
        diagnostic("application.error", ["message": text], error: true)
        activity("任务执行", "任务未完成", status: "失败", source: text)
        flow("处理失败", detail: text)
        if let i = messages.lastIndex(where: { $0.responseType == .stream }) { messages[i].isError = true }
    }
    /// Badge = unhandled 需要回复 + 仅需查看 items only; 仅消息流 (assistant posts, welcome) never counts.
    /// 待答 everywhere = questions + material requests that are shown (same as classroomQuestionCount).
    var pendingQuestionCount: Int { classroomQuestionCount }
    var badgeCount: Int { messages.filter(\.pinned).count }
    /// 课堂 tab counts — exactly the rows its groups show: 待答问题 = questions + material requests, 课堂反馈 = feedback + violations
    /// (items still being evaluated are not shown, so not counted).
    var classroomQuestionCount: Int { messages.filter { $0.responseType == .reply }.count }
    var classroomFeedbackCount: Int { messages.filter { $0.responseType == .view }.count }
    /// Measured bubble parts (header+pinned, activity stream) for the content-fit bubble height.
    @Published var bubbleTopH: CGFloat = 0
    @Published var bubbleStreamH: CGFloat = 0
    var hasDisplayMessages: Bool { messages.contains { $0.responseType != .processing } }
    /// 「助教昵称」 from settings — the assistant's name everywhere (falls back to 小保).
    var assistantName: String { let n = saved.preferences.nickname.trimmingCharacters(in: .whitespacesAndNewlines); return n.isEmpty ? "小保" : n }
    /// System hints (e.g. 对助教说 examples) go into the stream with the system avatar; deduped while still the latest.
    func postSystem(_ title: String, _ text: String) {
        if let last = messages.last(where: { $0.responseType == .stream }), last.isSystem, last.title == title, last.question == text { return }
        var m = PendingMessage(kind: .notice, title: title, question: text); m.isSystem = true
        messages.removeAll { $0.responseType == .stream }; log = []; messages.append(m)
    }
    func insertWelcome() {
        let setup = saved.libraries.isEmpty ? "先在 ⚙︎ 设置里配置模型和知识库，" : ""
        messages.insert(PendingMessage(kind: .notice, title: "你好，我是\(assistantName)", question: setup + "点工具栏 ▶ 开始上课；有新消息会出现在这里。"), at: 0)
    }
    func toast(_ text: String, seconds: Double = 5) {
        infoTask?.cancel(); notice = text
        infoTask = Task { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)); if !Task.isCancelled { notice = ""; if !voice.active && !processing { action = messages.isEmpty ? .idle : .alert } } }
    }
    @Published var handled: [HandledQA] = []
    func send(_ id: UUID, auto: Bool = false, draftOverride: String? = nil) {
        guard let i = messages.firstIndex(where: { $0.id == id }), !messages[i].busy else { return }
        var m = messages[i]
        if let draftOverride { m.draft = draftOverride }
        guard m.requiredCapability.map({ enabled($0) }) ?? true else { return }
        let draft = m.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty || m.attachment != nil else { messages[i].error = "请输入回答"; return }
        if demo { completeMessage(m, auto: auto); toast("预览完成，未发送到聊天室"); return }
        messages[i].busy = true; messages[i].error = ""; action = .typing
        let generation = epoch; let targetCourseID = currentCourseID
        diagnostic("reply.started", ["id": id.uuidString, "automatic": auto]); flow("正在发送…")
        Task {
            do {
                if let attachment = m.attachment { try await gateway.sendFile(attachment, userID: saved.preferences.userID) }
                else { try await reply(draft, to: m.sourceMessages.first) }
                guard epoch == generation else {
                    complete(OperationRecord(question: m.question, people: m.people.sorted(), answer: m.attachment?.lastPathComponent ?? draft, actor: auto ? "助教" : "主讲", kind: m.kind == .question ? "question" : "material", sourceMessageIDs: m.sourceMessages.map(\.id), sourceUserIDs: m.sourceMessages.map(\.userID)), courseID: targetCourseID)
                    return
                }
                completeMessage(m, auto: auto)
            } catch { guard epoch == generation else { return }; if let j = messages.firstIndex(where: { $0.id == id && $0.time == m.time }) { messages[j].busy = false; messages[j].error = error.localizedDescription }; postError(error.localizedDescription) }
        }
    }
    func completeMessage(_ m: PendingMessage, auto: Bool) {
        diagnostic("reply.completed", ["id": m.id.uuidString, "automatic": auto, "characters": m.draft.count])
        var m = m
        let superseded = messages.contains { $0.id == m.id && $0.time != m.time }
        if let latest = messages.first(where: { $0.id == m.id && $0.time == m.time }) { m.people = latest.people; m.sourceMessages = latest.sourceMessages }
        let spoken = m.spokenMatch.flatMap { "老师刚刚说明：" + $0.answer == m.draft ? $0 : nil }
        var record = OperationRecord(question: m.question, people: m.people.sorted(), answer: m.attachment?.lastPathComponent ?? m.draft, actor: spoken != nil ? "主讲口述，助教整理" : auto ? "助教" : "主讲", kind: m.kind == .question ? "question" : "material", sourceMessageIDs: m.sourceMessages.map(\.id), sourceUserIDs: m.sourceMessages.map(\.userID))
        record.id = m.id
        complete(record)
        if m.kind == .question { recordAnswer(question: m.question, answer: m.draft, actor: record.actor, messages: m.sourceMessages, sources: m.source, spoken: spoken, spokenAt: m.spokenAt) }
        markCardSent(m.attachment); if !superseded { dismiss(m.id) }; action = .done
        if m.attachment != nil {
            flow("已发送：\(m.attachment!.lastPathComponent)")
        } else {
            flow(Self.replyActivityTitle(nickname: Self.replyNickname(from: m), question: Self.replyQuestion(from: m)))
        }
    }
    /// Nickname for a reply activity line: the person we actually replied to (first source message), else the sole
    /// person in `people`. Never pick one name out of several — that would invent who was answered.
    static func replyNickname(from m: PendingMessage) -> String? {
        if let name = m.sourceMessages.first?.name.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if m.people.count == 1, let name = m.people.first?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return nil
    }
    static func replyQuestion(from m: PendingMessage) -> String? {
        let q = m.question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty { return q }
        let t = m.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    /// `已回复 {nickname} · {question}` with whatever pieces we have; never invent missing fields.
    static func replyActivityTitle(nickname: String?, question: String?) -> String {
        let nick = (nickname ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let q = (question ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (!nick.isEmpty, !q.isEmpty) {
        case (true, true): return "已回复 \(nick) · \(q)"
        case (true, false): return "已回复 \(nick)"
        case (false, true): return "已回复 · \(q)"
        case (false, false): return "已回复"
        }
    }
    /// Stream rows still inside the display window, oldest→newest, capped at `limit` (newest kept).
    static func recentStreamMessages(_ messages: [PendingMessage], now: Date = Date(), lifetime: Double, limit: Int) -> [PendingMessage] {
        let live = messages.filter { $0.responseType == .stream && now.timeIntervalSince($0.time) < lifetime }
        return Array(live.suffix(max(limit, 0)))
    }
    func reply(_ text: String, to message: ClassroomMessage?) async throws {
        if let replyOverride { try await replyOverride(text, message) }
        else { try await gateway.send(text, replyingTo: message) }
    }
    static let chatCapabilities: [AssistantCapability] = [.questionRadar, .technicalAlerts, .riskAlerts, .messageDigest]
    var pendingIncoming: Int { incoming.count + (processing ? 1 : 0) + classroomWork.count }
    func receive(id: String, name: String, text: String) { receive(ClassroomMessage(id: id, userID: id, name: name, text: text)) }
    func receive(_ message: ClassroomMessage) {
        guard !message.text.isEmpty, message.text.count <= 6000 else { return }
        ensureCourse()
        if let i = courseIndex {
            if saved.courses[i].events?.contains(where: { $0.id == message.id }) == true { return }
            if saved.courses[i].events == nil { saved.courses[i].events = [] }
            saved.courses[i].events?.append(message); persist()
        }
        diagnostic("message.received", ["message_id": message.id, "characters": message.text.count])
        incoming.append(message); drain()
    }
    func drain() {
        guard !processing, !incoming.isEmpty else { return }; processing = true
        let generation = epoch; let item = incoming.removeFirst()
        Task {
            defer { processing = false; drain() }
            do {
                let recentPending = messages.filter {  $0.responseType != .stream && Date().timeIntervalSince($0.lastTime) < 300 }
                let recentHandled = handled.filter { ["question", "dismiss", "viewed"].contains($0.kind) && Date().timeIntervalSince($0.time) < ($0.kind == "question" ? 180 : 300) }
                let groups = classroomWork.groups + recentPending.map { ($0.id.uuidString, $0.question) } + recentHandled.map { ($0.id.uuidString, $0.question) }
                let result: (String, String)
                if let classifyMessage { result = try await classifyMessage(item, groups) }
                else if classroomDecisionOverride != nil { result = ("question", "none") } // isolated harness tests
                else { result = try await client.classify(item.text, groups: groups, focus: (currentCourse?.preparation.map { $0.title + "\n" + $0.goals } ?? focus) + "\n" + String((currentCourse?.transcript ?? "").suffix(2500))) }
                guard generation == epoch else { return }
                if result.0 == "chat" {
                    if let ci = courseIndex, let mi = saved.courses[ci].events?.firstIndex(where: { $0.id == item.id }) { saved.courses[ci].events?[mi].category = "chat"; persist() }
                    activity("消息判断", "普通聊天 → 略过", status: "已略过", source: item.text, messageID: item.id)
                    showPublicMessage(item); return
                }
                let key = result.0 == "blocked" ? "risk:" + item.userID : (result.1 == "none" ? UUID().uuidString : result.1)
                classroomWork.enqueue(key:key, question:item.text) { [self] in
                    guard generation == epoch, !Task.isCancelled else { return }
                    await processClassifiedMessage(item, classification:(result.0,key), generation:generation)
                }
            } catch { retainClassroomFailure(item, error:error, generation:generation) }
        }
    }

    func processClassifiedMessage(_ item: ClassroomMessage, classification: (String, String), generation: UUID) async {
        do {
            var result = (classification.0 == "feedback" ? "technical" : classification.0, classification.1)
            var route: ClassroomRoute?
            var priorSendInFlight = false
            if (classifyMessage == nil && client.provider != nil) || classroomDecisionOverride != nil {
                let reservedID = UUID(uuidString:classification.1)
                let proposedID = (currentCourse?.classroomIssues ?? []).contains { $0.id == reservedID } ? nil : reservedID
                let planned: ClassroomRoute
                let knownGroup = (currentCourse?.classroomIssues ?? []).contains { $0.id == reservedID } || messages.contains { $0.id == reservedID } || handled.contains { $0.id == reservedID }
                if classroomDecisionOverride == nil, !knownGroup, let kind = ClassroomIssue.Kind(rawValue: classification.0) {
                    // A clear new item already has a decision. Do not ask the LLM to classify it again.
                    var issue = ClassroomIssue(id: reservedID ?? UUID(), kind:kind, title:String(item.text.prefix(100)), at:item.time)
                    try issue.receive(item, relation:.new)
                    planned = ClassroomRoute(category:classification.0, issue:issue)
                } else {
                    planned = try await planClassroomMessage(item, generation:generation, proposedID:proposedID)
                }
                route = planned
                result = (planned.category == "feedback" ? "technical" : planned.category, planned.issue?.id.uuidString ?? classification.1)
            }
                guard generation == epoch else { return }
                diagnostic("message.classified", ["message_id": item.id, "category": result.0, "cluster_id": result.1])
                if let ci = courseIndex, let mi = saved.courses[ci].events?.firstIndex(where: { $0.id == item.id }) { saved.courses[ci].events?[mi].category = result.0; persist() }
                if result.0 == "chat" { activity("消息判断", "普通聊天 → 略过", status: "已略过", source: item.text, messageID: item.id); showPublicMessage(item); return }
                if result.0 == "uncertain" { messages.append(PendingMessage(kind: .risk, title: "待判断", question: item.text, people: [item.name], sourceMessages: [item])); activity("消息判断", "判断不明确，不自动处罚", status: "已略过", source: item.text, messageID: item.id); return }
                activity("消息判断", result.0 == "question" ? "课程提问 → 检索回答依据" : result.0 == "technical" ? "异常反馈 → 提醒主讲" : "疑似违规 → 核实处理程度", source: item.text, messageID: item.id)
                guard handlesCategory(result.0) else { return }
                if let issue = route?.issue {
                    saveClassroomIssue(issue)
                    if route?.relation == .recovered {
                        if issue.status == .resolved { dismiss(issue.id) }
                        else if let i = messages.firstIndex(where: { $0.id == issue.id }) {
                            messages[i].sourceMessages = issue.messages
                            messages[i].title = "仍有 \(issue.activeParticipants.count) 人待跟进"
                        }
                        activity("反馈更新", issue.status == .resolved ? "已反馈观众均报告恢复" : "部分观众恢复，仍需关注", source: item.text, messageID: item.id)
                        return
                    }
                    if route?.relation == .followup {
                        priorSendInFlight = messages.contains { $0.id == issue.id && $0.busy }
                        messages.removeAll { $0.id == issue.id }
                    }
                }
                if result.0 == "blocked" { await moderate(item, generation: generation); return }
                if let i = messages.firstIndex(where: { $0.id.uuidString == result.1 && !$0.isError }) {
                    if !messages[i].sourceMessages.contains(where: { $0.id == item.id }) { messages[i].sourceMessages.append(item) }
                    messages[i].people = Set(messages[i].sourceMessages.map { $0.userID }).reduce(into: Set<String>()) { names, id in
                        let name = messages[i].sourceMessages.first { $0.userID == id }?.name ?? "观众"; names.insert(name + (names.contains(name) ? " · " + String(id.suffix(4)) : ""))
                    }
                    messages[i].lastTime = Date(); activity("问题聚合", "已合并同类消息，\(messages[i].people.count) 人", source: item.text, messageID: item.id); diagnostic("message.merged", ["message_id": item.id, "cluster_id": result.1, "people": messages[i].people.count]); return
                }
                if route?.relation != .followup, route?.issue?.kind != .technical, route?.issue?.kind != .feedback, let i = handled.firstIndex(where: { $0.id.uuidString == result.1 }), result.0 == "question" || ["dismiss", "viewed"].contains(handled[i].kind) {
                    if !handled[i].sourceUserIDs.contains(item.userID) { handled[i].people.append(item.name); handled[i].sourceUserIDs.append(item.userID) }
                    handled[i].sourceMessageIDs.append(item.id); persistHandled(); activity("问题聚合", "关联到近期已处理事项，不重复发送", source: item.text, messageID: item.id); return
                }
                let kind: PendingMessage.Kind = result.0 == "technical" ? .technical : .question
                var pending = PendingMessage(kind: kind, title: String(item.text.prefix(36)), question: item.text, people: [item.name], sourceMessages: [item], libraryID: libraryID)
                if route == nil, let id = UUID(uuidString: result.1) { pending.id = id }
                if let issue = route?.issue {
                    pending.id = issue.id
                    if route?.relation == .followup { pending.question = issue.title + "\n观众追问：" + item.text }
                    pending.sourceMessages = route?.relation == .followup ? [item] + issue.messages.filter { $0.id != item.id } : issue.messages
                    pending.people = Self.issuePeople(issue.messages)
                }
                pending.evaluating = kind == .question && enabled(.knowledgeAnswers) && !priorSendInFlight
                messages.append(pending)
                guard kind == .question, enabled(.knowledgeAnswers), !priorSendInFlight else { return }
                // Answer generation does not block classification of later feedback.
                let answerQuestion = pending.question
                let pendingID = pending.id; let pendingCreatedAt = pending.time; let revision = capabilityRevision
                classroomWork.enqueue(key: pendingID.uuidString, question: pending.question) { [self] in
                    guard epoch == generation, !Task.isCancelled else { return }
                    var retrievedPassages: [Passage] = []
                    do {
                        scheduleKnowledgePreparation()
                        let library = answerLibrary
                        activity("知识库检索", "正在查找回答依据", status: "处理中", source: item.text, messageID: item.id)
                        guard let answer = try await client.answer(answerQuestion, library: library, trace: { stage, fields in
                            guard self.epoch == generation else { return }
                            self.diagnostic("answer." + stage, fields.merging(["message_id": item.id]) { $1 })
                            if stage == "retrieved" { self.activity("知识库检索", "命中 \(fields["count"] ?? 0) 个片段：" + ((fields["documents"] as? [String]) ?? []).joined(separator: "、"), source: item.text, messageID: item.id) }
                            if stage == "retrieval_fallback" { self.activity("知识库检索", fields["reason"] as? String ?? "检索降级", status: "降级", source: item.text, messageID: item.id) }
                            if stage == "rejected" { self.activity("答案校验", fields["reason"] as? String ?? "资料不足", status: "待主讲", source: item.text, messageID: item.id) }
                        }, onRetrieved: { retrievedPassages = $0 }) else { guard epoch == generation, revision == capabilityRevision, messages.contains(where: { $0.id == pendingID && $0.time == pendingCreatedAt }) else { return }; escalateQuestion(pendingID); activity("自动答疑", "没有可靠依据 → 转交主讲", status: "待主讲", source: item.text, messageID: item.id); diagnostic("answer.unavailable", ["message_id": item.id, "reason": "no_grounded_answer"]); await prepareLecturerSuggestion(pendingID, passages: retrievedPassages, generation: generation, revision: revision); return }
                        guard epoch == generation, revision == capabilityRevision, enabled(.knowledgeAnswers), let i = messages.firstIndex(where: { $0.id == pendingID && $0.time == pendingCreatedAt }), !messages[i].busy, messages[i].draft.isEmpty else { return }
                        var pending = messages[i]; pending.draft = answer.0; pending.sourceLabels = Knowledge.sourceLabels(answer.1); pending.source = pending.sourceLabels.joined(separator: "、")
                        activity("知识库检索", "找到依据：" + pending.source, source: item.text, messageID: item.id)
                        messages[i] = pending; send(pendingID, auto: true)
                    } catch { guard epoch == generation, let i = messages.firstIndex(where: { $0.id == pendingID && $0.time == pendingCreatedAt }) else { return }; messages[i].evaluating = false; streamCardArrived(); postError(error.localizedDescription); diagnostic("answer.failed", ["message_id": item.id, "message": error.localizedDescription], error: true) }
                }
        } catch { retainClassroomFailure(item, error:error, generation:generation) }
    }

    func retainClassroomFailure(_ item: ClassroomMessage, error: Error, generation: UUID) {
        guard epoch == generation, !(error is CancellationError) else { return }
        if let ci = courseIndex, let mi = saved.courses[ci].events?.firstIndex(where: { $0.id == item.id }) { saved.courses[ci].events?[mi].category = "uncertain"; persist() }
        messages.append(PendingMessage(kind:.risk,title:"消息待重查",question:item.text,people:[item.name],sourceMessages:[item],error:error.localizedDescription))
        activity("消息判断", "判断失败，保留待处理事项",status:"失败",source:item.text,messageID:item.id)
        postError(error.localizedDescription)
    }

    func escalateQuestion(_ id: UUID) { scheduleSpokenFollowup(); if let i = messages.firstIndex(where: { $0.id == id }) { messages[i].evaluating = false; action = .alert; streamCardArrived() } }
    func talkToAssistant() {
        guard canTalkToAssistant, !busy else { return }
        if voice.active { voice.stop(); return }
        voice.transcript = ""; error = ""
        commandVoiceVisible = true
        postSystem("对助教说", "你可以这样说：" + CapabilitiesSettingsView.voiceExamples.map { "「\($0)」" }.joined(separator: "、"))
        startVoice()
    }
    func dismissVoiceFeedback() {
        guard !busy else { return }
        cancelCommandVoice(); commandVoiceVisible = false
    }
    func startVoice(question: UUID? = nil) {
        guard canTalkToAssistant else { return }
        guard require(.voiceInput) else { return }
        if voice.active { voice.stop(); return }
        if question != nil { commandVoiceVisible = false }
        sourceQuestion = question; error = ""; action = .listening
        voiceRequestID = UUID(); let request = voiceRequestID
        if liveVoice.active { pausedLiveForCommand = true; liveVoice.stop() }
        let client = self.client
        Task {
            for _ in 0..<120 {
                if !liveVoice.active { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard request == voiceRequestID else { return }
            if liveVoice.active { liveVoice.cancel() }
            await voice.start(key: client.dashKey, host: client.host, model: SpeechSettings.fixedModel)
        }
    }
    private func voiceFinished(_ text: String) {
        diagnostic("command.transcribed", ["voice_request_id": voiceRequestID.uuidString, "text": text, "destination": sourceQuestion == nil ? "command" : "reply"])
        resumeLiveRecording()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sourceQuestion = nil; commandVoiceVisible = false
            action = messages.isEmpty ? .idle : .alert
            return
        }
        let target = sourceQuestion; sourceQuestion = nil
        if let target, let i = messages.firstIndex(where: { $0.id == target }) { messages[i].draft = text; action = .done; return }
        command = text; interpretCommand()
    }
    nonisolated static let commandProcessingTitle = "正在处理指令…"
    func interpretCommand() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canTalkToAssistant, !text.isEmpty, !busy else { return }
        busy = true; commandVoiceVisible = false; let generation = epoch
        flow(Self.commandProcessingTitle, detail: text)   // the instructor's own words show under it
        Task { defer { busy = false }; await runCommand(text, generation: generation) }
    }
    func chooseAttachment() {
        guard require(.materials) else { return }
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.pdf, .png, .jpeg]; picker.canChooseDirectories = false
        guard picker.runModal() == .OK, let source = picker.url else { action = .idle; return }
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20_000_000 else { throw AppError.message("文件不能超过 20 MB") }
            let folder = file.url.deletingLastPathComponent().appendingPathComponent("Attachments").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: destination)
            let message = PendingMessage(kind: .material, title: "待发送资料", question: source.lastPathComponent, attachment: destination)
            messages.append(message); action = .alert; open(message.id)
        } catch { self.error = error.localizedDescription }
    }
    func addLibrary() { let library = KnowledgeBase(name: "新知识库"); saved.libraries.append(library); libraryIDs.insert(library.id); persist() }
    func importDocument(into id: UUID) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .pdf, .rtf, UTType(filenameExtension: "md") ?? .text]; panel.allowsMultipleSelection = true
        panel.placeOnAssistantScreen()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size < 20_000_000 else { throw AppError.message("文件不能超过 20 MB") }
                let text: String
                if url.pathExtension.lowercased() == "pdf" { text = PDFDocument(url: url)?.string ?? "" }
                else if url.pathExtension.lowercased() == "rtf" { text = try NSAttributedString(url: url, options: [:], documentAttributes: nil).string }
                else { text = try String(contentsOf: url, encoding: .utf8) }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("未读取到文本，请使用文字版资料") }
                guard text.count <= 100_000 else { throw AppError.message("单份资料不能超过 10 万字") }
                guard let index = saved.libraries.firstIndex(where: { $0.id == id }) else { return }
                saved.libraries[index].documents.append(Document(name: url.lastPathComponent, text: text)); persist()
            } catch { self.error = "\(url.lastPathComponent)：\(error.localizedDescription)" }
        }
    }
}
