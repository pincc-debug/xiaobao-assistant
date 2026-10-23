import Foundation
import CoreFoundation


public struct ViewerPoint: Codable, Identifiable, Equatable {
    public var time: Date
    public var count: Int
    public var source: String
    public var id: String { "\(source):\(time.timeIntervalSince1970)" }
    public init(time: Date, count: Int, source: String) { self.time = time; self.count = count; self.source = source }
}
public struct CourseMetrics: Codable, Equatable {
    public var fetchedAt = Date()
    public var viewers: Int?
    public var views: Int?
    public var peak: Int?
    public var averageMinutes: Int?
    public var totalMinutes: Int?
    public var durationSeconds: Int?
    public var start: Date?
    public var end: Date?
    public init() {}
}
public struct PublicChatRecord: Codable, Identifiable, Equatable {
    public var id: String
    public var userID: String
    public var name: String
    public var role: String
    public var time: Date
    public var text: String
    public var quote: String?
    public var sessionID: String?
    public var isStudent: Bool { ["student", "slice", "attendee", "viewer"].contains(role) }
    public init(id:String, userID:String, name:String, role:String, time:Date, text:String, quote:String? = nil, sessionID:String? = nil) {
        self.id=id; self.userID=userID; self.name=name; self.role=role; self.time=time; self.text=text; self.quote=quote; self.sessionID=sessionID
    }
}
public struct CourseAnalytics: Codable {
    public var points: [ViewerPoint] = []
    public var metrics: CourseMetrics?
    public var lastRealtimeAt: Date?
    public var lastHistoryAt: Date?
    public var realtimeError: String?
    public var syncError: String?
    public var chatSyncedThrough: Date?
    public var chatSyncedFrom: Date?   // start of the window that chatSyncedThrough closes
    public var chatSnapshotStart: Date?
    public var chatSnapshotEnd: Date?
    public var chatNextPage: Int?
    public var chatUnassigned: Int? // Records whose session identity could not be established.
    public var firstCollectedAt: Date?
    public init() {}
}
public enum CourseData {
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier:"Asia/Shanghai")!; return c }
    public static func format(_ date: Date, pattern: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.calendar = calendar; f.timeZone = calendar.timeZone; f.dateFormat = pattern
        return f.string(from:date)
    }
    public static func date(_ raw: Any?) -> Date? {
        let number = (raw as? NSNumber)?.doubleValue ?? Double(raw as? String ?? "")
        if let number, number.isFinite, number > 0 { return Date(timeIntervalSince1970: number > 10_000_000_000 ? number/1000 : number) }
        guard let text = raw as? String else { return nil }
        let f = DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.timeZone=calendar.timeZone; f.dateFormat="yyyy-MM-dd HH:mm:ss"; f.isLenient=false
        return f.date(from:text)
    }
    public static func integer(_ raw: Any?) -> Int? {
        guard !(raw is NSNull) else { return nil }
        let value = (raw as? NSNumber)?.doubleValue ?? Double(raw as? String ?? "")
        guard let value, value.isFinite, value >= 0, value < Double(Int.max), value.rounded() == value else { return nil }
        if let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
        return Int(value)
    }
    public static func string(_ raw: Any?) -> String? {
        if let s = raw as? String, !s.isEmpty { return s }
        if let n = raw as? NSNumber { return n.stringValue }; return nil
    }
    public static func realtime(_ rows: [[String:Any]], channel: String, start: Date, now: Date) -> [ViewerPoint] {
        rows.compactMap { row in
            guard string(row["channelId"]) == channel, let count=integer(row["count"]), let clock=row["time"] as? String else { return nil }
            let day = calendar.startOfDay(for:now)
            let candidates = [-1,0,1].compactMap { delta -> Date? in
                guard let d=calendar.date(byAdding:.day,value:delta,to:day) else { return nil }
                return date(format(d,pattern:"yyyy-MM-dd") + " " + clock)
            }
            guard let time=candidates.min(by:{ abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }), time <= now.addingTimeInterval(5), time >= start, now.timeIntervalSince(time) <= 600 else { return nil }
            return ViewerPoint(time:time,count:count,source:"实时")
        }.sorted { $0.time < $1.time }
    }
    public static func historical(_ rows: [[String:Any]], start: Date, end: Date) -> [ViewerPoint] {
        rows.compactMap { row in
            guard let day=row["day"] as? String, let minute=row["minute"] as? String, let count=integer(row["viewers"]),
                  let time=date(day + " " + minute + (minute.count == 5 ? ":00" : "")), time >= start, time <= end else { return nil }
            return ViewerPoint(time:time,count:count,source:"历史")
        }.sorted { $0.time < $1.time }
    }
    public static func mergePoints(_ old: [ViewerPoint], _ new: [ViewerPoint]) -> [ViewerPoint] {
        var values = Dictionary(old.map { ($0.id,$0) }, uniquingKeysWith: { _,b in b })
        new.forEach { values[$0.id]=$0 }; return values.values.sorted { $0.time < $1.time }
    }
    /// End of the chart / chat sync window. While the class is live the platform summary's endTime can lag far
    /// behind (it may describe an early stream segment), so a live class always syncs up to now; only after 下课
    /// does the platform endTime bound the window.
    public static func syncWindowEnd(metricsEnd: Date?, ended: Date?, live: Bool, now: Date) -> Date {
        live ? now : min(metricsEnd ?? ended ?? now, now)
    }
    /// The platform says the stream stopped more than `grace` seconds ago while the class is still live in the app.
    public static func platformEndedEarly(metricsEnd: Date?, live: Bool, now: Date, grace: TimeInterval = 120) -> Bool {
        guard live, let metricsEnd else { return false }
        return now.timeIntervalSince(metricsEnd) > grace
    }
    public static func metrics(_ row: [String:Any]) -> CourseMetrics {
        var value=CourseMetrics(); value.viewers=integer(row["uniqueViewer"]); value.views=integer(row["videoView"])
        value.peak=integer(row["maxConcurrencyCount"]); value.averageMinutes=integer(row["averagePlayDuration"])
        value.totalMinutes=integer(row["totalPlayDuration"]); value.durationSeconds=integer(row["startDuration"])
        value.start=date(row["startTime"]); value.end=date(row["endTime"]); return value
    }
    public static func chat(_ row: [String:Any], live: Bool = false) -> PublicChatRecord? {
        let user=row["user"] as? [String:Any] ?? [:]
        guard let id=string(row["id"]), let uid=string(user["userId"]), let time=date(row["time"]),
              (row["sourceType"] as? String ?? "public") == "public",
              !["delete","censor"].contains(row["status"] as? String ?? "") else { return nil }
        let event=string(row["EVENT"]) ?? string(row["event"]) ?? "SPEAK"
        guard ["SPEAK","CHAT_IMG","SEND_FILE","speak"].contains(event) else { return nil }
        let kind=row["msgType"] as? String ?? row["msgSource"] as? String ?? ""
        var text=row["content"] as? String ?? (row["values"] as? [String])?.first ?? ""
        if kind == "chatImg" || event == "CHAT_IMG" { text="[图片]" }
        else if kind == "file" || event == "SEND_FILE" { text="[文件]" }
        guard !text.isEmpty else { return nil }
        let quote = row["quote"] as? String ?? (row["quote"] as? [String:Any]).flatMap { try? JSONSerialization.data(withJSONObject:$0) }.flatMap { String(data:$0,encoding:.utf8) }
        return PublicChatRecord(id:id,userID:uid,name:user["nickname"] as? String ?? user["nick"] as? String ?? "观众",role:string(row["userType"]) ?? string(user["userType"]) ?? "unknown",time:time,text:text,quote:quote,sessionID:string(row["sessionId"]) ?? string(user["sessionId"]))
    }
    public static func mergeChat(_ old: [PublicChatRecord], _ new: [PublicChatRecord]) -> [PublicChatRecord] {
        var values = Dictionary(old.map { ($0.id,$0) }, uniquingKeysWith:{ _,b in b })
        for record in new {
            var value=record
            if value.role == "unknown", let existing=values[value.id] { value.role=existing.role }
            values[value.id]=value
        }
        return values.values.sorted { $0.time == $1.time ? $0.id < $1.id : $0.time < $1.time }
    }
    public static func chats(_ course: CourseSession) -> [PublicChatRecord] {
        let fallback=(course.events ?? []).map { PublicChatRecord(id:$0.id,userID:$0.userID,name:$0.name,role:"student",time:$0.time,text:$0.text) }
        return mergeChat(fallback,course.publicChat ?? [])
    }
    public static func report(_ course: CourseSession) -> String {
        let a=course.analytics ?? CourseAnalytics(), chat=chats(course), students=chat.filter(\.isStudent)
        let people=Set(students.map(\.userID)).count
        func number(_ n:Int?) -> String { n.map(String.init) ?? "未取得" }
        let m=a.metrics
        let coverage=a.chatSyncedThrough.map { "平台公聊已同步至 " + $0.ISO8601Format() } ?? "仅已采集记录，未完成平台公聊同步"
        let pending=Set((course.events ?? []).filter { $0.category == "question" }.map(\.id)).subtracting(Set((course.operations ?? []).filter { $0.kind == "question" }.flatMap(\.sourceMessageIDs))).count
        return """
        场次：\(course.platformSessionID ?? "未确认")；时间：\(course.started.ISO8601Format()) 至 \(course.ended?.ISO8601Format() ?? "进行中")
        数据范围：\(coverage)。仅公聊，不含已删除、待审核或私聊。\(a.chatUnassigned ?? 0)条无法确认场次的记录未纳入。
        已采集学生发言：\(students.count)条；发言学生：\(people)人；已记录师生公聊：\(chat.count)条。
        应用已答问答：\(course.answers.count)条；已识别但未处理的问题消息：\(pending)条。此数量不等于平台全场问题数；相同问题可能由不同消息提出。
        平台观看人数：\(number(m?.viewers))；观看次数：\(number(m?.views))；最高并发：\(number(m?.peak))。
        平均观看时长：\(number(m?.averageMinutes))分钟；总观看时长：\(number(m?.totalMinutes))分钟。
        平台汇总获取时间：\(m?.fetchedAt.ISO8601Format() ?? "未取得")；统计生成可能延迟。
        在线趋势点数：\(a.points.count)。缺失不为零；在线下降表示净变化，不等于离场人数，更不能直接断定讲课导致流失。
        同步状态：\(a.syncError ?? "无已报告错误")
        """
    }
}
