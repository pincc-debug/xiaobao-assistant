import XCTest
import Foundation
import AssistantCore
@testable import Assistant

/// Live 「对助教说」 tool-choice eval against production `ProviderAPI.chooseTool` + `AssistantTool.voice`.
/// Enable with XB_VOICE_TOOL_EVAL=1. Writes report to ~/br-tmp/duizhujiao-eval-report-4981e33.md (override via XB_VOICE_TOOL_EVAL_REPORT).
final class VoiceToolChoiceEval: XCTestCase {
    private struct Case {
        let id: Int
        let utterance: String
        let expected: String
        let note: String
        let kind: Kind
        let seed: Seed
        enum Kind { case positive, boundary, negative }
        struct Seed {
            var previous: [[String: Any]] = []
            var results: [[String: Any]] = []
        }
    }

    private let removedTools: Set<String> = [
        "send_chat_message", "reply_chat_message", "remove_notice",
        "stop_checkin", "get_checkin_result",
        "stop_answer_card", "get_answer_result", "publish_answer_result",
        "stop_questionnaire", "start_rush_answer", "stop_rush_answer",
        "pause_timer", "end_timer",
        "list_cards", "push_card", "withdraw_card",
        "list_lotteries", "start_lottery", "end_lottery", "get_lottery_result",
        "list_enroll_lotteries", "draw_enroll_lottery",
        "mute_user", "unmute_user", "kick_user", "restore_user"
    ]

    @MainActor
    func testLiveVoiceToolChoiceEval() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XB_VOICE_TOOL_EVAL"] == "1", "set XB_VOICE_TOOL_EVAL=1 to run live eval")

        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveAssistant")
        let state = try StateFile(url: support.appendingPathComponent("state.json")).read()
        let provider = try XCTUnwrap(state.providers.first { $0.id == state.defaultProviderID }, "default answer provider missing")
        let keyName = "provider." + provider.id.uuidString
        let key = Vault.read(keyName)
        XCTAssertFalse(key.isEmpty, "provider key missing in credentials (name only checked)")

        let cases = Self.cases()
        XCTAssertEqual(cases.count, 40)

        var rows: [(Case, Outcome)] = []
        for item in cases {
            let outcome = await runCase(item, provider: provider, key: key)
            rows.append((item, outcome))
            let mark = outcome.pass ? "PASS" : "FAIL"
            print("VOICE_EVAL", item.id, mark, "expected=\(item.expected)", "actual=\(outcome.actual)", outcome.reason)
        }

