import XCTest
import AssistantCore
@testable import Assistant

final class LessonAssetTests: XCTestCase {
    @MainActor func testPreparationMultipleChoiceUsesValidAnswerAndCanRetryRejection() async throws {
        let (s,id) = try fixture()
        var args = arguments(); args["correct_indices"] = [0,1]
        _ = try s.createQuestionAsset(args, channel: "100", lessonID: id, stage: .preparation, sources: [source])
        let assetID = s.room("100").materials[0].id
        var attempts = 0
        s.questionBankOverride = { _, method, params in
            if method == "GET" { return ["list": []] }
            XCTAssertEqual(params["type"], "C")
            XCTAssertEqual(params["answer"], "A,B")
            attempts += 1
            if attempts == 1 { throw QuestionBankRejected(message: "请提交正确的答案值") }
            return "multi-preparation"
        }
        await s.saveQuestionToChannel(assetID, channel: "100")
        XCTAssertEqual(s.room("100").materials[0].questionSaveState, "failed")
        await s.saveQuestionToChannel(assetID, channel: "100")
        XCTAssertEqual(s.room("100").materials[0].questionSaveState, "saved")
        XCTAssertEqual(s.room("100").materials[0].exercise?.platformID, "multi-preparation")
    }
    private let source=RoomSource(id:"source-1",title:"课程讲义",text:"变量用于保存数据，函数用于封装可复用的操作。")
    @MainActor private func fixture() throws -> (Store,UUID) {
        let s=Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.capabilities.set(.courseArchive,enabled:false)
        let id=try s.createPreparation(channel:"100",title:"变量与函数")
        return (s,id)
    }
    private func arguments(_ id:String="") -> [String:Any] {
        ["asset_id":id,"question":"变量的用途是什么？","options":["保存数据","封装操作"],"correct_indices":[0],"explanation":"变量用于保存数据。","evidence":source.text,"source_ids":[source.id]]
    }
    @MainActor func testQuestionDraftDoesNotRequireVerbatimEvidence() throws {
        for stage: LessonAssetStage in [.preparation, .classroom, .review] {
            for evidence in ["变量保存数据", "", "变量：用于保存数据。"] {
                let (s, id) = try fixture()
                var args = arguments()
                args["evidence"] = evidence
                _ = try s.createQuestionAsset(args, channel: "100", lessonID: id, stage: stage, sources: [source])
                XCTAssertEqual(s.room("100").materials.first?.exercise?.evidence, evidence)
            }
        }
        let (s, id) = try fixture()
        var args = arguments()
        args.removeValue(forKey: "evidence")
        _ = try s.createQuestionAsset(args, channel: "100", lessonID: id, stage: .preparation, sources: [source])
        args["correct_indices"] = [5]
        XCTAssertThrowsError(try s.createQuestionAsset(args, channel: "100", lessonID: id, stage: .preparation, sources: [source]))
        args["correct_indices"] = [0]
        args["options"] = ["只有一项"]
        XCTAssertThrowsError(try s.createQuestionAsset(args, channel: "100", lessonID: id, stage: .preparation, sources: [source]))
    }

