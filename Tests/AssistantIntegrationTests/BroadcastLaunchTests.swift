import XCTest
import AssistantCore
@testable import Assistant

final class BroadcastLaunchTests: XCTestCase {
    @MainActor func testLibrarySelectionStartsEmptyDespitePreviousSelection() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        var state = SavedState(); let library = KnowledgeBase(name: "资料")
        state.libraries = [library]; state.selectedLibraryIDs = [library.id]
        try StateFile(url: path).write(state)
        let store = Store(preview: true, storageURL: path)
        XCTAssertTrue(store.libraryIDs.isEmpty)
        XCTAssertEqual(store.libraryLabel, "选择知识库")
        let lesson = try store.createPreparation(channel: "100", title: "课")
        store.saved.rooms[0].libraryIDs = [library.id]
        _ = try store.configureBroadcastClass(channel: "100", lessonID: lesson)
        XCTAssertTrue(store.libraryIDs.isEmpty)
        store.libraryIDs = [library.id]
        _ = try store.configureBroadcastClass(channel: "100", lessonID: lesson)
        XCTAssertEqual(store.libraryIDs, [library.id])
    }
    private let account = PolyvChannelOwnership.Account(appID: "app", userID: "owner", secret: "secret")

    @MainActor private func makeStore() -> Store {
        let store = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        store.demo = false
        store.currentCourseID = nil
        store.saved.capabilities.set(.courseArchive, enabled: false)
        return store
    }

    @MainActor func testOneClickUsesSelectedLessonAndBindsWithoutStreaming() throws {
        let store = makeStore()
        let id = try store.createPreparation(channel: "100", title: "今晚的课")
        XCTAssertTrue(try store.configureBroadcastClass(channel: "100", lessonID: id))
        XCTAssertEqual(store.channel, "100")
        XCTAssertEqual(store.selectedPreparationID, id)
        XCTAssertEqual(store.focus, "今晚的课")
        store.ensureCourse()
        XCTAssertNil(store.currentCourse?.platformSessionID)
        store.bindPreparationToCurrentCourse(requirePlatformSession: false)
        XCTAssertEqual(store.currentCourse?.preparation?.id, id)
        XCTAssertEqual(store.preparations("100").first?.usedByCourseID, store.currentCourseID)
        XCTAssertNil(store.currentCourse?.platformSessionID)
        store.connected = true
        let courseID = store.currentCourseID
        XCTAssertFalse(try store.configureBroadcastClass(channel: "100", lessonID: id))
        XCTAssertEqual(store.currentCourseID, courseID)
    }

    @MainActor func testDoesNotReplaceAnotherActiveClassOrUseMissingLesson() throws {
        let store = makeStore()
        let id = try store.createPreparation(channel: "100", title: "新课")
        store.channel = "200"
        store.connected = true
        XCTAssertThrowsError(try store.configureBroadcastClass(channel: "100", lessonID: id))
        XCTAssertEqual(store.channel, "200")
        store.connected = false
        XCTAssertThrowsError(try store.configureBroadcastClass(channel: "100", lessonID: UUID()))
        XCTAssertEqual(store.channel, "200")
    }

    private func response(_ request: URLRequest, _ payload: [String: Any]) throws -> (Data, URLResponse) {
        (try JSONSerialization.data(withJSONObject: payload), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func testClientUsesChannelAndPreservesPasswordWithoutCourseID() async throws {
        let password = "a&+=?#中文"
        let service = PolyvBroadcastLaunch { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/live/v2/channels/100/get")
            return try self.response(request, ["code": 200, "data": ["channelId": 100, "channelPasswd": password]])
        }
        let url = try await service.link(channel: "100", account: account, destination: .client)
        XCTAssertEqual(url.scheme, "polyvlive")
        let params = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(params, ["pdn": "api.polyv.net", "channelId": "100", "passwd": password])
    }

    func testWebSignsTheRequestedChannelAndAcceptsDocumentedResponseForms() async throws {
        let link = "https://live.polyv.net/web-start/?channelId=100&loginToken=test"
        for payload: Any in [link, ["token": link]] {
            let service = PolyvBroadcastLaunch { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/live/v3/channel/common/token-login-url")
                let body = String(data: request.httpBody!, encoding: .utf8)!
                var params = Dictionary(uniqueKeysWithValues: URLComponents(string: "?\(body)")!.queryItems!.map { ($0.name, $0.value!) })
                let sign = params.removeValue(forKey: "sign")
                XCTAssertEqual(params["channelId"], "100")
                XCTAssertNil(params["sessionId"])
                XCTAssertNil(params["appSecret"])
                XCTAssertEqual(sign, ChatGateway.signature(params, secret: "secret"))
                return try self.response(request, ["code": 200, "data": payload])
            }
            let url = try await service.link(channel: "100", account: account, destination: .web)
            XCTAssertEqual(url.absoluteString, link)
        }
    }

    func testRejectsUntrustedLinksAndDoesNotExposeServerMessages() async throws {
        for payload: [String: Any] in [
            ["code": 200, "data": ["token": "https://polyv.net.evil.test/?loginToken=private"]],
            ["code": 200, "data": ["token": "file:///tmp/private"]],
            ["code": 200, "data": ["token": "http://live.polyv.net/"]],
            ["code": 400, "message": "private-token"]
        ] {
            let service = PolyvBroadcastLaunch { try self.response($0, payload) }
            do {
                _ = try await service.link(channel: "100", account: account, destination: .web)
                XCTFail("Invalid result must not open")
            } catch {
                XCTAssertFalse(error.localizedDescription.contains("private"))
            }
        }
    }

    func testClientRejectsWrongChannelOrMissingPassword() async throws {
        for detail: [String: Any] in [
            ["channelId": 101, "channelPasswd": "password"],
            ["channelId": 100, "channelPasswd": ""],
            ["channelId": 100]
        ] {
            let service = PolyvBroadcastLaunch { try self.response($0, ["code": 200, "data": detail]) }
            do {
                _ = try await service.link(channel: "100", account: account, destination: .client)
                XCTFail("Invalid channel credentials must not open")
            } catch {}
        }
    }
}
