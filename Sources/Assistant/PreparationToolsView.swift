import SwiftUI
import AssistantCore

struct PreparationToolsBar: View {
    @ObservedObject var store: Store
    var stage: LessonAssetStage = .preparation
    private var tools: [PreparationShortcut] {
        (stage == .review ? Store.builtinReviewShortcuts : Store.builtinPreparationShortcuts) + store.saved.preparationShortcuts
    }
    var disabled: Bool
    var send: (String) -> Void
    var edit: (PreparationShortcut) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(tools) { tool in
                        Button(tool.name) { send(tool.prompt) }
                            .buttonStyle(PromptCapsuleStyle()).disabled(disabled).help(tool.prompt)
                    }
                    moreMenu   // grey 28×28 capsule right after the last chip
                }
            }
        }
    }
    private var moreMenu: some View {
            Menu {
                Button("新建工具", systemImage: "plus") { edit(.init(name: "", prompt: "")) }
                Divider()
                ForEach(tools) { tool in
                    Menu(tool.name) {
                        Button("使用") { send(tool.prompt) }.disabled(disabled)
                        if store.saved.preparationShortcuts.contains(where: { $0.id == tool.id }) {
                            Button("编辑") { edit(tool) }
                        } else {
                            Button("另存为工具") { edit(.init(name: tool.name, prompt: tool.prompt)) }
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28).background(Circle().fill(AppTheme.dyn(0x000000, 0xFFFFFF, 0.04, 0.06))).contentShape(Circle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("常用工具")
    }
}

struct PreparationShortcutEditor: View {
    @ObservedObject var store: Store
    @State var tool: PreparationShortcut
    @State private var error = ""
    @State private var confirmingDelete = false   // D7: 「删除」 asks first (取消 = Return / Esc)
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.saved.preparationShortcuts.contains { $0.id == tool.id } ? "编辑常用工具" : "新建常用工具").font(.system(size: 15, weight: .semibold))
            Text("名称").font(.system(size: 11))
            TextField("工具名称", text: $tool.name).textFieldStyle(FilledFieldStyle())
            Text("指令").font(.system(size: 11))
            TextEditor(text: $tool.prompt).font(.system(size: 13)).frame(height: 150)
                .scrollContentBackground(.hidden).padding(6).background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 8))
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            HStack {
                if store.saved.preparationShortcuts.contains(where: { $0.id == tool.id }) {
                    Button("删除", role: .destructive) { confirmingDelete = true }.buttonStyle(.plain).foregroundStyle(AppTheme.danger).font(.system(size: 13, weight: .medium))   // red text, left side, no Return
                }
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(ModernSecondaryButtonStyle(size: .regular)).keyboardShortcut(.cancelAction)
                let empty = tool.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tool.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button("保存") {
                    do { try store.savePreparationShortcut(tool); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(ModernPrimaryButtonStyle(size: .regular, disabledLook: empty))
                    .disabled(empty)
            }
        }.padding(22).frame(width: 380)
        .alert("删除“\(tool.name)”？", isPresented: $confirmingDelete) {
            Button("取消", role: .cancel) { confirmingDelete = false }.keyboardShortcut(.defaultAction)
            Button("删除", role: .destructive) {
                do { try store.deletePreparationShortcut(tool.id); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } message: { Text("这个常用工具会从列表中移除。删除后无法撤销。") }
        .background(AlertEscapeCancels(active: confirmingDelete) { confirmingDelete = false })
    }
}

struct ClassroomDirectoryRow: View {
    var title: String
    var subtitle: String? = nil
    var selected: Bool
    var room: Bool = false
    var expanded: Bool = false
    var status: String = "备课中"
    var canDelete: Bool
    var select: () -> Void
    var edit: () -> Void
    var rename: () -> Void
    var delete: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 8) {
                    if room { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(AppTheme.textSecondary).frame(width: 24) }
                    else { LessonStatusDot(phase: .init(status: status)) }
                    if room {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title).font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .lineLimit(1).minimumScaleFactor(0.8).frame(height: 16, alignment: .leading)
                            Text(subtitle ?? "").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1).frame(height: 15, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(title).font(.system(size: 13)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }.padding(.leading, 8).frame(maxWidth: .infinity).frame(height: room ? 56 : 32).contentShape(Rectangle())
            }.buttonStyle(.plain).focused($focused)
                .accessibilityValue(room ? (expanded ? "已展开" : "已折叠") : "")
                .help(room ? (expanded ? "折叠课程" : "展开课程") : title)
            Menu {
                Button(room ? "编辑教室" : "编辑课程", action: edit)
                Button("重命名", action: rename)
                Divider()
                Button(room ? "删除教室" : "删除课程", role: .destructive, action: delete).disabled(!canDelete)
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .opacity(hovered || focused ? 1 : 0)
                .help(room ? "教室操作" : "课程操作")
        }
        .foregroundStyle(selected ? AppTheme.accent : .primary)
        .background(selected ? AppTheme.accent.opacity(0.08) : hovered ? AppTheme.subtleFill : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
    }
}

/// P0-1 copy: names what goes (no 「资料」: that word means knowledge-base files, which stay) and says it can't be undone.
enum ClassroomDeleteCopy {
    static func message(lesson: Bool, lessonCount: Int) -> String {
        lesson ? "这节课的聊天、备课、课堂记录、文档和答题卡都会从这台电脑上删除，知识库里的资料不受影响。删除后无法撤销。"
               : "这个教室和其中 \(lessonCount) 节课的聊天、备课、课堂记录、文档和答题卡都会从这台电脑上删除，知识库里的资料不受影响。删除后无法撤销。"
    }
}

struct ClassroomItemRequest: Identifiable {
    enum Action { case edit, rename, delete }
    let id = UUID()
    var channel: String
    var lessonID: UUID?
    var title: String
    var action: Action
}

struct ClassroomItemEditor: View {
    @ObservedObject var store: Store
    var request: ClassroomItemRequest
    @State private var title: String
    @State private var libraryIDs: Set<UUID>
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    init(store: Store, request: ClassroomItemRequest) {
        self.store = store; self.request = request
        _title = State(initialValue: request.title)
        _libraryIDs = State(initialValue: Set(store.room(request.channel).libraryIDs))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.action == .rename ? "重命名" : request.lessonID == nil ? "编辑教室" : "编辑课程").font(.system(size: 15, weight: .semibold))
            Group {   // delete never reaches this sheet: it is the system alert in ClassroomSpaceView
                TextField("名称", text: $title).textFieldStyle(FilledFieldStyle())
                if request.action == .edit && request.lessonID == nil {
                    Text("频道 \(request.channel)").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                    Text("关联知识库").font(.system(size: 13, weight: .medium))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(store.saved.libraries) { library in
                                let on = libraryIDs.contains(library.id)
                                Button { if on { libraryIDs.remove(library.id) } else { libraryIDs.insert(library.id) } } label: {
                                    HStack(spacing: 8) {   // same row as the 开始上课 knowledge list
                                        DropdownCheckbox(on: on)
                                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(KnowledgeSpine.color(for: library.name)).frame(width: 4, height: 20)
                                        Text(library.name).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                                        Spacer(minLength: 4)
                                        Text("\(library.documents.count) 份资料").font(.system(size: 11).monospacedDigit()).foregroundStyle(AppTheme.textSecondary)
                                    }.padding(.horizontal, 6).frame(height: 32).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                .accessibilityAddTraits(.isToggle).accessibilityValue(on ? "已选中" : "未选中")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 160)
                }
            }
            if !error.isEmpty { Text(error).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            HStack {
                Spacer(); Button("取消") { dismiss() }.buttonStyle(ModernSecondaryButtonStyle(size: .regular)).keyboardShortcut(.cancelAction)
                Button("保存") {
                    do {
                        if request.action == .edit && request.lessonID == nil {
                            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty, trimmed.count <= 120 else { throw AppError.message("名称限1至120字") }
                            try store.commitRoom(request.channel) { room, _ in room.name = trimmed; room.libraryIDs = Array(libraryIDs) }
                        } else { try store.renameClassroomItem(channel: request.channel, lessonID: request.lessonID, title: title) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(ModernPrimaryButtonStyle(size: .regular))
            }
        }.padding(22).frame(width: 380)
    }
}
