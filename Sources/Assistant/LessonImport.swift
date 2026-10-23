import Foundation
import AssistantCore

struct LessonImport: Codable {
    var id: UUID
    var name: String
    var documents: [Document]
    var enableTestCapabilities: Bool?
}
extension Store {
    func importLesson(_ url: URL) {
        guard !connected, !busy else { error = "请结束本场后再导入课程资料"; return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 2_000_000 else { throw AppError.message("课程资料过大") }
            let lesson = try JSONDecoder().decode(LessonImport.self, from: data)
            guard !lesson.name.isEmpty, !lesson.documents.isEmpty, lesson.documents.count <= 30 else { throw AppError.message("课程资料格式无效") }
            let library = KnowledgeBase(id: lesson.id, name: lesson.name, documents: lesson.documents)
            if let i = saved.libraries.firstIndex(where: { $0.id == lesson.id }) { saved.libraries[i] = library }
            else { saved.libraries.append(library) }
            libraryIDs.insert(lesson.id)
            if lesson.enableTestCapabilities == true {
                for c in [AssistantCapability.knowledgeAnswers, .riskAlerts, .messageDigest, .welcomeRecap, .quoteCards, .courseArchive] { saved.capabilities.set(c, enabled: true) }
                for output in ArchiveOutput.allCases where output != .faqToKnowledge { saved.capabilities.set(output, enabled: true) }
            }
            persist(); flow("课程资料已导入", detail: lesson.name); settingsPage = "知识库"
        } catch { self.error = "导入失败：" + error.localizedDescription }
    }
}
