import Foundation
import AppKit
import PDFKit
import UniformTypeIdentifiers
import AssistantCore

extension Store {
    func normalizedClassroomChannel(_ raw: String) -> String? {
        let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 20, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let normalized=String(text.drop(while:{$0 == "0"}))
        return normalized.isEmpty ? nil : normalized
    }
    func createClassroom(_ raw: String, name: String) async throws -> String {
        guard let channel=normalizedClassroomChannel(raw) else { throw AppError.message("请输入有效频道号") }
        try await validateChannelOwnership(channel)
        try commitRoom(channel) { room,state in
            let title=name.trimmingCharacters(in:.whitespacesAndNewlines)
            if !title.isEmpty { room.name=String(title.prefix(80)) }
            if (room.preparations ?? []).isEmpty, !state.courses.contains(where: { $0.channel == channel }) {
                room.preparations = [LessonPreparation(title: "新建课程")]
            }
        }
        return channel
    }
    func classroomTitle(_ channel: String) -> String { room(channel).name ?? "教室 \(channel)" }
    func preparations(_ channel: String) -> [LessonPreparation] { room(channel).preparations ?? [] }
    func classroomLessons(_ channel: String) -> [ClassroomLesson] {
        let courses=roomCourses(channel), ids=Set(courses.map(\.id))
        let sessions=courses.map { ClassroomLesson(id:$0.id,title:$0.title,date:$0.started,status:$0.id == currentCourseID ? LessonAssetStage.classroom.statusTitle : LessonAssetStage.review.statusTitle) }
        let drafts=preparations(channel).filter { !ids.contains($0.usedByCourseID ?? $0.id) }.map { ClassroomLesson(id:$0.usedByCourseID ?? $0.id,title:$0.title,date:$0.createdAt,status:$0.usedByCourseID != nil ? LessonAssetStage.review.statusTitle : LessonAssetStage.preparation.statusTitle) }
        return (sessions + drafts).sorted { $0.date > $1.date }
    }
    func lessonConversation(_ channel: String, lessonID: UUID?) -> RoomConversation {
        var value=room(channel)
        value.messages=value.messages.filter { $0.lessonID == lessonID }
        value.materials=value.materials.filter { $0.lessonID == lessonID }
        return value
    }
    func createPreparation(channel: String, title: String) throws -> UUID {
        let title=title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 120 else { throw AppError.message("请输入课程名称（最多120字）") }
        let value=LessonPreparation(title:title)
        try commitRoom(channel) { room,_ in
            if room.preparations == nil { room.preparations=[] }; room.preparations?.append(value)
        }
        return value.id
    }
    func savePreparation(_ value: LessonPreparation, channel: String, confirm: Bool) throws {
        guard !value.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, value.title.count <= 120,
              value.audience.count <= 2000, value.goals.count <= 5000, value.notes.count <= 60000 else { throw AppError.message("请检查课程名称和内容长度") }
        try commitRoom(channel) { room,_ in
            guard let index=room.preparations?.firstIndex(where:{$0.id == value.id}), room.preparations?[index].usedByCourseID == nil else { throw AppError.message("这份备课已用于上课，请复制后修改") }
            guard room.preparations?[index].updatedAt == value.updatedAt else { throw AppError.message("备课已更新，请重新打开后编辑") }
            var updated=value; updated.updatedAt=Date(); updated.confirmedAt=confirm ? Date() : nil
            updated.usedByCourseID=nil
            room.preparations?[index]=updated
        }
        if confirm { schedulePreparationQuestions(value.id,channel:channel) }
    }
    func copyPreparation(_ value: LessonPreparation, channel: String) throws -> UUID {
        var copy=value; copy.id=UUID(); copy.contextDocumentID=UUID(); copy.title=String((value.title + " · 副本").prefix(120)); copy.createdAt=Date(); copy.updatedAt=Date()
        copy.usedByCourseID=nil; copy.confirmedAt=nil; copy.knowledgeDocumentID=nil; copy.exercises=nil; copy.exerciseSources=nil
        copy.documents=[]
        try commitRoom(channel) { room,_ in
            if room.preparations == nil { room.preparations=[] }; room.preparations?.append(copy)
        }
        return copy.id
    }
    func preparationForLesson(_ id: UUID, channel: String) -> LessonPreparation? {
        roomCourses(channel).first { $0.id == id }?.preparation ?? preparations(channel).first { $0.id == id || $0.usedByCourseID == id }
    }
    /// Automatic session discovery waits for platform identity; explicit course launch can bind locally.
    func bindPreparationToCurrentCourse(requirePlatformSession: Bool = true) {
        guard let index=courseIndex, !requirePlatformSession || saved.courses[index].platformSessionID != nil,
              let candidate=saved.courses[index].candidatePreparationID else { return }
        let course=saved.courses[index]
        guard course.preparation == nil else { saved.courses[index].candidatePreparationID=nil; return }
        guard let chosen=preparations(course.channel).first(where:{$0.id == candidate}), chosen.usedByCourseID == nil,
              course.candidatePreparationUpdatedAt == nil || chosen.updatedAt == course.candidatePreparationUpdatedAt else {
            saved.courses[index].candidatePreparationID=nil
            saved.courses[index].candidatePreparationUpdatedAt=nil
            roomErrors[course.channel]="所选备课已变化，本场未关联备课"
            persist(); return
        }
        do {
            try commitRoom(course.channel) { room,state in
                guard let pi=room.preparations?.firstIndex(where:{$0.id == candidate}),
                      var snapshot=room.preparations?[pi], snapshot.usedByCourseID == nil,
                      let ci=state.courses.firstIndex(where:{$0.id == course.id}) else { throw AppError.message("所选备课已变化，本场未关联备课") }
                snapshot.confirmedAt = snapshot.confirmedAt ?? Date()
                snapshot.usedByCourseID=course.id
                let assets=(room.materials).filter { $0.lessonID == candidate && ($0.stage ?? .preparation) == .preparation }
                snapshot.exercises=assets.compactMap(\.exercise)
                var sourceIDs=Set<String>(); snapshot.exerciseSources=assets.filter { $0.exercise != nil }.flatMap(\.sources).filter { sourceIDs.insert($0.id).inserted }
                var existingQuestions=state.courses[ci].exercises ?? []
                let existingIDs=Set(existingQuestions.map(\.id))
                existingQuestions += (snapshot.exercises ?? []).filter { !existingIDs.contains($0.id) }
                state.courses[ci].exercises=existingQuestions
                var docs=snapshot.documents + assets.filter { $0.exercise == nil }.map { preparationAssetDocument($0) }
                docs += state.libraries.filter { snapshot.libraryIDs.contains($0.id) }.flatMap(\.documents)
                var seen=Set<UUID>(); snapshot.documents=docs.filter { seen.insert($0.id).inserted }
                state.courses[ci].preparation=snapshot
                state.courses[ci].candidatePreparationID=nil
                state.courses[ci].candidatePreparationUpdatedAt=nil
                state.courses[ci].title=snapshot.title
                room.preparations?[pi].confirmedAt=snapshot.confirmedAt
                room.preparations?[pi].usedByCourseID=course.id
                if candidate != course.id {
                    for index in room.messages.indices where room.messages[index].lessonID == candidate { room.messages[index].lessonID=course.id }
                    for index in room.materials.indices where room.materials[index].lessonID == candidate { room.materials[index].lessonID=course.id }
                }
            }
        } catch { roomErrors[course.channel]=error.localizedDescription }
    }
    func usePreparationToStart(_ id: UUID, channel: String) {
        guard preparations(channel).contains(where:{$0.id == id && $0.ready}) else { roomErrors[channel]="请先确认备课"; return }
        self.channel=channel; selectedPreparationID=id; showStart?()
    }
    func preparationKnowledgeText(_ plan: LessonPreparation, channel: String) -> String {
        let assets=room(channel).materials.filter { $0.lessonID == (plan.usedByCourseID ?? plan.id) && ($0.stage ?? .preparation) == .preparation }
        return plan.text + "\n\n" + (plan.documents + assets.filter { $0.exercise == nil }.map { preparationAssetDocument($0) }).map { "## " + $0.name + "\n" + $0.text }.joined(separator:"\n\n")
    }
    func preparationIsSaved(_ id: UUID, channel: String) -> Bool {
        guard let plan=preparations(channel).first(where:{$0.id == id}), let documentID=plan.knowledgeDocumentID else { return false }
        let text=preparationKnowledgeText(plan,channel:channel)
        return saved.libraries.contains { $0.documents.contains { $0.id == documentID && $0.text == text } }
    }
    func savePreparationToKnowledge(_ id: UUID, channel: String, libraryID: UUID?) {
        do {
            try commitRoom(channel) { room,state in
                guard let pi=room.preparations?.firstIndex(where:{$0.id == id}), let plan=room.preparations?[pi], plan.confirmedAt != nil else { throw AppError.message("请先确认备课") }
                let text=preparationKnowledgeText(plan,channel:channel)
                if let documentID=plan.knowledgeDocumentID, state.libraries.contains(where:{$0.documents.contains(where:{$0.id == documentID && $0.text == text})}) { return }
                let target: UUID
                if let libraryID { target=libraryID }
                else { let library=KnowledgeBase(name:classroomTitle(channel)); target=library.id; state.libraries.append(library) }
                guard let li=state.libraries.firstIndex(where:{$0.id == target}) else { throw AppError.message("知识库不存在") }
                let doc=Document(name:plan.title + " · 备课",text:text,sourceKind:"已确认备课",recordedAt:plan.confirmedAt)
                state.libraries[li].documents.append(doc); room.preparations?[pi].knowledgeDocumentID=doc.id
                if !room.libraryIDs.contains(target) { room.libraryIDs.append(target) }
            }
            roomErrors[channel]=nil
        } catch { roomErrors[channel]=error.localizedDescription }
    }
    func importPreparationDocuments() throws -> [Document] {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.plainText,.pdf,.rtf,UTType(filenameExtension:"md") ?? .text]; panel.allowsMultipleSelection=true; panel.placeOnAssistantScreen()
        guard panel.runModal() == .OK else { return [] }
        return try panel.urls.map { try preparationDocument(at:$0) }
    }
    func preparationDocument(at url: URL) throws -> Document {
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0) <= 20_000_000 else { throw AppError.message("文件不能超过20 MB") }
        let text:String
        if url.pathExtension.lowercased() == "pdf" { text=PDFDocument(url:url)?.string ?? "" }
        else if url.pathExtension.lowercased() == "rtf" { text=try NSAttributedString(url:url,options:[:],documentAttributes:nil).string }
        else { text=try String(contentsOf:url,encoding:.utf8) }
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.count <= 100_000 else { throw AppError.message("请使用10万字以内的文字资料") }
        return Document(name:url.lastPathComponent,text:text,sourceKind:"备课资料",recordedAt:Date())
    }
}
