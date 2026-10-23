import XCTest
import AssistantCore
@testable import Assistant

final class ClassroomManagementTests: XCTestCase {
    @MainActor private func fixture() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.rooms = []; s.saved.courses = []; s.currentCourseID = nil
        s.saved.capabilities.set(.courseArchive, enabled: false)
        return s
    }
    @MainActor func testShortcutsPersistEditDeleteAndOldStateDecodes() throws {
        let s = fixture()
        var tool = PreparationShortcut(name: "三段式讲义", prompt: "结合当前课生成知识点、案例和练习。")
        try s.savePreparationShortcut(tool)
        XCTAssertEqual(try s.file.read().preparationShortcuts, [tool])
        tool.name = "分层讲义"; try s.savePreparationShortcut(tool)
        XCTAssertEqual(s.saved.preparationShortcuts.count, 1)
        XCTAssertEqual(try s.file.read().preparationShortcuts[0].name, "分层讲义")
        try s.deletePreparationShortcut(tool.id)
        XCTAssertTrue(try s.file.read().preparationShortcuts.isEmpty)
        XCTAssertTrue(try JSONDecoder().decode(SavedState.self, from: Data("{}".utf8)).preparationShortcuts.isEmpty)
    }
    @MainActor func testFailedShortcutSavePreservesMemoryAndRejectsInvalidInput() throws {
        let s = fixture(); let tool = PreparationShortcut(name: "讲义", prompt: "整理讲义")
        try s.savePreparationShortcut(tool)
        try FileManager.default.removeItem(at: s.file.url)
        try FileManager.default.createDirectory(at: s.file.url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try s.savePreparationShortcut(.init(name: "新工具", prompt: "生成大纲")))
        XCTAssertEqual(s.saved.preparationShortcuts, [tool])
        XCTAssertThrowsError(try s.savePreparationShortcut(.init(name: " ", prompt: "生成大纲")))
    }
    @MainActor func testDeleteDraftIsScopedAndRemovesChatAssets() throws {
        let s = fixture(); let id = try s.createPreparation(channel: "100", title: "第一课")
        let keep = try s.createPreparation(channel: "100", title: "第二课")
        _ = try s.createPreparation(channel: "200", title: "其他教室")
        try s.commitRoom("100") { room, _ in
            room.messages = [RoomMessage(role: "user", text: "删除我", lessonID: id), RoomMessage(role: "user", text: "保留我", lessonID: keep)]
            room.materials = [RoomMaterial(title: "讲义", text: "内容", kind: "文档", sources: [], lessonID: id)]
        }
        try s.deleteClassroomItem(channel: "100", lessonID: id)
        XCTAssertEqual(s.preparations("100").map(\.id), [keep])
        XCTAssertEqual(s.room("100").messages.map(\.text), ["保留我"])
        XCTAssertTrue(s.room("100").materials.isEmpty)
        XCTAssertEqual(s.preparations("200").count, 1)
        XCTAssertEqual(try s.file.read().rooms.first { $0.channel == "100" }?.preparations?.count, 1)
    }
    @MainActor func testDeleteWholeRoomAndBusyProtection() throws {
        let s = fixture(); let id = try s.createPreparation(channel: "100", title: "课")
        s.roomRunIDs["100"] = UUID()
        XCTAssertThrowsError(try s.deleteClassroomItem(channel: "100", lessonID: id))
        s.roomRunIDs["100"] = nil
        s.channel = "100"; s.demo = false; s.selectedPreparationID = id; s.ensureCourse(); s.adoptSession("session", started: Date())
        s.channel = "200" // Editing the next login channel must not unlock the live room.
        XCTAssertThrowsError(try s.deleteClassroomItem(channel: "100", lessonID: nil))
        s.finishCourse()
        try s.deleteClassroomItem(channel: "100", lessonID: nil)
        XCTAssertFalse(s.classroomChannels.contains("100"))
        XCTAssertTrue(s.saved.courses.isEmpty)
    }
    @MainActor func testRenameBoundCourseKeepsSnapshotAndDeleteDoesNotResurrectPreparation() throws {
        let s = fixture(); let id = try s.createPreparation(channel: "100", title: "原课名")
        s.channel = "100"; s.demo = false; s.selectedPreparationID = id; s.ensureCourse(); s.adoptSession("session", started: Date())
        let course = try XCTUnwrap(s.currentCourseID); s.finishCourse()
        try s.renameClassroomItem(channel: "100", lessonID: course, title: "新课名")
        XCTAssertEqual(s.classroomLessons("100").first?.title, "新课名")
        XCTAssertEqual(s.saved.courses[0].preparation?.title, "原课名")
        try s.deleteClassroomItem(channel: "100", lessonID: course)
        XCTAssertTrue(s.classroomLessons("100").isEmpty)
        XCTAssertTrue(s.preparations("100").isEmpty)
    }
}
