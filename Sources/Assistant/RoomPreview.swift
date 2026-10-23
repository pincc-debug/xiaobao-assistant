import Foundation
import AssistantCore

extension Store {
    /// Deterministic, isolated UI fixture. Never installed in a normal app session.
    func prepareRoomPreview() {
        guard previewMode, let course = saved.courses.first else { return }
        var second = CourseSession(title: "数据结构入门", channel: "789012")
        second.transcript = "数组存储有序元素。"; second.ended = Date()
        saved.courses.append(second)
        roomAgentOverride = { input in
            let context = input as? [String:Any] ?? [:]
            let results = context["results"] as? [[String:Any]] ?? []
            if results.isEmpty { return ["name":"list_courses","arguments":[:]] }
            if results.count == 1 { return ["name":"read_course","arguments":["course_id":course.id.uuidString,"offset":0]] }
            if results.count == 2 {
                return ["name":"create_material", "arguments":["title":"变量与函数 · 课堂复盘", "kind":"资料", "text":"本场重点\n变量用于存储数据，函数用于封装可复用的操作。\n\n值得跟进\n学员问到变量的用途，可以增加一个变量存取的操作练习。\n\n下次尝试\n先让学员用变量记录一个数值，再将重复操作写成函数。", "source_ids":["\(course.id):0"]]]
            }
            return ["message":"本场讲解了变量与函数的基本用途，学员提问集中在变量的作用。建议下次增加变量存取和函数调用的练习。\n\n复盘资料已整理好，可以查看并存入知识库。"]
        }
    }
}

extension Store {
    func prepareDataPreview() {
        guard previewMode, let index=courseIndex else { return }
        let now=Date()
        var a=CourseAnalytics()
        a.points=(0..<42).filter { !(20...24).contains($0) }.map { n in
            ViewerPoint(time:now.addingTimeInterval(Double(n-42)*60),count:32+Int(18*sin(Double(n)/6))+n,source:"历史")
        }
        a.points += (0..<6).map { ViewerPoint(time:now.addingTimeInterval(Double($0-5)*10),count:68+$0,source:"实时") }
        var metrics=CourseMetrics(); metrics.viewers=126; metrics.views=184; metrics.peak=92; metrics.averageMinutes=23; metrics.totalMinutes=2898
        a.metrics=metrics; a.lastRealtimeAt=now; a.chatSyncedThrough=now; a.firstCollectedAt=now.addingTimeInterval(-42*60)
        saved.courses[index].analytics=a
        saved.courses[index].publicChat=(0..<24).map { n in
            PublicChatRecord(id:"preview-message-\(n)",userID:"preview-user-\(n%8)",name:["小周","小林","小陈","小许"][n%4],role:"student",time:now.addingTimeInterval(Double(n-24)*90),text:n%3 == 0 ? "函数和变量有什么区别？" : "这个例子我理解了。",sessionID:"preview-session")
        }
        saved.courses[index].transcriptSegments=[TranscriptSegment(text:"变量用于保存数据，函数用来封装重复的操作。")]
    }
}

extension Store {
    func preparePreparationPreview() {
        guard previewMode else { return }
        saved.rooms=[]; saved.courses=[]; currentCourseID=nil; messages=[]; demo=false; channel=""; selectedPreparationID=nil
        let library=KnowledgeBase(name:"公共课程资料",documents:[Document(name:"学习须知",text:"课后提供复习资料。")])
        saved.libraries=[library]; libraryIDs=[library.id]
    }
}

extension Store {
    func prepareToolsPreview() {
        guard previewMode else { return }
        preparePreparationPreview()
        do {
            let id = try createPreparation(channel: "3187065", title: "变量与函数")
            try commitRoom("3187065") { room, _ in
                room.name = "编程入门教室"
                room.messages = [RoomMessage(role: "user", text: "请按知识点、案例、练习三个部分整理本课。", lessonID: id),
                                 RoomMessage(role: "assistant", text: "先认识变量与赋值，再用订单计算案例理解函数，最后通过课堂练习巩固。", lessonID: id)]
                var process = RoomThinking(id: UUID(), messageID: room.messages[0].id)
                process.started = Date().addingTimeInterval(-8); process.finished = Date(); process.status = "已完成"
                process.steps = [.init(title: "查阅课程资料", detail: "先查看本课已有内容。"),
                                 .init(title: "整理教学顺序", detail: "按知识点、案例、练习组织内容。")]
                room.messages[0].thinking = process
            }
            _ = try createPreparation(channel: "8575413", title: "未命名教室的课程")
            roomAgentOverride = { _ in ["message": "可以围绕变量与函数设计知识点讲解、案例和课堂练习。"] }
        } catch { self.error = error.localizedDescription }
    }
}
