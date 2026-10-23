import SwiftUI
import AppKit
import AssistantCore

extension Store {
    func ensureCourse() {
        guard currentCourseID == nil, !demo, !persistenceBlocked else { return }
        let date = Date().formatted(.dateTime.month().day().hour().minute())
        let title = focus.isEmpty ? "课程 · \(date)" : focus
        var course = CourseSession(title: title, channel: channel)
        course.startTimeVerified = false
        course.publicLibraryIDs = Array(libraryIDs)
        if let selectedPreparationID,
           let plan=preparations(channel).first(where:{$0.id == selectedPreparationID && $0.usedByCourseID == nil}) {
            course.candidatePreparationID=plan.id
            course.title=plan.title
            course.candidatePreparationUpdatedAt=plan.updatedAt
        }
        let directory = file.url.deletingLastPathComponent().appendingPathComponent("Courses").appendingPathComponent(course.id.uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let transcript = directory.appendingPathComponent("直播转写.txt")
            try Data().write(to: transcript, options: .atomic)
            course.recordingPath = transcript.path
            var updated=saved; updated.courses.insert(course,at:0)
            try file.write(updated)
            saved=updated; activities=[]; currentCourseID=course.id; selectedPreparationID=nil; attachLogToCourse(); persist()
        } catch { recordingError = "无法创建课程记录：\(error.localizedDescription)" }
    }
    /// Speech API configured → recording is always on in class (no toggle).
    var speechConfigured: Bool { !dashKey.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Called on class start: record automatically, or post a red stream message when speech isn't configured.
    func autoRecord() {
        guard speechConfigured else { error = "请在连接设置填写语音转写 API Key"; return }
        beginRecording()
    }
    func beginRecording() {
        guard require(.transcription) else { recordingError = error; return }
        guard !liveVoice.active, !voice.active else { return }
        if demo { error = "请结束交互预览后开始记录"; return }
        ensureCourse(); guard let courseID = currentCourseID else { return }
        recordingError = ""
        liveVoice.onFinal = { [weak self] text in self?.appendTranscript(text, courseID: courseID) }
        liveVoice.failure = { [weak self] text in self?.recordingError = text; self?.error = "讲课记录失败：" + text }
        liveVoice.completion = { [weak self] _ in
            guard let self else { return }
            if self.connected, self.speechConfigured, self.currentCourseID != nil, !self.pausedLiveForCommand { self.beginRecording() }
        }
        let client = self.client
        Task {
            guard currentCourseID == courseID, connected else { return }
            await liveVoice.start(key: client.dashKey, host: client.host, model: SpeechSettings.fixedModel)
        }
    }
    func resumeLiveRecording() {
        guard pausedLiveForCommand else { return }; pausedLiveForCommand = false
        if currentCourseID != nil { beginRecording() }
    }
    func cancelCommandVoice() { voiceRequestID = UUID(); voice.cancel(); resumeLiveRecording(); action = messages.isEmpty ? .idle : .alert }
    func finishCourse() {
        classroomCueTask?.cancel(); classroomCueTask = nil; classroomCueRun = nil; pendingClassroomCue = nil
        guard let id = currentCourseID, let i = saved.courses.firstIndex(where: { $0.id == id }) else { return }
        if liveVoice.active && liveVoice.phase != "识别中" { liveVoice.stop() }
        else if liveVoice.phase != "识别中" { liveVoice.cancel() }
        saved.courses[i].ended = Date()
        saved.courses[i].unanswered = messages.filter { $0.kind == .question }.map(\.question)
        currentCourseID = nil; quoteBuffer = ""; pausedLiveForCommand = false; persist()
        scheduleCourseDataSync(id); scheduleFinalCourseDataSync(id)
        if enabled(.courseArchive) { Task {
            for _ in 0..<160 { if !liveVoice.active && !notebookBusy { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
            while let course = saved.courses.first(where: { $0.id == id }), (course.notebookOffset ?? 0) < course.transcript.count {
                let before = course.notebookOffset ?? 0
                await notebookTick(courseID: id, final: true)
                if (saved.courses.first { $0.id == id }?.notebookOffset ?? 0) <= before { break }
            }
            await generateArchive(courseID: id)
        } }
    }
    /// 课程归档: produce each enabled output from the transcript with the default model; results show in 助教笔记.
    func generateArchive(courseID: UUID) async {
        guard let i = saved.courses.firstIndex(where: { $0.id == courseID }) else { return }
        let course = saved.courses[i]
        let transcript = course.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let qa = course.answers.map { "问：\($0.question)\n答：\($0.answer)" }.joined(separator: "\n")
        guard !transcript.isEmpty || !qa.isEmpty else { return }
        diagnostic("archive.started", ["course_id": courseID.uuidString])
        var failed: [String] = []
        for output in ArchiveOutput.allCases where !output.realtime && saved.capabilities.isEnabled(output) {
            guard enabled(.courseArchive) else { return }
            do {
                let text: String
                if let archiveGenerate { text = try await archiveGenerate(output, transcript, qa) }
                else {
                    let r = try await client.generate(system: AssistantPersona.prefix(style: saved.preferences.style) + output.prompt + "只依据给定的转写和问答，不编造。只输出JSON：{\"text\":\"内容\"}。", input: ["transcript": transcript, "qa": qa, "title": course.title])
                    text = (r["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard enabled(.courseArchive), saved.capabilities.isEnabled(output), !text.isEmpty, let j = saved.courses.firstIndex(where: { $0.id == courseID }) else { continue }
                saved.courses[j].outputs = (saved.courses[j].outputs ?? [:]).merging([output.rawValue: text]) { $1 }; persist(); diagnostic("archive.output.completed", ["course_id": courseID.uuidString, "output": output.rawValue, "characters": text.count])
            } catch { failed.append(output.rawValue) }
        }
        // Prior-class archive feedback must not land in a newer live bubble.
        let surface = currentCourseID == nil || currentCourseID == courseID
        if !failed.isEmpty {
            if surface { postError("课程归档未完成：\(failed.joined(separator: "、"))（请检查默认模型配置）") }
        } else if surface { flow("课程回顾已生成") }
    }
    func appendTranscript(_ text: String, courseID: UUID) {
        guard enabled(.transcription), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let i = saved.courses.firstIndex(where: { $0.id == courseID }) else { return }
        let line = text + "\n"
        diagnostic("transcript.final", ["course_id": courseID.uuidString, "characters": text.count])
        defer { observeClassroomCue(text, courseID: courseID) }
        saved.courses[i].transcript += line
        if saved.courses[i].transcriptSegments == nil { saved.courses[i].transcriptSegments = [] }; saved.courses[i].transcriptSegments?.append(TranscriptSegment(text: text))
        if let path = saved.courses[i].recordingPath {
            do {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path)); defer { try? handle.close() }
                try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8))
            } catch { recordingError = "转写文件保存失败：\(error.localizedDescription)" }
        }
        persist()
        if currentCourseID == courseID { quoteBuffer += line; scheduleSpokenFollowup() }
        // 知识点提炼 now runs on its own 4-minute loop (quoteTick) and sends to chat.
    }
    func makeQuote(courseID: UUID) {
        guard require(.quoteCards) else { recordingError = error; return }
        guard !quoteBusy, let i = saved.courses.firstIndex(where: { $0.id == courseID }) else { return }
        let source = quoteBuffer.isEmpty ? String(saved.courses[i].transcript.suffix(6000)) : quoteBuffer
        guard source.count >= 20 else { recordingError = "记录更多讲课内容后再整理"; return }
        quoteBusy = true; lastQuoteCheck = Date(); recordingError = ""; let client = self.client; let revision = capabilityRevision
        Task {
            defer { quoteBusy = false }
            do {
                guard let point = try await client.extractKnowledgePoint(source, alreadySent: saved.courses[i].cards.map(\.quote)) else { return }
                guard revision == capabilityRevision, enabled(.quoteCards), let index = saved.courses.firstIndex(where: { $0.id == courseID }), !saved.courses[index].cards.contains(where: { $0.quote == point.text }), let path = saved.courses[index].recordingPath else { return }
                let quote = point.text, title = "课堂知识点"
                let destination = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("知识点-\(UUID().uuidString.prefix(8)).png")
                try QuoteRenderer.save(title: title, quote: quote, course: saved.courses[index].title, to: destination)
                saved.courses[index].cards.append(QuoteCard(title: title, quote: quote, path: destination.path)); persist()
                let pending = PendingMessage(kind: .material, title: "知识点 · \(title)", question: quote, attachment: destination, requiredCapability: .quoteCards)
                messages.append(pending); liveQuotes.insert(LiveQuote(text: quote, cardPath: destination.path), at: 0); action = .alert; quoteBuffer = ""
            } catch { recordingError = error.localizedDescription }
        }
    }
    func recordAnswer(question: String, answer: String, actor: String = "助教", messages: [ClassroomMessage] = [], sources: String = "", spoken: SpokenAnswer? = nil, spokenAt: Date? = nil) {
        guard !answer.isEmpty, let i = courseIndex else { return }
        var record = CourseAnswer(question: question, answer: answer)
        record.actor = actor; record.sourceMessageIDs = messages.map(\.id); record.sources = sources
        record.spokenEvidence = spoken?.evidence; record.spokenSegmentIDs = spoken?.segmentIDs; record.spokenAt = spokenAt
        saved.courses[i].answers.append(record); refreshQA(saved.courses[i].id); persist()
    }
    func markCardSent(_ url: URL?) {
        guard let url else { return }
        for i in saved.courses.indices { for j in saved.courses[i].cards.indices where saved.courses[i].cards[j].path == url.path { saved.courses[i].cards[j].sent = true } }; persist()
    }
    func previewQuote(_ card: QuoteCard) {
        if let existing = messages.first(where: { $0.attachment?.path == card.path }) { open(existing.id); return }
        let message = PendingMessage(kind: .material, title: "知识点 · \(card.title)", question: card.quote, attachment: URL(fileURLWithPath: card.path), requiredCapability: .quoteCards); messages.append(message); open(message.id)
    }
    func courseText(_ course: CourseSession) -> String {
        var text = "# \(course.title)\n\n## 直播转写\n\n\(course.transcript)\n"
        if !course.answers.isEmpty { text += "\n## 课堂问答\n\n" + course.answers.map { "问：\($0.question)\n答：\($0.answer)" }.joined(separator: "\n\n") }
        if !course.cards.isEmpty { text += "\n\n## 知识点摘录\n\n" + course.cards.map { "### \($0.title)\n\($0.quote)" }.joined(separator: "\n\n") }
        if !course.unanswered.isEmpty { text += "\n\n## 未答问题\n\n" + course.unanswered.map { "- \($0)" }.joined(separator: "\n") }
        for output in ArchiveOutput.allCases { if let value = course.outputs?[output.rawValue], !value.isEmpty { text += "\n## \(output.title)\n\n\(value)\n" } }
        for exercise in course.exercises ?? [] { text += "\n### \(exercise.question)\n" + exercise.options.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n参考答案：\(exercise.correctIndices.map { String($0 + 1) }.joined(separator: ","))\n\(exercise.explanation)\n" }
        return text
    }
    func exportCourse(_ course: CourseSession) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = course.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.placeOnAssistantScreen()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try courseText(course).write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
    }
}
@MainActor enum QuoteRenderer {
    static func save(title: String, quote: String, course: String, to url: URL) throws {
        let image = NSImage(size: NSSize(width: 960, height: 720)); image.lockFocus()
        NSColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 960, height: 720).fill()
        NSColor(red: 0.32, green: 0.36, blue: 0.72, alpha: 1).setFill(); NSRect(x: 68, y: 592, width: 45, height: 5).fill()
        let ink = NSColor(red: 0.16, green: 0.18, blue: 0.23, alpha: 1)
        (title as NSString).draw(in: NSRect(x: 68, y: 520, width: 824, height: 56), withAttributes: [.font: NSFont.systemFont(ofSize: 28, weight: .medium), .foregroundColor: ink])
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 12; paragraph.lineBreakMode = .byWordWrapping
        let fontSize: CGFloat = quote.count > 100 ? 30 : 38
        (quote as NSString).draw(in: NSRect(x: 68, y: 145, width: 824, height: 340), withAttributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: ink, .paragraphStyle: paragraph])
        ("课堂摘录  ·  " + String(course.prefix(32)) as NSString).draw(in: NSRect(x: 68, y: 61, width: 824, height: 28), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.secondaryLabelColor])
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw AppError.message("卡片生成失败") }
        try png.write(to: url, options: .atomic)
    }
}