        let passed = rows.filter { $0.1.pass }.count
        let failed = rows.count - passed
        let reportURL = reportURL()
        try writeReport(rows: rows, providerName: provider.name, model: provider.model, url: reportURL)
        print("VOICE_EVAL_SUMMARY", "pass=\(passed)", "fail=\(failed)", "total=\(rows.count)", "report=\(reportURL.path)")
        if ProcessInfo.processInfo.environment["XB_VOICE_TOOL_EVAL_SOFT"] == "1" {
            if failed > 0 { print("VOICE_EVAL_SOFT_FAIL", failed) }
        } else {
            XCTAssertEqual(failed, 0, "voice tool-choice eval had \(failed) failures; see \(reportURL.path)")
        }
    }

    private struct Outcome {
        var actual: String
        var hops: [String]
        var args: [String: Any]
        var message: String
        var pass: Bool
        var reason: String
        var chainNote: String
    }

    private func runCase(_ item: Case, provider: ModelProvider, key: String) async -> Outcome {
        var results = item.seed.results
        var previous = item.seed.previous
        var hops: [String] = []
        var lastArgs: [String: Any] = [:]
        var lastMessage = ""
        let maxHops = item.expected.contains("→") ? 2 : 1

        do {
            for _ in 0..<maxHops {
                let context: [String: Any] = [
                    "instruction": item.utterance,
                    "previous": previous,
                    "results": results,
                    "active_interactions": [] as [[String: Any]],
                    "pending": [] as [[String: Any]],
                    "viewers": [] as [[String: Any]]
                ]
                let choice = try await chooseToolWithRetry(provider: provider, key: key, input: context)
                if let name = choice["name"] as? String, let arguments = choice["arguments"] as? [String: Any] {
                    hops.append(name)
                    lastArgs = arguments
                    let stub = stubResult(for: name, utterance: item.utterance, args: arguments)
                    results.append(["name": name, "result": stub])
                    previous.append(["instruction": item.utterance, "tool": name, "result": stub])
                    // Launch tools end the product loop early; list/find continue.
                    if ["start_answer_card", "start_checkin", "publish_notice", "send_material", "start_questionnaire", "start_timer"].contains(name) {
                        break
                    }
                } else {
                    lastMessage = (choice["message"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    hops.append("clarify")
                    break
                }
            }
        } catch {
            return Outcome(actual: "error", hops: [], args: [:], message: "", pass: false, reason: "API error: \(error.localizedDescription)", chainNote: "")
        }

        let first = hops.first ?? "clarify"
        let actualLabel: String
        if hops.isEmpty {
            actualLabel = "clarify"
        } else if hops.count == 1 {
            actualLabel = hops[0] == "clarify" ? "clarify" : hops[0]
        } else {
            actualLabel = hops.joined(separator: " → ")
        }

        let chainNote = item.expected.contains("→") ? (hops.count >= 2 ? "chain ran \(hops.count) hops" : "scored first hop only") : ""
        let argTool = hops.last(where: { $0 != "clarify" }) ?? first
        let (pass, reason) = score(item: item, hops: hops, first: first, argTool: argTool, args: lastArgs, message: lastMessage)
        return Outcome(actual: actualLabel, hops: hops, args: lastArgs, message: lastMessage, pass: pass, reason: reason, chainNote: chainNote)
    }

    private func score(item: Case, hops: [String], first: String, argTool: String, args: [String: Any], message: String) -> (Bool, String) {
        let expected = item.expected.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .positive:
            let firstExpected = expected.split(separator: "→").map { $0.trimmingCharacters(in: .whitespaces) }.first ?? expected
            guard first == firstExpected else {
                return (false, "want first hop \(firstExpected), got \(first)")
            }
            if let argFail = checkArgs(item: item, tool: argTool, args: args) {
                return (false, argFail)
            }
            if expected.contains("→"), hops.count >= 2 {
                let parts = expected.split(separator: "→").map { $0.trimmingCharacters(in: .whitespaces) }
                if hops.count >= 2, hops[1] != parts[1] {
                    return (true, "first hop ok; second hop \(hops[1]) ≠ \(parts[1]) (noted)")
                }
            }
            return (true, "ok")
        case .boundary:
            if expected.hasPrefix("clarify 或") {
                let alt = expected.replacingOccurrences(of: "clarify 或 ", with: "").trimmingCharacters(in: .whitespaces)
                if first == "clarify" || first == alt {
                    return (true, "ok (\(first))")
                }
                return (false, "want clarify or \(alt), got \(first)")
            }
            if first == "clarify" { return (true, "ok") }
            return (false, "want clarify, got \(first)")
        case .negative:
            if first == "clarify" { return (true, "ok") }
            if removedTools.contains(first) {
                return (false, "called removed tool \(first)")
            }
            // Not a removed tool — not the cut regression we measure.
            return (true, "no removed tool (got \(first))")
        }
    }

    private func checkArgs(item: Case, tool: String, args: [String: Any]) -> String? {
        let note = item.note
        if tool == "publish_notice", note.contains("content 含休息") {
            let content = (args["content"] as? String ?? "")
            if !content.contains("休息") { return "args: content missing 休息 (\(content))" }
        }
        if tool == "find_materials", note.contains("query≈第一章") {
            let q = args["query"] as? String ?? ""
            if !q.contains("第一章") { return "args: query missing 第一章 (\(q))" }
        }
        if tool == "start_checkin" {
            if note.contains("duration=60"), intArg(args, "duration_seconds") != 60 {
                return "args: duration_seconds want 60 got \(String(describing: args["duration_seconds"]))"
            }
            if note.contains("duration=120"), intArg(args, "duration_seconds") != 120 {
                return "args: duration_seconds want 120 got \(String(describing: args["duration_seconds"]))"
            }
            if note.contains("tips=请签到") {
                let tips = args["tips"] as? String ?? ""
                if !tips.contains("请签到") { return "args: tips missing 请签到 (\(tips))" }
            }
            if item.id == 10, intArg(args, "duration_seconds") != 90 {
                return "args: duration_seconds want 90 got \(String(describing: args["duration_seconds"]))"
            }
        }
        if tool == "start_answer_card", note.contains("duration_seconds=0") || note.contains("duration=0") {
            if intArg(args, "duration_seconds") != 0 {
                return "args: duration_seconds want 0 got \(String(describing: args["duration_seconds"]))"
            }
        }
        if tool == "start_timer" {
            if note.contains("duration=300"), intArg(args, "duration_seconds") != 300 {
                return "args: duration_seconds want 300 got \(String(describing: args["duration_seconds"]))"
            }
            if note.contains("duration=180"), intArg(args, "duration_seconds") != 180 {
                return "args: duration_seconds want 180 got \(String(describing: args["duration_seconds"]))"
            }
            if note.contains("duration=600"), intArg(args, "duration_seconds") != 600 {
                return "args: duration_seconds want 600 got \(String(describing: args["duration_seconds"]))"
            }
        }
        return nil
    }

    private func intArg(_ args: [String: Any], _ key: String) -> Int? {
        if let n = args[key] as? Int { return n }
        if let n = args[key] as? NSNumber { return n.intValue }
        if let s = args[key] as? String { return Int(s) }
        return nil
    }

    private func chooseToolWithRetry(provider: ModelProvider, key: String, input: [String: Any]) async throws -> [String: Any] {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try await ProviderAPI.chooseTool(provider, key: key, input: input)
            } catch {
                lastError = error
                let msg = error.localizedDescription
                let transient = msg.contains("回答格式异常") || msg.contains("服务请求失败") || msg.contains("超时")
                if !transient || attempt == 3 { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 800_000_000)
            }
        }
        throw lastError ?? AppError.message("chooseTool failed")
    }

        private func stubResult(for name: String, utterance: String, args: [String: Any]) -> Any {
        switch name {
        case "find_materials":
            return [["id": "mat-seed-1", "name": "第一章-导论.pptx"]]
        case "list_exercises":
            let q = utterance.contains("数组") ? "关于数组的练习题" : "第一道练习题示例"
            return [["id": "ex-seed-1", "question": q, "sent": false] as [String: Any]]
        case "list_questionnaires":
            return [["id": "qn-seed-1", "name": "课前调研", "title": "课前调研"] as [String: Any]]
        case "send_material", "start_answer_card", "start_questionnaire", "publish_notice", "start_checkin", "start_timer":
            return ["ok": true]
        default:
            return ["ok": true, "echo": args]
        }
    }

    private func reportURL() -> URL {
        if let custom = ProcessInfo.processInfo.environment["XB_VOICE_TOOL_EVAL_REPORT"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("br-tmp/duizhujiao-eval-report-4981e33.md")
    }

    private func writeReport(rows: [(Case, Outcome)], providerName: String, model: String, url: URL) throws {
        let passed = rows.filter { $0.1.pass }.count
        let failed = rows.count - passed
        let pos = rows.filter { $0.0.kind == .positive }
        let bound = rows.filter { $0.0.kind == .boundary }
        let neg = rows.filter { $0.0.kind == .negative }
        var md = ""
        md += "# 「对助教说」tool-choice 评测报告 · 4981e33\n\n"
        let shanghai = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = shanghai; df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        md += "- 时间：\(df.string(from: Date()))（Asia/Shanghai）\n"
        md += "- 路径：`ProviderAPI.chooseTool` + `AssistantTool.voice`（生产 system prompt）\n"
        md += "- 回答模型：\(providerName) / \(model)（key 来自 credentials，未写入本报告）\n"
        md += "- 口令表：`~/br-tmp/duizhujiao-eval-utterances-4981e33.md`\n"
        md += "- 结果：**\(passed)/\(rows.count) pass**（fail \(failed)）\n"
        md += "  - 正例 \(pos.filter { $0.1.pass }.count)/\(pos.count)\n"
        md += "  - 边界 \(bound.filter { $0.1.pass }.count)/\(bound.count)\n"
        md += "  - 负例 \(neg.filter { $0.1.pass }.count)/\(neg.count)\n\n"
        md += "## 明细\n\n"
        md += "| # | 口令 | 期望 | 实际 | 通过 | 备注 |\n"
        md += "|---|------|------|------|------|------|\n"
        for (item, out) in rows {
            let utter = item.utterance.replacingOccurrences(of: "|", with: "\\|")
            var note = out.reason
            if !out.chainNote.isEmpty { note += "; " + out.chainNote }
            if !out.message.isEmpty, out.hops.first == "clarify" {
                let clip = out.message.count > 40 ? String(out.message.prefix(40)) + "…" : out.message
                note += "; msg=" + clip.replacingOccurrences(of: "|", with: "/")
            }
            if !out.args.isEmpty, item.kind == .positive {
                if let compact = try? String(data: JSONSerialization.data(withJSONObject: out.args, options: [.sortedKeys]), encoding: .utf8) {
                    let clip = compact.count > 80 ? String(compact.prefix(80)) + "…" : compact
                    note += "; args=" + clip.replacingOccurrences(of: "|", with: "/")
                }
            }
            note = note.replacingOccurrences(of: "\n", with: " ")
            md += "| \(item.id) | \(utter) | \(item.expected) | \(out.actual) | \(out.pass ? "✅" : "❌") | \(note) |\n"
        }
        let fails = rows.filter { !$0.1.pass }
        md += "\n## 失败分析\n\n"
        if fails.isEmpty {
            md += "无失败。\n"
        } else {
            var modes: [String: Int] = [:]
            for (item, out) in fails {
                let mode: String
                if item.kind == .negative, removedTools.contains(out.hops.first ?? "") {
                    mode = "负例仍调已裁 tool"
                } else if item.kind == .boundary {
                    mode = "边界未追问"
                } else if out.actual == "error" {
                    mode = "API/运行错误"
                } else if item.kind == .positive, out.reason.hasPrefix("args:") {
                    mode = "参数不符"
                } else if item.kind == .positive {
                    mode = "正例工具选错"
                } else {
                    mode = "其他"
                }
                modes[mode, default: 0] += 1
                md += "- #\(item.id) \(item.utterance)：期望 `\(item.expected)`，实际 `\(out.actual)` — \(out.reason)\n"
            }
            md += "\n### 失败模式汇总\n\n"
            for (k, v) in modes.sorted(by: { $0.value > $1.value }) {
                md += "- \(k)：\(v)\n"
            }
        }
        md += "\n## 说明\n\n"
        md += "- 链式口令最多跑 2 跳；list/find 的返回为本地 stub，不打 POLYV。\n"
        md += "- 负例：clarify 或未调已裁 tool 即过；调已裁 tool 判失败。\n"
        md += "- 边界 `clarify 或 list_*`：clarify 或对应 list 均过。\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try md.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func cases() -> [Case] {
        let matSeed = Case.Seed(
            previous: [["instruction": "找一下课件里带「第一章」的", "tool": "find_materials", "result": [["id": "mat-seed-1", "name": "第一章-导论.pptx"]]]],
            results: [["name": "find_materials", "result": [["id": "mat-seed-1", "name": "第一章-导论.pptx"]]]]
        )
        let exSeed = Case.Seed(
            previous: [["instruction": "看看笔记里有哪些练习题", "tool": "list_exercises", "result": [["id": "ex-seed-1", "question": "关于数组的练习题", "sent": false]]]],
            results: [["name": "list_exercises", "result": [["id": "ex-seed-1", "question": "关于数组的练习题", "sent": false]]]]
        )
        let qnSeed = Case.Seed(
            previous: [["instruction": "查一下有哪些问卷", "tool": "list_questionnaires", "result": [["id": "qn-seed-1", "name": "课前调研"]]]],
            results: [["name": "list_questionnaires", "result": [["id": "qn-seed-1", "name": "课前调研"]]]]
        )

        let list: [Case] = [
            .init(id: 1, utterance: "发个公告：下节课休息五分钟", expected: "publish_notice", note: "content 含休息", kind: .positive, seed: .init()),
            .init(id: 2, utterance: "公告一下，请大家把麦关了", expected: "publish_notice", note: "", kind: .positive, seed: .init()),
            .init(id: 3, utterance: "帮我发公告，今晚作业交到后台", expected: "publish_notice", note: "", kind: .positive, seed: .init()),
            .init(id: 4, utterance: "找一下课件里带「第一章」的", expected: "find_materials", note: "query≈第一章", kind: .positive, seed: .init()),
            .init(id: 5, utterance: "搜一下 PPT，关键词是期中复习", expected: "find_materials", note: "", kind: .positive, seed: .init()),
            .init(id: 6, utterance: "把「第一章」那个课件发出去", expected: "find_materials → send_material", note: "先查再发", kind: .positive, seed: .init()),
            .init(id: 7, utterance: "发一下刚才找到的那个课件", expected: "send_material", note: "依赖 previous/results 有 material_id", kind: .positive, seed: matSeed),
            .init(id: 8, utterance: "发起签到，六十秒，提示写「请签到」", expected: "start_checkin", note: "duration=60 tips=请签到", kind: .positive, seed: .init()),
            .init(id: 9, utterance: "开个两分钟签到，提示「到课打卡」", expected: "start_checkin", note: "duration=120", kind: .positive, seed: .init()),
            .init(id: 10, utterance: "签到一下，时长九十秒", expected: "start_checkin", note: "tips 可默认/追问后补", kind: .positive, seed: .init()),
            .init(id: 11, utterance: "看看笔记里有哪些练习题", expected: "list_exercises", note: "", kind: .positive, seed: .init()),
            .init(id: 12, utterance: "列一下本场练习题", expected: "list_exercises", note: "", kind: .positive, seed: .init()),
            .init(id: 13, utterance: "把第一道练习题发成答题卡", expected: "list_exercises → start_answer_card", note: "duration_seconds=0", kind: .positive, seed: .init()),
            .init(id: 14, utterance: "发答题卡，用笔记里那道关于数组的题", expected: "list_exercises → start_answer_card", note: "", kind: .positive, seed: .init()),
            .init(id: 15, utterance: "把这道练习题发出去当答题卡", expected: "start_answer_card", note: "依赖 results 已有 exercise_id；duration=0", kind: .positive, seed: exSeed),
            .init(id: 16, utterance: "查一下有哪些问卷", expected: "list_questionnaires", note: "", kind: .positive, seed: .init()),
            .init(id: 17, utterance: "列一下问卷列表", expected: "list_questionnaires", note: "", kind: .positive, seed: .init()),
            .init(id: 18, utterance: "把课前调研那个问卷发一下", expected: "list_questionnaires → start_questionnaire", note: "", kind: .positive, seed: .init()),
            .init(id: 19, utterance: "发布刚才查到的那个问卷", expected: "start_questionnaire", note: "依赖 questionnaire_id", kind: .positive, seed: qnSeed),
            .init(id: 20, utterance: "开个五分钟倒计时", expected: "start_timer", note: "duration=300", kind: .positive, seed: .init()),
            .init(id: 21, utterance: "倒计时三分钟", expected: "start_timer", note: "duration=180", kind: .positive, seed: .init()),
            .init(id: 22, utterance: "开始十分钟倒计时", expected: "start_timer", note: "duration=600", kind: .positive, seed: .init()),
            .init(id: 23, utterance: "发起签到", expected: "clarify", note: "缺 duration", kind: .boundary, seed: .init()),
            .init(id: 24, utterance: "帮我签个到，提示写「到课」", expected: "clarify", note: "缺 duration", kind: .boundary, seed: .init()),
            .init(id: 25, utterance: "发个公告", expected: "clarify", note: "缺 content", kind: .boundary, seed: .init()),
            .init(id: 26, utterance: "发课件", expected: "clarify", note: "缺文件名/id", kind: .boundary, seed: .init()),
            .init(id: 27, utterance: "发答题卡", expected: "clarify 或 list_exercises", note: "缺题；可先 list 再问发哪道", kind: .boundary, seed: .init()),
            .init(id: 28, utterance: "发问卷", expected: "clarify 或 list_questionnaires", note: "同上", kind: .boundary, seed: .init()),
            .init(id: 29, utterance: "停掉签到", expected: "clarify", note: "引导点进行中卡片", kind: .negative, seed: .init()),
            .init(id: 30, utterance: "暂停倒计时", expected: "clarify", note: "", kind: .negative, seed: .init()),
            .init(id: 31, utterance: "结束倒计时", expected: "clarify", note: "", kind: .negative, seed: .init()),
            .init(id: 32, utterance: "公布答题结果", expected: "clarify", note: "引导点「公布结果」", kind: .negative, seed: .init()),
            .init(id: 33, utterance: "停掉答题卡", expected: "clarify", note: "", kind: .negative, seed: .init()),
            .init(id: 34, utterance: "撤下公告", expected: "clarify", note: "", kind: .negative, seed: .init()),
            .init(id: 35, utterance: "禁言那个刷屏的", expected: "clarify", note: "jev/手动，不嘴说", kind: .negative, seed: .init()),
            .init(id: 36, utterance: "把某某踢出去", expected: "clarify", note: "", kind: .negative, seed: .init()),
            .init(id: 37, utterance: "发一句公聊：大家加油", expected: "clarify", note: "公聊已裁", kind: .negative, seed: .init()),
            .init(id: 38, utterance: "开个抢答一分钟", expected: "clarify", note: "抢答已裁", kind: .negative, seed: .init()),
            .init(id: 39, utterance: "抽个奖，奖品是周边，抽三人", expected: "clarify", note: "抽奖已裁", kind: .negative, seed: .init()),
            .init(id: 40, utterance: "推一张卡片", expected: "clarify", note: "推送卡片已裁", kind: .negative, seed: .init()),
        ]
        return list
    }
}
