import Foundation
import AssistantCore

actor StatisticsThrottle {
    static let shared = StatisticsThrottle()
    private var next = Date.distantPast
    func wait() async throws {
        let slot=max(Date(),next); next=slot.addingTimeInterval(1)
        let delay=slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(nanoseconds:UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
    }
}

/// Uses a captured channel and credentials, never the gateway's currently connected room.
struct CourseDataClient {
    let appID: String
    let secret: String
    let channel: String
    var override: ((String,[String:String]) async throws -> Any)?
    func get(_ path:String, _ params:[String:String]) async throws -> Any {
        if let override { return try await override(path,params.merging(["channelId":channel]) { _,new in new }) }
        guard !appID.isEmpty, !secret.isEmpty else { throw AppError.message("请先配置保利威连接") }
        try await StatisticsThrottle.shared.wait()
        var fields=params
        if fields["channelIds"] == nil { fields["channelId"]=channel }
        fields["appId"]=appID; fields["timestamp"]=String(Int(Date().timeIntervalSince1970*1000))
        fields["sign"]=ChatGateway.signature(fields,secret:secret)
        var url=URLComponents(string:"https://api.polyv.net" + path)!
        url.queryItems=fields.sorted { $0.key < $1.key }.map { URLQueryItem(name:$0.key,value:$0.value) }
        var request=URLRequest(url:url.url!); request.timeoutInterval=25
        let json=try await ProviderAPI.execute(request)
        guard CourseData.integer(json["code"]) == 200 else { throw AppError.message("平台数据暂不可用，请检查权限或稍后重试") }
        guard let data=json["data"], !(data is NSNull) else { throw AppError.message("平台暂未返回数据") }
        return data
    }
}

extension Store {
    func updateCourseData(_ id: UUID, _ change:(inout CourseSession) -> Void) throws {
        guard !persistenceBlocked else { throw AppError.message("本地资料无法保存，请先恢复备份") }
        guard let index=saved.courses.firstIndex(where:{$0.id == id}) else { throw CancellationError() }
        var updated=saved; change(&updated.courses[index]); try file.write(updated); saved=updated
    }
    func statisticsClient(_ channel: String) -> CourseDataClient {
        CourseDataClient(appID:saved.preferences.appID,secret:polyvSecret,channel:channel,override:statisticsOverride)
    }
    func collectPublicChat(_ record: PublicChatRecord) {
        guard let id=currentCourseID, let course=currentCourse else { return }
        if let sid=record.sessionID, let expected=course.platformSessionID, sid != expected { return }
        guard record.time >= course.started.addingTimeInterval(-5) else { return }
        do { try updateCourseData(id) { c in
            c.publicChat=CourseData.mergeChat(c.publicChat ?? [],[record])
            if c.analytics == nil { c.analytics=CourseAnalytics() }
            if c.analytics?.firstCollectedAt == nil { c.analytics?.firstCollectedAt=Date() }
        } } catch { dataErrors[id]="课堂记录保存失败" }
    }
    func startStatisticsPolling() {
        guard statisticsPolling == nil, !previewMode else { return }
        statisticsPolling=Task { [weak self] in
            var failures=0
            while !Task.isCancelled {
                guard let self else { return }
                if self.connected, let id=self.currentCourseID {
                    let success=await self.pollRealtimeData(courseID:id)
                    failures=success ? 0 : min(3,failures+1)
                    if let course=self.currentCourse, let sid=course.platformSessionID, !sid.isEmpty,
                       Date().timeIntervalSince(self.lastDataSyncAttempt[id] ?? .distantPast) > 300 {
                        self.scheduleCourseDataSync(id)
                    }
                }
                do { try await Task.sleep(nanoseconds:UInt64(15 * pow(2,Double(failures)) * 1_000_000_000)) } catch { return }
            }
        }
    }
    @discardableResult func pollRealtimeData(courseID: UUID, now: Date = Date()) async -> Bool {
        guard let course=saved.courses.first(where:{$0.id == courseID}), currentCourseID == courseID, connected else { return false }
        let generation=epoch
        let client=statisticsClient(course.channel)
        do {
            let value=try await client.get("/live/v2/statistics/get-realtime-viewers",["channelIds":course.channel])
            try Task.checkCancellation()
            guard generation == epoch, currentCourseID == courseID, connected else { return false }
            guard let rows=value as? [[String:Any]] else { throw AppError.message("在线数据格式暂不可用") }
            let points=CourseData.realtime(rows,channel:course.channel,start:course.started,now:now)
            try updateCourseData(courseID) { c in
                var a=c.analytics ?? CourseAnalytics(); a.points=CourseData.mergePoints(a.points,points)
                if !points.isEmpty { a.lastRealtimeAt=now }; a.realtimeError=points.isEmpty ? "暂未取得在线数据" : nil
                c.analytics=a
            }
            dataErrors[courseID]=nil
            return !points.isEmpty
        } catch {
            guard generation == epoch, currentCourseID == courseID, !Task.isCancelled else { return false }
            try? updateCourseData(courseID) { c in
                if c.analytics == nil { c.analytics=CourseAnalytics() }; c.analytics?.realtimeError="在线数据更新失败"
            }
            dataErrors[courseID]="在线数据更新失败，稍后自动重试"
            return false
        }
    }
    func scheduleCourseDataSync(_ id: UUID) {
        guard dataSyncTasks[id] == nil, !previewMode || statisticsOverride != nil else { return }
        dataSyncTasks[id]=Task { [weak self] in
            await self?.refreshCourseData(id)
            self?.dataSyncTasks[id]=nil
        }
    }
    func scheduleFinalCourseDataSync(_ id: UUID) {
        guard !previewMode, finalDataSyncTasks[id] == nil else { return }
        finalDataSyncTasks[id]=Task { [weak self] in
            defer { self?.finalDataSyncTasks[id]=nil }
            // Give platform aggregation time to settle. Later openings can refresh again.
            do { try await Task.sleep(nanoseconds:45_000_000_000) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.dataSyncTasks[id]?.value
            guard !Task.isCancelled else { return }
            await self.refreshCourseData(id)
        }
    }
    func refreshCourseData(_ id: UUID) async {
        guard !dataSyncBusy.contains(id), let initial=saved.courses.first(where:{$0.id == id}) else { return }
        guard dataSyncBusy.count < 2 else { dataErrors[id]="正在更新其他课程，请稍后重试"; return }
        guard let session=initial.platformSessionID, !session.isEmpty else { dataErrors[id]="场次尚未确认"; return }
        // Covers manual, model-triggered and automatic refreshes.
        guard Date().timeIntervalSince(lastDataSyncAttempt[id] ?? .distantPast) >= 30 else { return }
        lastDataSyncAttempt[id]=Date(); dataSyncBusy.insert(id); dataErrors[id]=nil
        defer { dataSyncBusy.remove(id) }
        let client=statisticsClient(initial.channel)
        let account=saved.preferences.appID
        var errors:[String]=[]
        func valid() throws {
            try Task.checkCancellation()
            guard saved.preferences.appID == account,
                  saved.courses.contains(where:{$0.id == id && $0.channel == initial.channel && $0.platformSessionID == session}) else { throw CancellationError() }
        }
        // Each source has independent failure handling; a failed chart request must not discard chat data.
        do {
            let data=try await client.get("/live/v4/statistics/session-stats/summary/list",["keyword":session,"pageNumber":"1","pageSize":"20"])
            try valid()
            guard let object=data as? [String:Any], let rows=object["contents"] as? [[String:Any]],
                  let row=rows.first(where:{ CourseData.string($0["sessionId"]) == session && CourseData.string($0["channelId"]) == initial.channel }) else { throw AppError.message("统计尚未生成") }
            let metrics=CourseData.metrics(row)
            diagnostic("course_data.sync.summary", ["session":session,"rows":rows.count,"platformStart":stamp(metrics.start),"platformEnd":stamp(metrics.end),"durationSeconds":metrics.durationSeconds ?? -1])
            try updateCourseData(id) { c in
                if c.analytics == nil { c.analytics=CourseAnalytics() }; c.analytics?.metrics=metrics
                if let start=metrics.start { c.started=start; c.startTimeVerified=true }
            }
        } catch is CancellationError { return } catch { errors.append("运营概况暂未更新"); diagnostic("course_data.sync.summary", ["session":session,"error":safe(error)], error: true) }
        guard let course=saved.courses.first(where:{$0.id == id}) else { return }
        let start=course.analytics?.metrics?.start ?? course.started
        let live=currentCourseID == id && connected && course.ended == nil
        let end=CourseData.syncWindowEnd(metricsEnd:course.analytics?.metrics?.end,ended:course.ended,live:live,now:Date())
        if end >= start, end.timeIntervalSince(start) <= 60*24*3600 {
            do {
                let data=try await client.get("/live/v3/channel/statistics/concurrence",["startDate":CourseData.format(start,pattern:"yyyy-MM-dd"),"endDate":CourseData.format(end,pattern:"yyyy-MM-dd")])
                try valid()
                guard let rows=data as? [[String:Any]] else { throw AppError.message("趋势数据尚未生成") }
                let points=CourseData.historical(rows,start:start,end:end)
                diagnostic("course_data.sync.trend", ["session":session,"live":live,"windowStart":stamp(start),"windowEnd":stamp(end),"rows":rows.count,"points":points.count])
                try updateCourseData(id) { c in
                    var a=c.analytics ?? CourseAnalytics(); a.points=CourseData.mergePoints(a.points,points); a.lastHistoryAt=Date(); c.analytics=a
                }
            } catch is CancellationError { return } catch { errors.append("人数趋势暂未更新"); diagnostic("course_data.sync.trend", ["session":session,"windowStart":stamp(start),"windowEnd":stamp(end),"error":safe(error)], error: true) }
        } else { errors.append("场次时间范围需核实"); diagnostic("course_data.sync.trend", ["session":session,"windowStart":stamp(start),"windowEnd":stamp(end),"error":"场次时间范围需核实"], error: true) }
        // Freeze the page window and checkpoint every page. Resume partial imports on the next refresh.
        do {
            let snapshot=course.analytics?.chatSnapshotEnd ?? Date(timeIntervalSince1970:floor(end.timeIntervalSince1970))
            let queryStart=course.analytics?.chatSnapshotStart ?? start
            guard snapshot >= queryStart else { throw AppError.message("场次时间范围无效") }
            var page=course.analytics?.chatNextPage ?? 1
            var excluded=course.analytics?.chatNextPage == nil ? 0 : course.analytics?.chatUnassigned ?? 0
            let firstPage=page; var fetchedPages=0, fetchedRows=0, keptRows=0, done=false
            defer {
                diagnostic("course_data.sync.chat", ["session":session,"live":live,"windowStart":stamp(queryStart),"windowEnd":stamp(snapshot),"firstPage":firstPage,"pages":fetchedPages,"rows":fetchedRows,"kept":keptRows,"unassigned":excluded,"finished":done])
            }
            for _ in 0..<20 {
                let data=try await client.get("/live/v3/channel/chat/get-history-page",[
                    "startDay":CourseData.format(queryStart,pattern:"yyyy-MM-dd HH:mm:ss"),"endDay":CourseData.format(snapshot,pattern:"yyyy-MM-dd HH:mm:ss"),
                    "page":String(page),"pageSize":"1000","status":"pass","hasTotal":"N"])
                try valid()
                guard let object=data as? [String:Any], let rows=object["contents"] as? [[String:Any]] else { throw AppError.message("公聊记录暂不可用") }
                var records:[PublicChatRecord]=[]
                for row in rows {
                    guard CourseData.string(row["channelId"]) == initial.channel else { continue }
                    guard let record=CourseData.chat(row) else { continue }
                    guard record.sessionID == session else { if record.sessionID == nil { excluded += 1 }; continue }
                    guard record.time >= queryStart, record.time <= snapshot else { continue }
                    records.append(record)
                }
                let finished=rows.count < 1000
                fetchedPages += 1; fetchedRows += rows.count; keptRows += records.count; done=finished
                page += 1
                try updateCourseData(id) { c in
                    c.publicChat=CourseData.mergeChat(c.publicChat ?? [],records)
                    var a=c.analytics ?? CourseAnalytics(); a.chatUnassigned=excluded
                    a.chatNextPage=finished ? nil : page; a.chatSnapshotEnd=finished ? nil : snapshot; a.chatSnapshotStart=finished ? nil : queryStart
                    if finished { a.chatSyncedThrough=snapshot; a.chatSyncedFrom=queryStart }; c.analytics=a
                }
                if finished { break }
            }
            if saved.courses.first(where:{$0.id == id})?.analytics?.chatNextPage != nil { errors.append("公聊同步未完，下次继续") }
        } catch is CancellationError { return } catch { errors.append("公聊记录暂未更新"); diagnostic("course_data.sync.chat", ["session":session,"error":safe(error)], error: true) }
        do {
            try valid()
            try updateCourseData(id) { c in
                if c.analytics == nil { c.analytics=CourseAnalytics() }
                c.analytics?.syncError=errors.isEmpty ? nil : errors.joined(separator:"；")
            }
            dataErrors[id]=errors.isEmpty ? nil : errors.joined(separator:"；")
        } catch { dataErrors[id]="资料保存失败，请重试" }
    }
    /// Log-friendly local time for sync windows (no secrets: only times, counts and session ids go to the log).
    /// Error text for the log with any URL query (which would carry the request signature) cut off.
    private func safe(_ error: Error) -> String { error.localizedDescription.replacingOccurrences(of:#"\?\S*"#,with:"?…",options:.regularExpression) }
    private func stamp(_ date: Date?) -> String { date.map { CourseData.format($0,pattern:"yyyy-MM-dd HH:mm:ss") } ?? "-" }
    func cancelDataTasks() {
        statisticsPolling?.cancel(); statisticsPolling=nil
        dataSyncTasks.values.forEach { $0.cancel() }; dataSyncTasks=[:]
        finalDataSyncTasks.values.forEach { $0.cancel() }; finalDataSyncTasks=[:]
    }
}
