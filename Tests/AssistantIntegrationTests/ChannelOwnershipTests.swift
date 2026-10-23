import XCTest
import AssistantCore
@testable import Assistant

final class ChannelOwnershipTests: XCTestCase {
    private let account = PolyvChannelOwnership.Account(appID: "app", userID: "owner", secret: "secret")
    private func result(_ request: URLRequest, _ body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    private let owned = #"{"code":200,"status":"success","data":{"channelId":100,"userCategory":{"userId":"owner"},"authSettings":[{"channelId":100,"userId":"owner"}]}}"#
    @MainActor private func store() -> Store {
        let s = Store(preview: true, storageURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.saved.preferences.appID = account.appID; s.saved.preferences.userID = account.userID; s.polyvSecret = account.secret
        s.saved.capabilities.set(.courseArchive, enabled: false)
        return s
    }
    func testSignedRequestAndMatchingOwner() async throws {
        let client = PolyvChannelOwnership { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.host, "api.polyv.net")
            XCTAssertEqual(request.url?.path, "/live/v4/channel/basic/get")
            XCTAssertEqual(request.timeoutInterval, 15)
            var params = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            let sign = params.removeValue(forKey: "sign")
            XCTAssertEqual(params["channelId"], "100"); XCTAssertEqual(params["appId"], "app")
            XCTAssertNil(params["appSecret"])
            XCTAssertEqual(sign, ChatGateway.signature(params, secret: "secret"))
            return self.result(request, self.owned)
        }
        try await client.validate(channel: "100", account: account)
    }
    func testAuthSettingsOwnershipWorksWithoutCategory() async throws {
        let client = PolyvChannelOwnership { request in
            self.result(request, #"{"code":200,"status":"success","data":{"channelId":"100","authSettings":[{"channelId":"100","userId":"owner"}]}}"#)
        }
        try await client.validate(channel: "100", account: account)
    }
    func testForeignMissingConflictingOrMalformedOwnershipFailsClosed() async {
        let bodies = [
            owned.replacingOccurrences(of: "owner", with: "foreign"),
            #"{"code":200,"status":"success","data":{"channelId":100}}"#,
            #"{"code":200,"status":"success","data":{"channelId":100,"userCategory":{"userId":"owner"},"authSettings":[{"channelId":100,"userId":"foreign"}]}}"#,
            owned.replacingOccurrences(of: "100", with: "101"),
            owned.replacingOccurrences(of: "100", with: "true"),
            #"{"code":400,"status":"error","message":"sensitive server error"}"#,
            #"{"code":200,"status":"error","data":{"channelId":100,"userCategory":{"userId":"owner"}}}"#,
            "not json"
        ]
        for body in bodies {
            let client = PolyvChannelOwnership { self.result($0, body) }
            do { try await client.validate(channel: "100", account: account); XCTFail("Accepted invalid ownership") }
            catch { XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
        }
    }
    func testMissingCredentialsAndTransportFailures() async {
        let missing = PolyvChannelOwnership { _ in XCTFail("Missing credentials must not send request"); throw URLError(.badURL) }
        do { try await missing.validate(channel: "100", account: .init(appID: "", userID: "owner", secret: "secret")); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, "请先配置保利威接入凭据") }
        let timeout = PolyvChannelOwnership { _ in throw URLError(.timedOut) }
        do { try await timeout.validate(channel: "100", account: account); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, "频道校验失败，请稍后重试") }
        let server = PolyvChannelOwnership { self.result($0, self.owned, status: 503) }
        do { try await server.validate(channel: "100", account: account); XCTFail() } catch {}
    }
    @MainActor func testRejectedCreationDoesNotPersistRoomOrLesson() async throws {
        let s = store()
        s.channelOwnership.transport = { self.result($0, self.owned.replacingOccurrences(of: "owner", with: "foreign")) }
        do { _ = try await s.createClassroom("100", name: "test"); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, "该频道不属于当前保利威账号") }
        do { _ = try await s.createValidatedPreparation(channel: "100", title: "test"); XCTFail() } catch {}
        XCTAssertTrue(s.saved.rooms.isEmpty); XCTAssertTrue(try s.file.read().rooms.isEmpty)
    }
    @MainActor func testOwnedLessonPersistsAndCancelledRoomDoesNot() async throws {
        let s = store()
        s.channelOwnership.transport = { self.result($0, self.owned) }
        let lesson = try await s.createValidatedPreparation(channel: "100", title: "本课")
        XCTAssertEqual(try s.file.read().rooms.first?.preparations?.first?.id, lesson)
        var continuation: CheckedContinuation<Void, Never>?
        s.channelOwnership.transport = { request in
            await withCheckedContinuation { continuation = $0 }
            return self.result(request, self.owned)
        }
        let task = Task { try await s.createClassroom("100", name: "不应写入") }
        while continuation == nil { await Task.yield() }
        task.cancel(); continuation?.resume()
        do { _ = try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertNil(s.saved.rooms.first?.name)
        XCTAssertNil(try s.file.read().rooms.first?.name)
    }
    @MainActor func testAccountChangeWhileAwaitingDoesNotCreateRoom() async {
        let s = store()
        s.channelOwnership.transport = { request in
            s.saved.preferences.userID = "different"
            return self.result(request, self.owned)
        }
        do { _ = try await s.createClassroom("100", name: "test"); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, "账号已变更，请重试") }
        XCTAssertTrue(s.saved.rooms.isEmpty)
    }
    @MainActor func testFailedConnectionKeepsPreviousCourseAndPreparation() async throws {
        let s = store(); s.channel = "99"; s.ensureCourse()
        let existing = try XCTUnwrap(s.currentCourseID)
        let prep = try s.createPreparation(channel: "100", title: "test")
        var plan = try XCTUnwrap(s.preparations("100").first); try s.savePreparation(plan, channel: "100", confirm: true)
        s.channel = "100"; s.selectedPreparationID = prep
        var requests = 0
        s.channelOwnership.transport = { request in
            requests += 1
            return self.result(request, self.owned.replacingOccurrences(of: "owner", with: "foreign"))
        }
        s.connect(); let task = s.connectionTask; s.connect()
        await task?.value
        XCTAssertEqual(requests, 1); XCTAssertFalse(s.busy)
        XCTAssertEqual(s.error, "该频道不属于当前保利威账号")
        XCTAssertEqual(s.currentCourseID, existing); XCTAssertNil(s.currentCourse?.ended)
        plan = try XCTUnwrap(s.preparations("100").first)
        XCTAssertTrue(plan.ready); XCTAssertNil(plan.usedByCourseID)
        XCTAssertFalse(s.gateway.isConnected)
    }
    @MainActor func testStopDuringValidationDiscardsLateResponse() async {
        let s = store(); s.channel = "100"
        var continuation: CheckedContinuation<Void, Never>?
        s.channelOwnership.transport = { request in
            await withCheckedContinuation { continuation = $0 }
            return self.result(request, self.owned)
        }
        s.connect(); let task = s.connectionTask
        while continuation == nil { await Task.yield() }
        s.stop(); continuation?.resume(); await task?.value
        XCTAssertFalse(s.busy); XCTAssertNil(s.currentCourseID); XCTAssertTrue(s.error.isEmpty)
        XCTAssertFalse(s.gateway.isConnected)
    }
    @MainActor func testChangedChannelDoesNotUseStaleConnectionValidation() async {
        let s = store(); s.channel = "100"
        s.channelOwnership.transport = { request in
            s.channel = "101"
            return self.result(request, self.owned)
        }
        s.connect(); await s.connectionTask?.value
        XCTAssertEqual(s.error, "开课信息已变更，请重试")
        XCTAssertFalse(s.busy); XCTAssertNil(s.currentCourseID); XCTAssertFalse(s.gateway.isConnected)
    }
}
