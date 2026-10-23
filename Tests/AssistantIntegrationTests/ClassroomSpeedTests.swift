import XCTest
import AssistantCore
@testable import Assistant

final class ClassroomSpeedTests: XCTestCase {
    @MainActor func spin(until condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<1000 { if condition() { return }; await Task.yield() }
        XCTFail("Expected asynchronous progress")
    }
    @MainActor func testSlowIssueDoesNotBlockClassificationOrIndependentIssue() async throws {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.channel = "100"; s.ensureCourse()
        var classified: [String] = []
        var gate: CheckedContinuation<Void,Never>?
        var planned: [String] = []
        s.classifyMessage = { item, _ in
            classified.append(item.id)
            return (item.id == "chat" ? "chat" : "technical","none")
        }
        s.classroomDecisionOverride = { context in
            let id = (context["message"] as! [String:String])["id"]!
            planned.append(id)
            if id == "slow" { await withCheckedContinuation { gate = $0 } }
            return ["name":"route_message","arguments":["category":"technical","relation":"new","issue_id":"none","reason":"测试反馈"]]
        }
        s.receive(.init(id:"slow",userID:"a",name:"甲",text:"声音有回声"))
        await spin { gate != nil }
        s.receive(.init(id:"chat",userID:"b",name:"乙",text:"大家好"))
        s.receive(.init(id:"other",userID:"c",name:"丙",text:"画面黑了"))
        await spin { classified.count == 3 && s.currentCourse?.events?.first(where: { $0.id == "chat" })?.category == "chat" && s.messages.contains(where: { $0.sourceMessages.contains(where: { $0.id == "other" }) }) }
        XCTAssertEqual(classified,["slow","chat","other"])
        XCTAssertEqual(planned,["slow","other"],"Idle chat must not reach the LLM")
        XCTAssertFalse(s.messages.contains { $0.sourceMessages.contains { $0.id == "slow" } })
        gate?.resume(); gate = nil
        await spin { s.pendingIncoming == 0 }
        XCTAssertEqual(s.currentCourse?.classroomIssues?.count,2)
    }
    @MainActor func testWorkQueueBoundsConcurrencyAndSerializesSameIssue() async {
        let q = ClassroomWorkQueue(limit:4)
        var started: [String] = []
        var gates: [String:CheckedContinuation<Void,Never>] = [:]
        for key in ["a","b","c","d","e"] {
            q.enqueue(key:key,question:key) {
                started.append(key)
                await withCheckedContinuation { gates[key] = $0 }
            }
        }
        q.enqueue(key:"a",question:"a followup") { started.append("a2") }
        await spin { started.count == 4 }
        XCTAssertEqual(Set(started),Set(["a","b","c","d"]))
        XCTAssertEqual(q.count,6)
        gates.removeValue(forKey:"b")?.resume()
        await spin { started.contains("e") }
        XCTAssertFalse(started.contains("a2"))
        gates.removeValue(forKey:"a")?.resume()
        await spin { started.contains("a2") }
        for gate in gates.values { gate.resume() }; gates.removeAll()
        await spin { q.count == 0 }
    }
    @MainActor func testNewClassificationSeesInFlightIssueReservation() async {
        let s = Store(preview:true,storageURL:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json"))
        s.channel = "100"; s.ensureCourse()
        var gate: CheckedContinuation<Void,Never>?
        var reserved: String?
        s.classifyMessage = { item, groups in
            if item.id == "second" { reserved = groups.first(where: { $0.1 == "回声" })?.0; return ("technical",reserved ?? "none") }
            return ("technical","none")
        }
        s.classroomDecisionOverride = { context in
            if (context["message"] as? [String:String])?["id"] == "first" { await withCheckedContinuation { gate = $0 } }
            let issues = context["issues"] as? [[String:String]] ?? []
            if let issue = issues.first {
                let results = context["results"] as? [[String:Any]] ?? []
                if results.isEmpty { return ["name":"read_issue","arguments":["id":issue["id"]!]] }
                return ["name":"route_message","arguments":["category":"technical","relation":"merge","issue_id":issue["id"]!,"reason":"同类反馈"]]
            }
            return ["name":"route_message","arguments":["category":"technical","relation":"new","issue_id":"none","reason":"新反馈"]]
        }
        s.receive(.init(id:"first",userID:"a",name:"甲",text:"回声"))
        await spin { gate != nil }
        s.receive(.init(id:"second",userID:"b",name:"乙",text:"我也有回声"))
        await spin { reserved != nil }
        gate?.resume(); gate = nil
        await spin { s.pendingIncoming == 0 }
        XCTAssertEqual(s.currentCourse?.classroomIssues?.count,1)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.id.uuidString,reserved)
        XCTAssertEqual(s.currentCourse?.classroomIssues?.first?.participants.count,2)
    }
}

extension ClassroomSpeedTests {
    @MainActor func testRealDecisionModelLatency() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_CLASSIFIER_SPEED_LIVE"] == "1")
        let key = Vault.read("jev")
        try XCTSkipIf(key.isEmpty,"No configured decision key")
        let client = ModelsClient(preferences:Preferences(),jevKey:key,dashKey:"",provider:nil,providerKey:"")
        let samples = [("大家好","chat"),("老师声音断断续续，听不清","technical"),("教学目标的三个方面是什么？","question"),("讲得太快了，希望再补一个例子","feedback")]
        for (text, expected) in samples {
            let start = Date()
            let result = try await client.classify(text,groups:[],focus:"小学数学教资教学设计，教学目标和教学过程")
            print("CLASSIFIER_LATENCY",expected,Int(Date().timeIntervalSince(start)*1000),"ms",result.0)
            XCTAssertEqual(result.0,expected)
        }
    }
}
