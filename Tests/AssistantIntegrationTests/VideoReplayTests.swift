import XCTest
import AssistantCore
@testable import Assistant

final class VideoReplayTests: XCTestCase {
    @MainActor func testFullVideoReplay() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_VIDEO_REPLAY"] == "1")
        let base = URL(fileURLWithPath:ProcessInfo.processInfo.environment["XB_VIDEO_REPLAY_DIR"] ?? "/tmp/xiaobao-video-replay")
        let output = base.appendingPathComponent("回放结果").appendingPathComponent(String(Int(Date().timeIntervalSince1970)))
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let original = try StateFile(url:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant/state.json")).read()
        let provider = try XCTUnwrap(original.providers.first { $0.id == original.defaultProviderID })
        let s = Store(preview:true,storageURL:output.appendingPathComponent("state.json"))
        s.saved.providers = [provider]; s.saved.defaultProviderID = provider.id
        s.providerKeys[provider.id] = Vault.read("provider." + provider.id.uuidString)
        s.jevKey = Vault.read("jev"); s.dashKey = Vault.read("dashscope")
        XCTAssertFalse(s.jevKey.isEmpty); XCTAssertFalse(s.dashKey.isEmpty)
        s.importLesson(base.appendingPathComponent(ProcessInfo.processInfo.environment["XB_REPLAY_LESSON"] ?? "课程资料.xblesson"))
        s.channel = "isolated-video-replay"; s.focus = "小学数学教资教学设计（视频回放测试）"
        s.demo = false; s.ensureCourse(); s.connected = true
        let courseID = try XCTUnwrap(s.currentCourseID)
        var outbox: [[String:Any]] = [], failures: [String] = []
        let began = Date()
        func capture(_ type: String, _ text: String, _ source: String = "") {
            outbox.append(["elapsed":Date().timeIntervalSince(began),"type":type,"text":text,"source":source,"delivery":"simulated"])
        }
        s.replyOverride = { text, message in capture("reply",text,message?.id ?? "") }
        s.recapSend = { capture("recap",$0) }
        s.quoteSend = { capture("knowledge",$0) }
        s.toolOverride = { name, args in
            guard ["mute_user","kick_user","unmute_user","restore_user"].contains(name) else { throw AppError.message("回放阻止未授权平台操作") }
            capture("moderation",name,args["user_id"] as? String ?? "")
            return ["simulated":true]
        }
        let voice = VoiceSession()
        voice.onFinal = { s.appendTranscript($0,courseID:courseID) }
        voice.failure = { failures.append($0) }
        defer { voice.cancel(); s.connected = false; s.recapTask?.cancel(); s.quoteLoopTask?.cancel(); s.runtimeTask?.cancel(); s.classroomWork.cancel(); s.cancelDataTasks() }
        await voice.start(key:s.dashKey,host:"dashscope.aliyuncs.com",externalAudio:true)
        for _ in 0..<200 {
            if voice.phase == "正在转写" || !failures.isEmpty { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard voice.phase == "正在转写" else { throw AppError.message("视频ASR未就绪：" + failures.joined(separator:"；")) }
        let pcm = try Data(contentsOf:URL(fileURLWithPath:"/tmp/math-replay.pcm"))
        let scenario = try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("scenario.json"))) as! [String:Any]
        let events = scenario["events"] as! [[String:Any]], viewers = scenario["viewers"] as! [[String:Any]]
        let names = Dictionary(uniqueKeysWithValues:viewers.map { ($0["id"] as! String,$0["name"] as! String) })
        let clock = Date()
        var eventIndex=0, audioOffset=0, joined=Set<String>(), left=Set<String>(), population: [[String:Any]] = [], lastProgress = -20, audioStopped=false
        var lastSpokenCheck=0, lastSpokenLength=0
        s.startRecapLoop(); s.startQuoteLoop(); s.startRuntimeLoop()
        func snapshot(_ elapsed: Int) throws {
            let course = try XCTUnwrap(s.currentCourse)
            let summary: [String:Any] = ["elapsed":elapsed,"messages_injected":eventIndex,"queue":s.pendingIncoming,"transcript_characters":course.transcript.count,"answers":course.answers.count,"pending_questions":s.messages.filter{$0.kind == .question}.count,"exercises":course.exercises?.count ?? 0,"asr_errors":failures,"model":provider.model,"output":output.path]
            try JSONSerialization.data(withJSONObject:summary,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("回放结果/progress.json"),options:.atomic)
            try JSONEncoder().encode(course).write(to:output.appendingPathComponent("course.json"),options:.atomic)
            let pending = s.messages.filter{$0.kind == .question || $0.kind == .risk || $0.kind == .technical}.map { m -> [String:Any] in
                ["id":m.id.uuidString,"kind":String(describing:m.kind),"question":m.question,"people":Array(m.people),"source_ids":m.sourceMessages.map(\.id),"source_texts":m.sourceMessages.map(\.text),"evaluating":m.evaluating,"error":m.error,"suggestion":m.suggestion?.draft ?? "","confirmation":m.suggestion?.confirmation ?? ""]
            }
            try JSONSerialization.data(withJSONObject:["pending":pending,"outbox":outbox,"asr_errors":failures,"simulated_chat_population":population],options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("results.json"),options:.atomic)
        }
        while Date().timeIntervalSince(clock) < 380 {
            let elapsed = Date().timeIntervalSince(clock)
            for v in viewers where !joined.contains(v["id"] as! String) && (v["join_at"] as! Int) <= Int(elapsed) {
                joined.insert(v["id"] as! String); s.newArrivals += 1; s.newArrivalTimes.append(Date()); population.append(["elapsed":elapsed,"viewer":v["id"]!,"action":"join","online":joined.count-left.count])
            }
            for v in viewers where joined.contains(v["id"] as! String) && !left.contains(v["id"] as! String) && (v["leave_at"] as? Int ?? 9999) <= Int(elapsed) {
                left.insert(v["id"] as! String); population.append(["elapsed":elapsed,"viewer":v["id"]!,"action":"leave","online":joined.count-left.count])
            }
            while eventIndex < events.count, (events[eventIndex]["at"] as! Int) <= Int(elapsed) {
                let e=events[eventIndex]; let uid=e["viewer"] as! String
                s.receive(.init(id:e["id"] as! String,userID:uid,name:names[uid]!,text:e["text"] as! String))
                eventIndex += 1
            }
            // Send the real video PCM at real-time speed (16kHz mono signed 16-bit).
            let target = min(pcm.count,Int(elapsed * 32000) / 2 * 2)
            while audioOffset < target {
                let end=min(target,audioOffset+6400)
                try await voice.appendStreamPCM(pcm.subdata(in:audioOffset..<end)); audioOffset=end
            }
            if audioOffset == pcm.count && !audioStopped { voice.stop(); audioStopped=true }
            if Int(elapsed)-lastSpokenCheck >= 10, (s.currentCourse?.transcript.count ?? 0)>lastSpokenLength {
                lastSpokenCheck=Int(elapsed); lastSpokenLength=s.currentCourse?.transcript.count ?? 0
                Task { await s.followSpokenAnswers() }
            }
            if Int(elapsed)-lastProgress >= 20 { lastProgress=Int(elapsed); try snapshot(Int(elapsed)) }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        s.recapTask?.cancel(); s.quoteLoopTask?.cancel(); s.runtimeTask?.cancel()
        for _ in 0..<1200 {
            if s.pendingIncoming == 0 && !s.notebookBusy && !s.recapBusy && !s.quoteSendBusy && !s.spokenFollowupBusy { break }
            try await Task.sleep(nanoseconds:100_000_000)
        }
        await s.notebookTick(courseID:courseID,final:true)
        if let i=s.courseIndex { s.saved.courses[i].ended=Date(); s.saved.courses[i].unanswered=s.messages.filter{$0.kind == .question}.map(\.question) }
        await s.generateArchive(courseID:courseID)
        try snapshot(Int(Date().timeIntervalSince(clock)))
        print("VIDEO_REPLAY_OUTPUT",output.path)
        XCTAssertEqual(eventIndex,64)
        XCTAssertGreaterThan(s.currentCourse?.transcript.count ?? 0,500)
        XCTAssertEqual(s.pendingIncoming,0,"Replay ended with unfinished work; report must preserve it")
    }
}
