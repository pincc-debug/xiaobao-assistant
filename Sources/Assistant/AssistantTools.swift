import Foundation
import AssistantCore

struct AssistantTool {
    let name: String
    let title: String
    let properties: [String: [String: Any]]
    var required: [String] { properties.keys.sorted() }
    var schema: [String: Any] { ["type": "object", "properties": properties, "required": required, "additionalProperties": false] }
    var definition: [String: Any] { ["name": name, "description": title, "parameters": schema] }
    static func string(_ description: String) -> [String: Any] { ["type": "string", "description": description, "minLength": 1, "maxLength": 2000] }
    static func duration(_ max: Int) -> [String: Any] { ["type": "integer", "minimum": 1, "maximum": max, "description": "时长，秒"] }
    /// Model-visible tools for「对助教说」/ chooseTool. Stop / withdraw / query / publish stay on in-progress cards (and jev), not in this list.
    static let voice: [AssistantTool] = [
        .init(name: "publish_notice", title: "发布聊天室公告", properties: ["content": string("公告正文")]),
        .init(name: "find_materials", title: "按名称查询可发送课件", properties: ["query": string("文件名称或关键词")]),
        .init(name: "send_material", title: "发送已找到的课件", properties: ["material_id": string("查询得到的文件ID，不可自造路径")]),
        .init(name: "start_checkin", title: "发起签到", properties: ["duration_seconds": duration(120), "tips": string("签到提示")]),
        .init(name: "list_exercises", title: "列出本场讲师笔记练习题", properties: [:]),
        .init(name: "prepare_exercise", title: "准备答题卡草稿", properties: ["request": string("讲师想准备的题目主题、题干或要求")]),
        .init(name: "start_answer_card", title: "发送笔记中的练习题为答题卡", properties: ["exercise_id": string("笔记练习题ID"), "duration_seconds": ["type":"integer", "minimum":0, "maximum":0, "description":"固定为0，由讲师手动结束"]]),
        .init(name: "list_questionnaires", title: "查询已有问卷", properties: [:]),
        .init(name: "start_questionnaire", title: "发布已有问卷", properties: ["questionnaire_id": string("查询得到的问卷ID")]),
        .init(name: "start_timer", title: "开始倒计时", properties: ["duration_seconds": duration(7200)])
    ]
    /// Full set performTool / closeInteraction / jev / UI buttons can still resolve. Includes voice plus stop/withdraw/query/publish/moderation and other platform actions.
    static let executable: [AssistantTool] = voice + [
        .init(name: "send_chat_message", title: "发送普通聊天消息", properties: ["content": string("要发给观众的完整消息")]),
        .init(name: "reply_chat_message", title: "引用回复本场观众问题", properties: ["message_id": string("从上下文获取原消息ID"), "content": string("回答正文")]),
        .init(name: "remove_notice", title: "撤下聊天室公告", properties: [:]),
        .init(name: "stop_checkin", title: "停止当前签到", properties: [:]),
        .init(name: "get_checkin_result", title: "查询当前签到状态与人数", properties: [:]),
        .init(name: "stop_answer_card", title: "停止当前答题卡", properties: ["question_id": string("平台答题卡ID")]),
        .init(name: "get_answer_result", title: "查询答题统计", properties: ["question_id": string("平台答题卡ID")]),
        .init(name: "publish_answer_result", title: "公布答题结果", properties: ["question_id": string("平台答题卡ID")]),
        .init(name: "stop_questionnaire", title: "停止问卷", properties: ["questionnaire_id": string("问卷ID")]),
        .init(name: "start_rush_answer", title: "开始抢答", properties: ["duration_seconds": duration(600)]),
        .init(name: "stop_rush_answer", title: "结束抢答", properties: ["rush_answer_id": string("抢答ID")]),
        .init(name: "pause_timer", title: "暂停倒计时", properties: [:]),
        .init(name: "end_timer", title: "结束倒计时", properties: [:]),
        .init(name: "list_cards", title: "查询可推送卡片", properties: [:]),
        .init(name: "push_card", title: "推送卡片", properties: ["card_id": string("查询得到的卡片ID")]),
        .init(name: "withdraw_card", title: "撤下卡片", properties: ["card_id": string("卡片ID")]),
        .init(name: "list_lotteries", title: "查询抽奖活动", properties: [:]),
        .init(name: "start_lottery", title: "发起即时抽奖", properties: ["prize_name": string("讲师明确指定的奖品"), "winner_count": ["type": "integer", "minimum": 1, "maximum": 999, "description": "中奖人数"]]),
        .init(name: "end_lottery", title: "结束抽奖", properties: ["lottery_id": string("正在进行的抽奖ID")]),
        .init(name: "get_lottery_result", title: "查询中奖名单", properties: ["lottery_id": string("抽奖ID")]),
        .init(name: "list_enroll_lotteries", title: "查询报名抽奖", properties: [:]),
        .init(name: "draw_enroll_lottery", title: "对已有报名抽奖立即开奖", properties: ["lottery_id": string("报名抽奖ID")]),
        .init(name: "mute_user", title: "禁言指定观众", properties: ["user_id": string("本场观众用户ID，不是昵称")]),
        .init(name: "unmute_user", title: "解除观众禁言", properties: ["user_id": string("本场观众用户ID")]),
        .init(name: "kick_user", title: "踢出违规观众", properties: ["user_id": string("本场观众用户ID")]),
        .init(name: "restore_user", title: "解除踢出", properties: ["user_id": string("本场观众用户ID")])
    ]
    /// Alias of voice — chooseTool default / legacy callers that meant the model-visible list.
    static var all: [AssistantTool] { voice }
    static func validate(_ name: String, _ args: [String: Any]) throws -> AssistantTool {
        guard let tool = executable.first(where: { $0.name == name }), Set(args.keys) == Set(tool.required) else { throw AppError.message("缺少必要信息，请说明操作对象") }
        for (key, schema) in tool.properties {
            if schema["type"] as? String == "string" {
                guard let value = args[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 2000 else { throw AppError.message("请补充\(key)") }
            } else {
                guard let number = args[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.rounded() == number.doubleValue, number.intValue >= (schema["minimum"] as? Int ?? 1), number.intValue <= (schema["maximum"] as? Int ?? 7200) else { throw AppError.message("时长超出范围") }
            }
        }
        return tool
    }
}

extension Store {
    func runCommand(_ text: String, generation: UUID) async {
        guard canTalkToAssistant else { return }
        guard let provider = client.provider else { postError("请先配置回答模型"); return }
        var results: [[String: Any]] = []
        var called = Set<String>()
        let commandID = UUID().uuidString
        diagnostic("command.started", ["command_id": commandID, "voice_request_id": voiceRequestID.uuidString, "instruction": text, "model": provider.model])
        do {
            for step in 0..<6 {
                let context: [String: Any] = ["instruction": text, "previous": commandHistory.suffix(6).map { $0 }, "results": results, "active_interactions": pinnedInteractions.map { ["kind": $0.kind.rawValue, "id": $0.platformID, "content": $0.content] }, "pending": messages.filter { $0.kind == .question }.map { ["id": $0.sourceMessages.first?.id ?? $0.id.uuidString, "question": $0.question] }, "viewers": (currentCourse?.events ?? []).suffix(50).map { ["id": $0.userID, "name": $0.name] }]
                let started = Date()
                let choice: [String: Any]
                if let commandDecisionOverride { choice = try await commandDecisionOverride(context) }
                else { choice = try await ProviderAPI.chooseTool(provider, key: client.providerKey, input: context) }
                guard generation == epoch else { return }
                diagnostic("command.decision", ["command_id": commandID, "step": step, "duration_ms": Int(Date().timeIntervalSince(started) * 1000), "tool": choice["name"] ?? "", "arguments": choice["arguments"] ?? [:], "reply": choice["message"] ?? ""])
                guard let name = choice["name"] as? String, let arguments = choice["arguments"] as? [String:Any] else {
                    let clarification = choice["message"] as? String ?? "请补充操作对象"
                    commandHistory.append(["instruction": text, "response": clarification])
                    if results.isEmpty || results.allSatisfy({ result in let name = result["name"] as? String ?? ""; return name.hasPrefix("get_") || name.hasPrefix("list_") || name == "find_materials" }) { flow(clarification) }
                    return
                }
                let signature = name + String(data: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), encoding: .utf8)!
                guard called.insert(signature).inserted else { return }
                let result = try await performTool(name, arguments: arguments, generation: generation, instructorRequest: text)
                diagnostic("command.tool_result", ["command_id": commandID, "step": step, "tool": name, "result": result])
                results.append(["name": name, "result": result])
                commandHistory.append(["instruction": text, "tool": name, "result": result])
                if commandHistory.count > 12 { commandHistory.removeFirst(commandHistory.count - 12) }
                if ["prepare_exercise", "start_answer_card", "start_checkin", "publish_notice"].contains(name) { return }
            }
        } catch { guard generation == epoch else { return }; diagnostic("command.failed", ["command_id": commandID, "message": error.localizedDescription], error: true); postError(error.localizedDescription) }
    }
    func performTool(_ name: String, arguments a: [String: Any], generation: UUID, origin: ClassroomMessage? = nil, instructorRequest: String? = nil) async throws -> Any {
        let tool = try AssistantTool.validate(name, a)
        let targetCourseID = currentCourseID
        diagnostic("tool.started", ["name": name])
        guard epoch == generation else { throw AppError.message("本场已结束") }
        if ["stop_answer_card", "stop_checkin", "remove_notice"].contains(name), let courseID = targetCourseID,
           let item = pinnedInteractions.first(where: { name == "stop_answer_card" ? $0.kind == .answer && $0.platformID == (a["question_id"] as? String) : name == "stop_checkin" ? $0.kind == .checkin : $0.kind == .notice }) {
            await closeInteraction(item.id, courseID: courseID)
            guard let completed = interactionRecord(item.id, courseID: courseID), completed.ended != nil else { throw AppError.message(interactionRecord(item.id, courseID: courseID)?.error ?? "操作未完成，请重试") }
            return ["ended":true]
        }
        let readOnly = name.hasPrefix("list_") || name.hasPrefix("get_") || name == "find_materials"
        if !readOnly { flow("正在\(tool.title)…") }
        let value: Any
        func str(_ key: String) -> String { a[key] as? String ?? "" }
        let duration = a["duration_seconds"] as? Int ?? 60
        if let toolOverride { value = try await toolOverride(name, a) }
        else if name == "find_materials" {
            return materials.filter { $0.name.localizedCaseInsensitiveContains(str("query")) && $0.file != nil }.map { ["id": $0.id.uuidString, "name": $0.name] }
        } else if name == "list_exercises" {
            return (currentCourse?.exercises ?? []).map { ["id": $0.id.uuidString, "question": $0.question, "sent": $0.sentAt != nil] as [String:Any] }
        } else {
            guard demo || connected else { throw AppError.message("请先连接直播间") }
            switch name {
            case "prepare_exercise":
                value = try await prepareVoiceExercise(instructorRequest ?? str("request"), generation: generation)
            case "send_chat_message": if !demo { try await reply(str("content"), to: nil) }; value = ["sent": true]
            case "reply_chat_message":
                guard let message = currentCourse?.events?.first(where: { $0.id == str("message_id") }) else { throw AppError.message("未找到原问题") }
                if !demo { try await reply(str("content"), to: message) }
                if let pending = messages.first(where: { $0.sourceMessages.contains(where: { $0.id == message.id }) }) { var m = pending; m.draft = str("content"); completeMessage(m, auto: false); return ["sent": true] }
                recordAnswer(question: message.text, answer: str("content"), actor: "主讲", messages: [message]); value = ["sent": true]
            case "send_material":
                guard let file = materials.first(where: { $0.id.uuidString == str("material_id") })?.file else { throw AppError.message("未找到课件，请先添加文件") }
                if !demo { try await gateway.sendFile(file, userID: saved.preferences.userID) }; value = ["file": file.lastPathComponent]
            case "mute_user", "unmute_user", "kick_user", "restore_user":
                guard currentCourse?.events?.contains(where: { $0.userID == str("user_id") }) == true || origin?.userID == str("user_id") else { throw AppError.message("未找到本场观众") }
                if name == "mute_user" || name == "unmute_user" { value = demo ? "预览完成" : try await gateway.api("/live/v3/channel/chat/banned-user", params: ["userIds": str("user_id"), "toBanned": name == "mute_user" ? "Y" : "N"]) }
                else { value = demo ? "预览完成" : try await gateway.kick(str("user_id"), restore: name == "restore_user") }
            case "start_answer_card":
                guard let id = UUID(uuidString: str("exercise_id")) else { throw AppError.message("题目无效") }
                value = try await publishExercise(id, duration: duration, generation: generation)
            default:
                if demo { value = ["preview": true] }
                else { value = try await platformTool(name, a, duration: duration, generation: generation) }
            }
        }
        if generation == epoch, let courseID = targetCourseID {
            if name == "publish_notice" { addInteraction(LiveInteraction(kind: .notice, platformID: UUID().uuidString, content: str("content")), courseID: courseID) }
            if name == "start_checkin" {
                let status = value as? [String:Any] ?? [:]
                var item = LiveInteraction(kind: .checkin, platformID: status["checkInId"] as? String ?? "", content: str("tips"))
                item.deadline = Date().addingTimeInterval(TimeInterval(duration))
                addInteraction(item, courseID: courseID)
            }
            // 问卷 / 抢答 / 倒计时 get an in-progress card too (push cards and lotteries stay one-off messages).
            if name == "start_questionnaire" {
                let detail = value as? [String:Any]
                let title = (detail?["title"] as? String) ?? (detail?["name"] as? String) ?? ""
                addInteraction(LiveInteraction(kind: .questionnaire, platformID: str("questionnaire_id"), content: title), courseID: courseID)
            }
            if name == "start_rush_answer" {
                let status = value as? [String:Any] ?? [:]
                let pid = (status["rushAnswerId"] as? String) ?? (status["id"] as? String) ?? (status["rushAnswerId"] as? NSNumber)?.stringValue ?? UUID().uuidString
                var item = LiveInteraction(kind: .rush, platformID: pid, content: "")
                item.deadline = Date().addingTimeInterval(TimeInterval(duration))
                addInteraction(item, courseID: courseID)
            }
            if name == "start_timer" {
                var item = LiveInteraction(kind: .timer, platformID: UUID().uuidString, content: "")
                item.deadline = Date().addingTimeInterval(TimeInterval(duration))
                addInteraction(item, courseID: courseID)
            }
            if ["stop_questionnaire", "stop_rush_answer", "end_timer"].contains(name), let ci = saved.courses.firstIndex(where: { $0.id == courseID }) {
                let kind: LiveInteraction.Kind = name == "stop_questionnaire" ? .questionnaire : name == "stop_rush_answer" ? .rush : .timer
                let target = name == "stop_questionnaire" ? str("questionnaire_id") : name == "stop_rush_answer" ? str("rush_answer_id") : nil
                for i in (saved.courses[ci].interactions ?? []).indices {
                    let x = saved.courses[ci].interactions![i]
                    guard x.kind == kind, x.ended == nil, target == nil || x.platformID == target! else { continue }
                    saved.courses[ci].interactions![i].ended = Date(); saved.courses[ci].interactions![i].finalized = true
                }
                persist()
            }
            if name == "pause_timer", let ci = saved.courses.firstIndex(where: { $0.id == courseID }) {
                for i in (saved.courses[ci].interactions ?? []).indices where saved.courses[ci].interactions![i].kind == .timer && saved.courses[ci].interactions![i].ended == nil {
                    saved.courses[ci].interactions![i].timerPaused = true
                }
                persist()
            }
            if name == "publish_answer_result", let ci = saved.courses.firstIndex(where: { $0.id == courseID }) {
                let qid = str("question_id")
                for i in (saved.courses[ci].interactions ?? []).indices {
                    var x = saved.courses[ci].interactions![i]
                    guard x.kind == .answer, x.platformID == qid else { continue }
                    x.resultPublished = true; x.finalized = true; x.error = nil
                    saved.courses[ci].interactions![i] = x
                }
                persist()
            }
            if name == "start_answer_card", let id = UUID(uuidString: str("exercise_id")), let exercise = currentCourse?.exercises?.first(where: { $0.id == id }), let platformID = (value as? [String:Any])?["question_id"] as? String {
                addInteraction(LiveInteraction(kind: .answer, platformID: platformID, content: exercise.question, exerciseID: id), courseID: courseID)
            }
        }
        if !readOnly {
            let target = origin ?? currentCourse?.events?.last(where: { $0.userID == str("user_id") })
            let details = target.map { $0.name + "：" + $0.text } ?? str("content")
            let completedTitle: String
            if let target, ["mute_user", "unmute_user", "kick_user", "restore_user"].contains(name) {
                let action = ["mute_user":"已禁言", "unmute_user":"已解除禁言", "kick_user":"已踢出", "restore_user":"已解除踢出"][name]!
                completedTitle = action + "「" + target.name + "」"
            } else { completedTitle = name == "prepare_exercise" ? "题目已准备好，确认后可发送" : "已" + tool.title }
            let users = str("user_id").isEmpty ? [] : [str("user_id")]
            complete(OperationRecord(question: details.isEmpty ? tool.title : details, people: origin.map { [$0.name] } ?? [], answer: completedTitle, actor: origin == nil ? "主讲指令" : "助教", kind: users.isEmpty ? "action" : "moderation", sourceMessageIDs: origin.map { [$0.id] } ?? [], sourceUserIDs: users), courseID: targetCourseID)
            if generation == epoch { flow(completedTitle) }
        } else if generation == epoch { flow("已查询：\(tool.title)", detail: String(describing: value).prefix(500).description) }
        diagnostic("tool.completed", ["name": name])
        return value
    }
    func platformTool(_ name: String, _ a: [String: Any], duration: Int, generation: UUID) async throws -> Any {
        func str(_ k: String) -> String { a[k] as? String ?? "" }
        func check() throws { if generation != epoch || !connected { throw AppError.message("场次已结束或连接已断开") } }
        switch name {
        case "publish_notice": return try await interactions.call("Notice", "publishNotice", [str("content")])
        case "remove_notice": return try await interactions.call("Notice", "unpublishNotice")
        case "start_checkin":
            let status = try await interactions.call("CheckIn", "getCheckInStatus") as? [String:Any]
            guard status?["isCheckingIn"] as? Bool != true else { throw AppError.message("签到正在进行") }; try check()
            _ = try await interactions.call("CheckIn", "start", [["duration": duration, "tips": str("tips")]])
            // Start succeeded; a subsequent status-read failure must not lose the live card.
            return (try? await interactions.call("CheckIn", "getCheckInStatus")) ?? [:]
        case "stop_checkin": return try await interactions.call("CheckIn", "stop")
        case "get_checkin_result":
            var status = try await interactions.call("CheckIn", "getCheckInStatus") as? [String:Any] ?? [:]
            guard let ongoing = status["isCheckingIn"] as? Bool else { throw AppError.message("未取得签到状态") }
            guard ongoing else { return status }
            let count = try await interactions.call("CheckIn", "getCheckInNum")
            let after = try await interactions.call("CheckIn", "getCheckInStatus") as? [String:Any] ?? [:]
            guard after["isCheckingIn"] as? Bool == true, let id = status["checkInId"] as? String,
                  after["checkInId"] as? String == id else { throw AppError.message("签到状态已变化，请重试") }
            guard let number = Self.interactionNumber(count), number >= 0 else { throw AppError.message("签到人数尚未就绪") }
            status["count"] = number
            return status
        case "stop_answer_card": return try await interactions.call("AnswerCard", "stop", [str("question_id")])
        case "get_answer_result":
            let status = try await interactionCall("AnswerCard", "getOngoingStatus") as? [String:Any] ?? [:]
            guard status["isOngoing"] is Bool else { throw AppError.message("未取得答题状态") }
            let result = try await answerSnapshot(str("question_id"), status: status)
            return ["total":result.count, "correctCount":result.correct.map { $0 as Any } ?? NSNull(), "options":result.options.map { ["count":$0] }] as [String:Any]
        case "publish_answer_result":
            guard let e = currentCourse?.exercises?.first(where: { $0.platformID == str("question_id") }) else { throw AppError.message("未找到本场题目") }
            let status = try await interactionCall("AnswerCard", "getOngoingStatus") as? [String:Any] ?? [:]
            guard status["isOngoing"] is Bool else { throw AppError.message("未取得答题状态") }
            let result = try await answerSnapshot(str("question_id"), status: status); try check()
            let stats: [String:Any] = ["total":result.count, "options":result.options.map { ["count":$0] }]
            return try await interactions.call("AnswerCard", "sendResult", [["question": exercisePayload(e), "statistics": stats]])
        case "list_questionnaires": return try await interactions.call("Questionnaire", "getQuestionnaireList")
        case "start_questionnaire":
            let detail = try await interactions.call("Questionnaire", "getQuestionnaireDetail", [str("questionnaire_id")]); try check()
            return try await interactions.call("Questionnaire", "start", [detail, []])
        case "stop_questionnaire": return try await interactions.call("Questionnaire", "stop", [str("questionnaire_id")])
        case "start_rush_answer": return try await interactions.call("RushAnswer", "start", [duration])
        case "stop_rush_answer": return try await interactions.call("RushAnswer", "stop", [str("rush_answer_id")])
        case "start_timer": return try await interactions.call("Timer", "start", [["time": duration, "enableTimeOut": false]])
        case "pause_timer": return try await interactions.call("Timer", "stop")
        case "end_timer": return try await interactions.call("Timer", "end")
        case "list_cards": return try await interactions.call("PushCard", "getList")
        case "push_card": return try await interactions.call("PushCard", "pushCard", [str("card_id")])
        case "withdraw_card": return try await interactions.call("PushCard", "stopCard", [str("card_id")])
        case "list_lotteries": return try await interactions.call("LotteryNew", "searchLotteryCardList", [1])
        case "start_lottery":
            let state = try await interactions.call("LotteryNew", "getLotteryStatus") as? [String:Any] ?? [:]
            guard state["lotteryStatus"] as? Bool != true else { throw AppError.message("抽奖正在进行") }
            try check()
            let params: [String:Any] = ["channelId": gateway.targetChannel, "prizeName": str("prize_name"), "amount": a["winner_count"] ?? 1, "lotteryRange": "all", "lotteryMode": "immediate", "presetList": [], "ignoreOnline": false, "hasCollect": "N", "receiveInfo": []]
            return try await interactions.call("LotteryNew", "lotteryStart", [params])
        case "end_lottery": return try await interactions.call("LotteryNew", "lotteryEnd", [str("lottery_id")])
        case "get_lottery_result": return try await interactions.call("LotteryNew", "getWinnersList", [1, str("lottery_id")])
        case "list_enroll_lotteries": return try await interactions.call("EnrollLottery", "getLotteryList", [["pageNumberNumber": 1, "type": ""]])
        case "draw_enroll_lottery": return try await interactions.call("EnrollLottery", "startLottery", [["lotteryId": str("lottery_id")]])
        default: throw AppError.message("不支持这项操作")
        }
    }
    func exercisePayload(_ e: Exercise) -> [String:Any] {
        ["questionId": e.platformID ?? "", "name": e.question, "type": e.correctIndices.count > 1 ? "C" : "R", "isQuickQuestion": false, "answer": e.correctIndices.sorted().map { String(UnicodeScalar(65 + $0)!) }.joined(separator: ","), "options": e.options]
    }
    func publishExercise(_ id: UUID, duration: Int, generation: UUID) async throws -> Any {
        guard let ci = courseIndex, let qi = saved.courses[ci].exercises?.firstIndex(where: { $0.id == id }), var exercise = saved.courses[ci].exercises?[qi], exercise.isValid(), !sendingExercises.contains(id), !savingQuestions.contains(id), exercise.sentAt == nil else { throw AppError.message("题目不存在、正在发送或已发送") }
        if let asset=saved.rooms.first(where:{$0.channel == saved.courses[ci].channel})?.materials.first(where:{$0.id == id}), ["creating","uncertain","needs_update"].contains(asset.questionSaveState ?? "") {
            throw AppError.message("请先核对题目保存状态，再发送答题卡")
        }
        sendingExercises.insert(id); defer { sendingExercises.remove(id) }
        let courseID = saved.courses[ci].id
        let platformID: String
        if demo { platformID = "preview-" + id.uuidString }
        else {
            let status = try await interactionCall("AnswerCard", "getOngoingStatus") as? [String:Any]
            guard let ongoing=status?["isOngoing"] as? Bool else { throw AppError.message("未确认当前答题状态，请重试") }
            let currentID = CourseData.string((status?["question"] as? [String:Any])?["questionId"])
            if ongoing {
                guard let known = exercise.platformID, !known.isEmpty, currentID == known else { throw AppError.message("已有答题正在进行，请先结束当前答题") }
                platformID = known
            } else {
                exercise = try await ensureExerciseInQuestionBank(exercise, courseID: courseID)
                guard generation == epoch, currentCourseID == courseID else { throw AppError.message("场次已结束") }
                let expected = exercise.platformID!
                do {
                    let value = try await interactionCall("AnswerCard", "start", [["question": exercisePayload(exercise), "setting": ["duration": 0, "defaultLimitTimeAnswer": false]]])
                    guard CourseData.string(value) == expected else { throw AppError.message("发送结果待确认") }
                } catch {
                    // A timeout may occur after the platform accepted the question. Reconcile before retrying.
                    let after = try? await interactionCall("AnswerCard", "getOngoingStatus") as? [String:Any]
                    guard after?["isOngoing"] as? Bool == true,
                          CourseData.string((after?["question"] as? [String:Any])?["questionId"]) == expected else { throw error }
                }
                platformID = expected
            }
        }
        guard let i = saved.courses.firstIndex(where: { $0.id == courseID }), let j = saved.courses[i].exercises?.firstIndex(where: { $0.id == id }) else { throw AppError.message("课程记录已移除") }
        saved.courses[i].exercises?[j].platformID = platformID; saved.courses[i].exercises?[j].sentAt = Date()
        classroomReminders.removeAll { $0.courseID == courseID && $0.destination == .exercise(id) }
        if let ri=saved.rooms.firstIndex(where:{$0.channel == saved.courses[i].channel}), let ai=saved.rooms[ri].materials.firstIndex(where:{$0.id == id}) {
            saved.rooms[ri].materials[ai].exercise?.platformID=platformID; saved.rooms[ri].materials[ai].exercise?.sentAt=saved.courses[i].exercises?[j].sentAt
        }
        persist()
        return ["question_id": platformID]
    }
    func sendExercise(_ exercise: Exercise) {
        guard exerciseSendTasks[exercise.id] == nil, !sendingExercises.contains(exercise.id) else { return }
        exerciseSendErrors[exercise.id] = nil
        let generation = epoch
        exerciseSendTasks[exercise.id] = Task {
            defer { exerciseSendTasks[exercise.id] = nil }
            do { _ = try await performTool("start_answer_card", arguments: ["exercise_id": exercise.id.uuidString, "duration_seconds": 0], generation: generation) }
            catch { exerciseSendErrors[exercise.id] = error.localizedDescription; postError(error.localizedDescription) }
        }
    }
    func ensureExerciseInQuestionBank(_ original: Exercise, courseID: UUID) async throws -> Exercise {
        if let id = original.platformID, !id.isEmpty { return original }
        guard let course = saved.courses.first(where: { $0.id == courseID }) else { throw AppError.message("课程不存在") }
        let credentials = (saved.preferences.appID, polyvSecret)
        let result = try await questionBankRequest("/live/v3/channel/interact/question/list-question", method: "GET", channel: course.channel, params: [:], credentials: credentials)
        guard let rows = (result as? [String:Any])?["list"] as? [[String:Any]] else { throw AppError.message("未能核对频道题库，请重试") }
        let answer = original.correctIndices.sorted().map { String(UnicodeScalar(65 + $0)!) }.joined(separator: ",")
        let match = rows.first { row in
            let options = row["options"] as? [String] ?? (1...15).compactMap { CourseData.string(row["option\($0)"]) }
            return row["name"] as? String == original.question && options == original.options && (row["answer"] as? String ?? "").uppercased().filter { $0.isLetter }.sorted() == answer.filter { $0.isLetter }.sorted()
        }
        var exercise = original
        if let id = CourseData.string(match?["questionId"]), !id.isEmpty { exercise.platformID = id }
        else {
            guard original.platformSavePending != true else { throw AppError.message("题目保存结果待确认，请稍后重试") }
            exercise.platformSavePending = true
            try updateCourseData(courseID) { c in if let i = c.exercises?.firstIndex(where: { $0.id == exercise.id }) { c.exercises?[i] = exercise } }
            var params = ["type": original.correctIndices.count > 1 ? "C" : "R", "answer": answer, "name": original.question, "itemType": "0"]
            for (i, option) in original.options.enumerated() { params["option\(i + 1)"] = option }
            let value: Any
            do {
                value = try await questionBankRequest("/live/v3/channel/interact/question/add-edit-question", method: "POST", channel: course.channel, params: params, credentials: credentials)
            } catch let rejection as QuestionBankRejected {
                exercise.platformSavePending = false
                try updateCourseData(courseID) { c in if let i = c.exercises?.firstIndex(where: { $0.id == exercise.id }) { c.exercises?[i] = exercise } }
                throw rejection
            }
            guard let id = CourseData.string(value), !id.isEmpty else { throw AppError.message("题目保存结果待确认，请稍后重试") }
            exercise.platformID = id
        }
        exercise.platformSavePending = false
        try updateCourseData(courseID) { c in if let i = c.exercises?.firstIndex(where: { $0.id == exercise.id }) { c.exercises?[i] = exercise } }
        return exercise
    }
}
