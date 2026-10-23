import Foundation
import AssistantCore

struct QuestionBankRejected: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Store {
    func lessonAssetStage(channel:String,lessonID:UUID?) -> LessonAssetStage {
        if let lessonID, lessonID == currentCourseID { return .classroom }
        if roomCourses(channel).contains(where:{$0.id == lessonID}) { return .review }
        if preparations(channel).contains(where:{$0.id == lessonID && $0.usedByCourseID == nil}) { return .preparation }
        return .review
    }
    func invalidatePreparation(_ room:inout RoomConversation,lessonID:UUID?,stage:LessonAssetStage?) {
        guard stage == .preparation, let index=room.preparations?.firstIndex(where:{$0.id == lessonID && $0.usedByCourseID == nil}) else { return }
        room.preparations?[index].confirmedAt=nil; room.preparations?[index].updatedAt=Date()
    }
    func preparationAssetDocument(_ asset:RoomMaterial) -> Document {
        let sources=asset.sources.map { "\($0.title) [\($0.id)]\n\($0.text)" }.joined(separator:"\n\n")
        return Document(id:asset.id,name:asset.title,text:asset.text + "\n\n依据：\n" + sources,sourceKind:"备课生成资产",recordedAt:asset.date)
    }
    func exerciseText(_ exercise:Exercise) -> String {
        exercise.question + "\n" + exercise.options.enumerated().map { "\(String(UnicodeScalar(65+$0.offset)!)). \($0.element)" }.joined(separator:"\n")
            + "\n参考答案：" + exercise.correctIndices.map { String(UnicodeScalar(65+$0)!) }.joined(separator:"、") + "\n解析：" + exercise.explanation
    }
    func exerciseSource(_ course:CourseSession) -> String {
        course.transcript + "\n" + (course.preparation?.text ?? "") + "\n" + (course.preparation?.documents ?? []).map(\.text).joined(separator:"\n")
            + "\n" + (course.preparation?.exerciseSources ?? []).map(\.text).joined(separator:"\n")
            + "\n" + room(course.channel).materials.filter { $0.lessonID == course.id && $0.stage == .classroom && $0.exercise != nil }.flatMap(\.sources).map(\.text).joined(separator:"\n")
    }
    func createQuestionAsset(_ args:[String:Any],channel:String,lessonID:UUID?,stage:LessonAssetStage,sources:[RoomSource]) throws -> Any {
        guard let lessonID, let question=args["question"] as? String, let options=args["options"] as? [String],
              let raw=args["correct_indices"] as? [Any], let explanation=args["explanation"] as? String, explanation.count <= 2000,
              let ids=args["source_ids"] as? [String], !ids.isEmpty,
              ids.allSatisfy({ id in sources.contains { $0.id == id } }), let rawID=args["asset_id"] as? String else { throw AppError.message("题干、选项、答案或来源不完整") }
        let indices=raw.compactMap(CourseData.integer)
        guard indices.count == raw.count else { throw AppError.message("答案序号无效") }
        let used=sources.filter { ids.contains($0.id) }
        var exercise=Exercise(question:question,options:options,correctIndices:indices,explanation:explanation,evidence:args["evidence"] as? String ?? "")
        guard exercise.isValid() else { throw AppError.message("题干、选项、答案或解析格式不正确") }
        if !rawID.isEmpty {
            guard let existing=room(channel).materials.first(where:{$0.id.uuidString == rawID && $0.lessonID == lessonID && $0.exercise != nil}),
                  existing.stage == stage, !savingQuestions.contains(existing.id), !sendingExercises.contains(existing.id), existing.exercise?.sentAt == nil,
                  !(stage == .preparation && preparations(channel).contains(where:{$0.usedByCourseID == lessonID})) else { throw AppError.message("题目已用于上课或不能在当前阶段修改") }
            exercise.id=existing.id; exercise.platformID=existing.exercise?.platformID
            var material=existing; material.exercise=exercise; material.text=exerciseText(exercise); material.title=String(question.prefix(120)); material.sources=used
            material.questionSaveState=exercise.platformID == nil ? nil : "needs_update"; material.priorQuestionIDs=nil; material.updatedAt=Date()
            try commitRoom(channel) { room,state in
                let index=room.materials.firstIndex { $0.id == existing.id }!
                room.materials[index]=material; invalidatePreparation(&room,lessonID:lessonID,stage:stage)
                if stage == .classroom, let ci=state.courses.firstIndex(where:{$0.id == lessonID && $0.channel == channel}), let qi=state.courses[ci].exercises?.firstIndex(where:{$0.id == exercise.id && $0.sentAt == nil}) { state.courses[ci].exercises?[qi]=exercise }
            }
            return ["status":"question_updated","asset_id":material.id.uuidString,"stage":stage.rawValue,"sent":false]
        }
        if let existing=room(channel).materials.first(where:{ asset in
            guard asset.lessonID == lessonID, asset.stage == stage, let e=asset.exercise else { return false }
            return e.question == exercise.question && e.options == exercise.options && Set(e.correctIndices) == Set(exercise.correctIndices) && e.explanation == exercise.explanation
        }) { return ["status":"question_already_exists","asset_id":existing.id.uuidString,"stage":stage.rawValue,"sent":existing.exercise?.sentAt != nil] }
        var material=RoomMaterial(title:String(question.prefix(120)),text:exerciseText(exercise),kind:"题目",sources:used,lessonID:lessonID)
        material.id=exercise.id; material.exercise=exercise; material.stage=stage
        try commitRoom(channel) { room,state in
            room.materials.append(material); invalidatePreparation(&room,lessonID:lessonID,stage:stage)
            if stage == .classroom, let ci=state.courses.firstIndex(where:{$0.id == lessonID && $0.channel == channel}) {
                if state.courses[ci].exercises == nil { state.courses[ci].exercises=[] }; state.courses[ci].exercises?.append(exercise)
            }
        }
        return ["status":"question_draft_created","asset_id":material.id.uuidString,"stage":stage.rawValue,"sent":false]
    }
    func updateDocumentAsset(_ asset:RoomMaterial,channel:String) throws {
        guard asset.exercise == nil, !asset.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, asset.title.count <= 120,
              !asset.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, asset.text.count <= 60000 else { throw AppError.message("请检查文档名称和内容") }
        try commitRoom(channel) { room,_ in
            guard let index=room.materials.firstIndex(where:{$0.id == asset.id}),
                  !(asset.stage == .preparation && room.preparations?.contains(where:{$0.usedByCourseID == asset.lessonID}) == true) else { throw AppError.message("本场备课版本已固定，请复制为新课后修改") }
            guard room.materials[index].updatedAt == asset.updatedAt else { throw AppError.message("文档已更新，请重新打开") }
            var updated=asset; updated.updatedAt=Date(); updated.documentID=nil; updated.libraryID=nil
            room.materials[index]=updated; invalidatePreparation(&room,lessonID:asset.lessonID,stage:asset.stage)
        }
    }
    func useAssetForNextLesson(_ asset: RoomMaterial, channel: String) throws -> UUID {
        guard room(channel).materials.contains(where:{$0.id == asset.id}) else { throw AppError.message("这份课程产出已不存在") }
        let plan=LessonPreparation(title:String((asset.title + " · 下次课").prefix(120)))
        var copy=asset; copy.id=UUID(); copy.lessonID=plan.id; copy.stage = .preparation; copy.date=Date(); copy.updatedAt=nil
        copy.documentID=nil; copy.libraryID=nil; copy.questionSaveState=nil; copy.priorQuestionIDs=nil
        if var exercise=copy.exercise { exercise.id=copy.id; exercise.platformID=nil; exercise.sentAt=nil; copy.exercise=exercise }
        try commitRoom(channel) { room,_ in
            if room.preparations == nil { room.preparations=[] }; room.preparations?.append(plan); room.materials.append(copy)
        }
        return plan.id
    }
    func schedulePreparationQuestions(_ id:UUID,channel:String) {
        guard !previewMode || questionBankOverride != nil else { return }
        for asset in room(channel).materials where asset.lessonID == id && asset.stage == .preparation && asset.exercise != nil && (asset.exercise?.platformID == nil || asset.questionSaveState == "needs_update") {
            guard questionBankTasks[asset.id] == nil else { continue }
            questionBankTasks[asset.id]=Task { [weak self] in
                await self?.saveQuestionToChannel(asset.id,channel:channel)
                self?.questionBankTasks[asset.id]=nil
            }
        }
    }
    /// Save to the channel question bank only. No socket, live-session or send/start endpoint is used.
    func questionBankRequest(_ path:String,method:String,channel:String,params:[String:String],credentials:(String,String)? = nil) async throws -> Any {
        if let questionBankOverride { return try await questionBankOverride(path,method,params.merging(["channelId":channel]) { _,b in b }) }
        let appID=credentials?.0 ?? saved.preferences.appID, secret=credentials?.1 ?? polyvSecret
        guard !previewMode, !appID.isEmpty, !secret.isEmpty else { throw AppError.message("请配置保利威连接后同步题目") }
        try await StatisticsThrottle.shared.wait()
        var fields=params; fields["channelId"]=channel; fields["appId"]=appID; fields["timestamp"]=String(Int(Date().timeIntervalSince1970*1000))
        fields["sign"]=ChatGateway.signature(fields,secret:secret)
        var components=URLComponents(); components.queryItems=fields.sorted { $0.key < $1.key }.map { URLQueryItem(name:$0.key,value:$0.value) }
        let encoded=components.percentEncodedQuery?.replacingOccurrences(of:"+",with:"%2B") ?? ""
        var request=URLRequest(url:URL(string:"https://api.polyv.net" + path + (method == "GET" ? "?"+encoded : ""))!); request.httpMethod=method; request.timeoutInterval=25
        if method == "POST" { request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type"); request.httpBody=Data(encoded.utf8) }
        let session = URLSession(configuration: .ephemeral, delegate: RejectRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        return try Self.questionBankResponse(data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
    static func questionBankResponse(_ data: Data, status: Int) throws -> Any {
        guard data.count <= 10_000_000, let json = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw AppError.message("题库响应异常，请稍后核对") }
        if [200, 400].contains(status), CourseData.integer(json["code"]) == 400 {
            let raw = json["message"] as? String ?? ""
            let safe = ["请提交正确的答案值", "请提交题目的答案", "请提交题目的名称", "选择项不能少于2个", "当前状态不允许修改答题卡", "答题卡记录不存在"]
            let message = safe.contains(raw) ? raw : raw == "invalid signature." ? "题库鉴权失败，请检查保利威凭据" : "题库请求被拒绝，请检查题目或频道权限"
            throw QuestionBankRejected(message: message)
        }
        guard status == 200, CourseData.integer(json["code"]) == 200, let value = json["data"], !(value is NSNull) else { throw AppError.message("题目保存结果待确认，请稍后重试") }
        return value
    }
    func saveQuestionToChannel(_ assetID:UUID,channel:String) async {
        guard !savingQuestions.contains(assetID), !sendingExercises.contains(assetID), let original=room(channel).materials.first(where:{$0.id == assetID}), let question=original.exercise, question.platformID == nil || original.questionSaveState != "saved" else { return }
        savingQuestions.insert(assetID); defer { savingQuestions.remove(assetID) }
        let account=saved.preferences.appID, credentials=(saved.preferences.appID,polyvSecret)
        var creating=false
        do {
            let value=try await questionBankRequest("/live/v3/channel/interact/question/list-question",method:"GET",channel:channel,params:[:],credentials:credentials)
            try Task.checkCancellation()
            guard saved.preferences.appID == account else { throw CancellationError() }
            guard let data=value as? [String:Any], let rows=data["list"] as? [[String:Any]] else { throw AppError.message("未能核对频道题库") }
            let answer=question.correctIndices.sorted().map { String(UnicodeScalar(65+$0)!) }.joined(separator: ",")
            let matches=rows.filter { row in
                let options=(row["options"] as? [String]) ?? (1...15).compactMap { CourseData.string(row["option\($0)"]) }
                let actual=(row["answer"] as? String ?? "").uppercased().filter { $0.isLetter }.sorted()
                return row["name"] as? String == question.question && options == question.options && actual == answer.filter { $0.isLetter }.sorted()
            }.compactMap { CourseData.string($0["questionId"]) }
            let platformID:String
            if let known=question.platformID, matches.contains(known) {
                platformID=known
            } else if question.platformID == nil && ["creating","uncertain"].contains(original.questionSaveState ?? "") {
                let newIDs=matches.filter { !(original.priorQuestionIDs ?? []).contains($0) }
                guard newIDs.count == 1 else { throw AppError.message("保存结果仍未确认，请稍后核对；不会重复创建") }
                platformID=newIDs[0]
            } else {
                try commitRoom(channel) { room,_ in
                    guard let index=room.materials.firstIndex(where:{$0.id == assetID}) else { throw CancellationError() }
                    room.materials[index].questionSaveState="creating"; room.materials[index].priorQuestionIDs=matches
                }
                var params=["type":question.correctIndices.count > 1 ? "C" : "R","answer":answer,"name":question.question,"itemType":"0"]
                if let known=question.platformID { params["questionId"]=known }
                for (index,option) in question.options.enumerated() { params["option\(index+1)"]=option }
                creating=true
                let response=try await questionBankRequest("/live/v3/channel/interact/question/add-edit-question",method:"POST",channel:channel,params:params,credentials:credentials)
                guard let id=CourseData.string(response), !id.isEmpty else { throw AppError.message("未收到答题卡ID") }; platformID=id
            }
            try Task.checkCancellation()
            guard saved.preferences.appID == account else { throw CancellationError() }
            try commitRoom(channel) { room,state in
                guard let index=room.materials.firstIndex(where:{$0.id == assetID}), room.materials[index].exercise?.question == question.question else { throw CancellationError() }
                room.materials[index].exercise?.platformID=platformID; room.materials[index].questionSaveState="saved"
                for ci in state.courses.indices where state.courses[ci].channel == channel {
                    if let qi=state.courses[ci].exercises?.firstIndex(where:{$0.id == question.id && $0.sentAt == nil}) { state.courses[ci].exercises?[qi].platformID=platformID }
                }
            }
            roomErrors[channel]=nil
        } catch {
            if creating { try? commitRoom(channel) { room,_ in if let i=room.materials.firstIndex(where:{$0.id == assetID}) { room.materials[i].questionSaveState = error is QuestionBankRejected ? "failed" : "uncertain" } } }
            roomErrors[channel]=error is CancellationError ? "题目同步已停止" : error.localizedDescription
        }
    }
}
