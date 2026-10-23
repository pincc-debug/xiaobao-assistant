import SwiftUI
import AssistantCore

struct ClassroomCreateSheet: View {
    @ObservedObject var store: Store
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var channel = ""
    @State private var name = ""
    @State private var error = ""
    @State private var creating = false
    @State private var creationTask: Task<Void, Never>?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("新建教室").font(.system(size: 15, weight: .semibold))
            VStack(alignment:.leading,spacing:6) { Text("频道号").font(.system(size: 13, weight: .medium)); TextField("如 3187065",text:$channel).disabled(creating) }
            VStack(alignment:.leading,spacing:6) { Text("教室名称（可选）").font(.system(size: 13, weight: .medium)); TextField("如 编程入门教室",text:$name).disabled(creating) }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.stopRed) }
            HStack { Spacer(); if creating { ProgressView().controlSize(.small) }; Button("取消") { creationTask?.cancel(); dismiss() }.buttonStyle(ModernSecondaryButtonStyle(size: .regular)).keyboardShortcut(.cancelAction); Button("创建") {
                creating = true; error = ""
                creationTask = Task {
                    defer { creating = false }
                    do { let channel=try await store.createClassroom(channel,name:name); onCreate(channel); dismiss() }
                    catch { if !Task.isCancelled { self.error=error.localizedDescription } }
                }
            }.buttonStyle(ModernPrimaryButtonStyle(size: .regular, disabledLook: creating || channel.trimmingCharacters(in:.whitespaces).isEmpty)).keyboardShortcut(.defaultAction).disabled(creating || channel.trimmingCharacters(in:.whitespaces).isEmpty)
            }
        }.textFieldStyle(FilledFieldStyle()).padding(22).frame(width:380)
            .onDisappear { creationTask?.cancel() }
    }
}
struct PreparationEditor: View {
    @ObservedObject var store: Store
    var channel: String
    @State var plan: LessonPreparation
    @Environment(\.dismiss) private var dismiss
    @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("备课").font(.system(size: 15, weight: .semibold))
            // Every field has a 13pt medium label 6 above it (consistency spec 6).
            VStack(alignment:.leading,spacing:6) { Text("课程名称").font(.system(size: 13, weight: .medium)); TextField("课程名称",text:$plan.title) }
            HStack(spacing:12) {
                VStack(alignment:.leading,spacing:6) { Text("面向").font(.system(size: 13, weight: .medium)); TextField("面向学员",text:$plan.audience) }
                VStack(alignment:.leading,spacing:6) { Text("目标").font(.system(size: 13, weight: .medium)); TextField("课程目标",text:$plan.goals) }
            }
            VStack(alignment:.leading,spacing:6) {
                Text("备课内容").font(.system(size: 13, weight: .medium))
                TextEditor(text:$plan.notes).accessibilityLabel("备课内容").font(.system(size:13)).scrollContentBackground(.hidden).padding(8)
                    .background(AppTheme.inputFill,in:RoundedRectangle(cornerRadius:8)).frame(height:140)
            }
            HStack { Text("课程资料").font(.system(size: 13, weight: .medium)); Spacer(); Button("上传资料") {
                do { plan.documents += try store.importPreparationDocuments() } catch { self.error=error.localizedDescription }
            }.buttonStyle(QuietFillButtonStyle()) }
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    ForEach(plan.documents) { document in HStack { Text(document.name).lineLimit(1); Spacer(); Button { plan.documents.removeAll { $0.id == document.id } } label: { Image(systemName:"minus.circle").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).frame(width: 28, height: 28) }.buttonStyle(HoverCircleButtonStyle()).help("移除此资料") } }
                }
            }.frame(height:60)
            DisclosureGroup("参考知识库") {
                ScrollView {
                    ForEach(store.saved.libraries) { library in
                        Toggle(library.name,isOn:Binding(get:{ plan.libraryIDs.contains(library.id) },set:{ on in
                            plan.libraryIDs.removeAll { $0 == library.id }; if on { plan.libraryIDs.append(library.id) }
                        })).toggleStyle(.checkbox)
                    }
                }.frame(maxHeight:100)
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.stopRed) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(ModernSecondaryButtonStyle(size: .regular)).keyboardShortcut(.cancelAction)
                Button("保存草稿") { save(confirm:false) }.buttonStyle(ModernSecondaryButtonStyle(size: .regular))
                Button("确认备课") { save(confirm:true) }.buttonStyle(ModernPrimaryButtonStyle(size: .regular))
            }
        }.textFieldStyle(FilledFieldStyle()).padding(22).frame(width:620,height:680)
    }
    private func save(confirm:Bool) {
        do { try store.savePreparation(plan,channel:channel,confirm:confirm); dismiss() }
        catch { self.error=error.localizedDescription }
    }
}
struct PreparationPanel: View {
    @ObservedObject var store: Store
    var channel: String
    var lessonID: UUID?
    var onSelect: (UUID) -> Void
    @State private var editing: LessonPreparation?
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            if let lessonID, let plan=store.preparationForLesson(lessonID,channel:channel) {
                HStack { Text(plan.usedByCourseID != nil ? "本场备课" : LessonAssetStage.preparation.statusTitle).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary); Spacer()
                    if plan.usedByCourseID == nil { Button("编辑") { editing=plan }.buttonStyle(QuietFillButtonStyle()) }
                }
                Text(plan.title).font(.system(size: 15, weight: .semibold))
                if !plan.audience.isEmpty { Text("面向：" + plan.audience).font(.system(size: 13)) }
                if !plan.goals.isEmpty { Text("目标：" + plan.goals).font(.system(size: 13)) }
                if !plan.notes.isEmpty { ChatMarkdown(text: plan.notes) }
                ForEach(plan.documents) { document in
                    DisclosureGroup(document.name) { Text(document.text).font(.system(size: 13)).textSelection(.enabled) }.font(.system(size: 13))
                }
                if plan.ready { Button("用于上课") { store.usePreparationToStart(plan.id,channel:channel) }.buttonStyle(ModernPrimaryButtonStyle(size: .small)) }
                if plan.confirmedAt != nil {
                    SaveToKnowledgeDropdown(store: store, saved: false) { store.savePreparationToKnowledge(plan.id,channel:channel,libraryID:$0) }
                    if store.preparationIsSaved(plan.id,channel:channel) {
                        Label("已存入知识库",systemImage:"checkmark.circle").font(.system(size: 11)).foregroundStyle(AppTheme.success)
                    }
                }
            } else {
                Text("本节课未备课").foregroundStyle(AppTheme.textSecondary).font(.system(size:13))
            }
        }.sheet(item:$editing) { value in PreparationEditor(store:store,channel:channel,plan:value) }
    }
}