    @MainActor func testStructuredQuestionsBecomeSendableOnlyInBoundCourse() async throws {
        let (s,id)=try fixture()
        _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        let asset=try XCTUnwrap(s.room("100").materials.first)
        XCTAssertEqual(asset.stage,.preparation); XCTAssertNil(asset.exercise?.sentAt)
        XCTAssertNil(s.currentCourseID); XCTAssertEqual(s.preparations("100")[0].confirmedAt,nil)
        try s.savePreparation(s.preparations("100")[0],channel:"100",confirm:true)
        s.channel="100"; s.selectedPreparationID=id; s.ensureCourse(); s.adoptSession("s1",started:Date())
        let course=try XCTUnwrap(s.currentCourse), question=try XCTUnwrap(course.exercises?.first)
        XCTAssertEqual(question.id,asset.id)
        XCTAssertTrue(question.isValid())
        XCTAssertFalse(s.answerLibrary.documents.contains { $0.text.contains("参考答案") })
        XCTAssertNil(question.sentAt)
        s.demo=true
        _ = try await s.publishExercise(question.id,duration:0,generation:s.epoch)
        XCTAssertNotNil(s.currentCourse?.exercises?.first?.sentAt)
        XCTAssertNotNil(s.room("100").materials.first?.exercise?.sentAt)
    }
    @MainActor func testStageNeverChangesAfterClassAndSameSessionCanKeepChatting() async throws {
        let (s,id)=try fixture()
        var sources=[source]
        _ = try s.performRoomTool("create_material",args:["title":"备课讲义","text":"准备讲变量","kind":"资料","source_ids":[source.id]],channel:"100",sources:&sources,lessonID:id)
        XCTAssertEqual(s.room("100").materials[0].stage,.preparation)
        try s.savePreparation(s.preparations("100")[0],channel:"100",confirm:true)
        s.channel="100"; s.selectedPreparationID=id; s.ensureCourse(); s.adoptSession("s1",started:Date())
        let actual=try XCTUnwrap(s.currentCourseID)
        XCTAssertEqual(s.lessonAssetStage(channel:"100",lessonID:actual),.classroom)
        s.finishCourse()
        XCTAssertEqual(s.lessonAssetStage(channel:"100",lessonID:actual),.review)
        _ = try s.performRoomTool("create_material",args:["title":"课后讲义","text":"本节回顾变量","kind":"资料","source_ids":[source.id]],channel:"100",sources:&sources,lessonID:actual)
        XCTAssertEqual(s.room("100").materials.map(\.stage),[.preparation,.review])
        s.roomAgentOverride={ _ in ["message":"可以继续复盘本课"] }
        XCTAssertTrue(s.sendRoomMessage("继续复盘",channel:"100",lessonID:actual)); await s.roomTasks["100"]?.value
        XCTAssertEqual(s.lessonConversation("100",lessonID:actual).messages.last?.role,"assistant")
        XCTAssertFalse(s.preparations("100")[0].ready)
        let next=try s.useAssetForNextLesson(s.room("100").materials[1],channel:"100")
        XCTAssertNotEqual(next,actual); XCTAssertEqual(s.lessonConversation("100",lessonID:next).materials[0].stage,.preparation)
    }
    @MainActor func testSaveQuestionCallsCreateButNeverSendAndIsIdempotent() async throws {
        let (s,id)=try fixture()
        _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        let asset=s.room("100").materials[0]
        var paths:[String]=[]
        s.questionBankOverride={ path,method,params in
            paths.append(path)
            XCTAssertEqual(params["channelId"],"100")
            if method == "GET" { return ["list":[]] }
            XCTAssertTrue(path.hasSuffix("add-edit-question")); XCTAssertEqual(params["type"],"R"); XCTAssertEqual(params["answer"],"A")
            XCTAssertNil(params["questionId"]); return "saved-question-1"
        }
        await s.saveQuestionToChannel(asset.id,channel:"100")
        await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertEqual(paths.count,2); XCTAssertFalse(paths.contains { $0.contains("/send") || $0.contains("createTest") })
        let result=s.room("100").materials[0]
        XCTAssertEqual(result.exercise?.platformID,"saved-question-1"); XCTAssertNil(result.exercise?.sentAt)
        XCTAssertEqual(try s.file.read().rooms[0].materials[0].questionSaveState,"saved")
    }
    @MainActor func testUncertainCreateReconcilesWithoutRepeatingPost() async throws {
        let (s,id)=try fixture(); _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        let asset=s.room("100").materials[0]
        var posts=0, reconcile=false
        s.questionBankOverride={ _,method,_ in
            if method == "POST" { posts += 1; throw AppError.message("响应中断") }
            let row:[String:Any]=["questionId":"new-id","name":"变量的用途是什么？","options":["保存数据","封装操作"],"answer":"A"]
            return ["list":reconcile ? [row] : []]
        }
        await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertEqual(s.room("100").materials[0].questionSaveState,"uncertain")
        await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertEqual(posts,1)
        reconcile=true; await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertEqual(posts,1); XCTAssertEqual(s.room("100").materials[0].exercise?.platformID,"new-id")
    }
    @MainActor func testQuestionEditUpdatesExistingBankIDAndClearsConfirmation() async throws {
        let (s,id)=try fixture(); _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        let asset=s.room("100").materials[0]
        s.questionBankOverride={ _,method,_ in if method == "GET" { return ["list":[]] }; return "q1" }
        await s.saveQuestionToChannel(asset.id,channel:"100")
        var changed=arguments(asset.id.uuidString); changed["question"]="变量主要用于什么？"
        _ = try s.createQuestionAsset(changed,channel:"100",lessonID:id,stage:.preparation,sources:[source])
        XCTAssertEqual(s.room("100").materials.count,1)
        XCTAssertNil(s.preparations("100")[0].confirmedAt)
        var updated=false
        s.questionBankOverride={ _,method,params in
            if method == "GET" { return ["list":[]] }
            XCTAssertEqual(params["questionId"],"q1"); updated=true; return "q1"
        }
        await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertTrue(updated)
    }
    @MainActor func testMalformedAnswersAndQuestionKnowledgeExportAreRejected() throws {
        let (s,id)=try fixture(); var bad=arguments(); bad["correct_indices"]=[true]
        XCTAssertThrowsError(try s.createQuestionAsset(bad,channel:"100",lessonID:id,stage:.preparation,sources:[source]))
        bad=arguments(); bad["correct_indices"]=[4]
        XCTAssertThrowsError(try s.createQuestionAsset(bad,channel:"100",lessonID:id,stage:.preparation,sources:[source]))
        _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        s.saveRoomMaterial(s.room("100").materials[0].id,channel:"100",libraryID:nil)
        XCTAssertTrue(s.saved.libraries.isEmpty)
    }
}

extension LessonAssetTests {
    @MainActor func testFailedLocalCheckpointPreventsCloudQuestionCreation() async throws {
        let (s,id)=try fixture(); _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        let asset=s.room("100").materials[0]
        try FileManager.default.removeItem(at:s.file.url)
        try FileManager.default.createDirectory(at:s.file.url,withIntermediateDirectories:true)
        var posts=0
        s.questionBankOverride={ _,method,_ in
            if method == "POST" { posts += 1; return "must-not-be-created" }
            return ["list":[]]
        }
        await s.saveQuestionToChannel(asset.id,channel:"100")
        XCTAssertEqual(posts,0); XCTAssertNil(s.room("100").materials[0].exercise?.platformID)
        XCTAssertFalse(s.savingQuestions.contains(asset.id))
    }
}

extension LessonAssetTests {
    @MainActor func testRetryDoesNotDuplicateIdenticalQuestionAsset() throws {
        let (s,id)=try fixture()
        _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        _ = try s.createQuestionAsset(arguments(),channel:"100",lessonID:id,stage:.preparation,sources:[source])
        XCTAssertEqual(s.lessonConversation("100",lessonID:id).materials.count,1)
    }
}
