import SwiftUI
import AssistantCore

struct CourseSettingsView: View {
    @ObservedObject var store: Store
    @State private var followsOutput = true
    @State private var validatingLesson = false
    @State private var lessonCreationTask: Task<Void, Never>?
    @State private var channel: String?
    @State private var collapsedChannels: Set<String> = []
    @State private var search = ""
    @State private var selectedLessonID: UUID?
    @State private var creatingRoom = false
    @State private var editingShortcut: PreparationShortcut?
    @State private var hoveredMessage: UUID?
    @State private var itemRequest: ClassroomItemRequest?
    @State private var deleteRequest: ClassroomItemRequest?
    private var activeLessonID: UUID? {
        guard let channel, let selectedLessonID else { return nil }
        return store.preparations(channel).first(where: { $0.id == selectedLessonID })?.usedByCourseID ?? selectedLessonID
    }
    @State private var drafts: [String: String] = [:]
    @State private var application: String?
    @State private var assetFocusStage: LessonAssetStage?
    @State private var assetFocusRequest = UUID()
    @State private var reshapeMode: ReshapeMode = .assets
    @State private var history: CourseSession?
    @State private var showHistory = false
    @State private var showLibraries = DropdownPreview.isOpen("classroom-libs")
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let apps = [("课程产出", "square.stack"), ("数据", "chart.xyaxis.line")]
    /// The classroom whose course list is open; 「新建课程」 adds there.
    private var expandedChannel: String? { channel.flatMap { collapsedChannels.contains($0) ? nil : $0 } }
    private var channels: [String] { store.classroomChannels.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || store.classroomTitle($0).localizedCaseInsensitiveContains(search) || store.classroomLessons($0).contains { $0.title.localizedCaseInsensitiveContains(search) } } }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                channelList.frame(width: 190)
                Rectangle().fill(AppTheme.columnLine).frame(width: 0.5)
                if let channel {
                    ZStack(alignment: .trailing) {
                        chat(channel).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.trailing, application != nil && geometry.size.width >= 900 ? 360 : 0)
                        if let application {
                            toolPanel(application, channel: channel)
                                .frame(width: min(360, max(280, geometry.size.width - 246)))
                                .background(AppTheme.pageBackground)
                                .overlay(alignment: .leading) { Rectangle().fill(AppTheme.columnLine).frame(width: 0.5) }   // divider, no drawer shadow
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                                .background(EscapeKeyCatcher { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { self.application = nil } })
                        }
                    }.clipped()
                    Rectangle().fill(AppTheme.columnLine).frame(width: 0.5)
                    VStack(spacing: 10) {
                        ForEach(apps, id: \.0) { item in
                            Button { if item.0 == "课程产出" { assetFocusStage=nil; assetFocusRequest=UUID(); reshapeMode = .assets }; if item.0 == "数据" { reshapeMode = .analysis }; withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { application = application == item.0 ? nil : item.0 } } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: item.1).font(.system(size: 15))
                                    Text(item.0).font(.system(size: 11))
                                }.foregroundStyle(application == item.0 ? AppTheme.accent : .secondary)
                                    .frame(width: 50, height: 54)   // +4pt so 「课程产出」 clears the selection fill
                                    .background(application == item.0 ? AppTheme.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).help(application == item.0 ? "收起\(item.0)" : item.0)   // no × on the panel: the rail icon closes it
                        }
                        Spacer()
                    }.padding(.horizontal, 5).padding(.top, 55).background(AppTheme.pageBackground)
                } else {
                    ContentUnavailableView("暂无教室", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { if CommandLine.arguments.contains("--preview-history") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showHistory = true } }   // dev screenshots
            if showLibraries { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showLibraries = true } }   // dev screenshots: survive the initial channel pick
            if channel == nil { channel = channels.first }; if selectedLessonID == nil, let channel { selectedLessonID=store.classroomLessons(channel).first?.id }
            consumeCourseListRequest()
        }
        .onChange(of: store.courseListRequest) { _, _ in consumeCourseListRequest() }
        .onChange(of: store.classroomChannels) { _, values in if channel == nil || !values.contains(channel!) { channel = values.first } }
        .onChange(of: activeLessonID) { _,_ in assetFocusStage=nil; assetFocusRequest=UUID() }
        .onChange(of: channel) { _, value in history = nil; showLibraries = false; selectedLessonID=value.flatMap { store.classroomLessons($0).first?.id } }
        .sheet(item: $editingShortcut) { tool in PreparationShortcutEditor(store: store, tool: tool) }
        .sheet(item: $itemRequest) { request in
            if request.action == .edit, let id = request.lessonID,
               let plan = store.preparations(request.channel).first(where: { $0.id == id && $0.usedByCourseID == nil }) {
                PreparationEditor(store: store, channel: request.channel, plan: plan)
            } else {
                ClassroomItemEditor(store: store, request: request)   // edit / rename only; delete goes through the system alert
            }
        }
        .alert(deleteRequest.map { "删除“\($0.title)”？" } ?? "", isPresented: Binding(get: { deleteRequest != nil }, set: { if !$0 { deleteRequest = nil } }), presenting: deleteRequest) { request in
            Button("取消", role: .cancel) { deleteRequest = nil }.keyboardShortcut(.defaultAction)   // D1: Return cancels, never deletes
            Button("删除", role: .destructive) { confirmDelete(request) }
        } message: { request in Text(ClassroomDeleteCopy.message(lesson: request.lessonID != nil, lessonCount: store.classroomLessons(request.channel).count)) }
        .background(AlertEscapeCancels(active: deleteRequest != nil) { deleteRequest = nil })
        .sheet(isPresented: $creatingRoom) {
            ClassroomCreateSheet(store:store) { value in
                channel = value
                collapsedChannels.remove(value)
                selectedLessonID = store.classroomLessons(value).first?.id
            }
        }
        .sheet(item: $history) { course in
            VStack(spacing: 0) {
                HStack { Text("课程记录").font(.system(size: 15, weight: .semibold)); Spacer(); Button("完成") { history = nil }.buttonStyle(.plain).foregroundStyle(AppTheme.accent).font(.system(size: 13, weight: .medium)) }.padding()
                Color.clear.frame(height: 4)
                CourseHistoryView(channelFilter: course.channel, initialCourseID: course.id, store: store)
            }.frame(width: 900, height: 650)
        }
        .sheet(isPresented: $showHistory) {
            VStack(spacing: 0) {
                HStack { Text("课程记录").font(.system(size: 15, weight: .semibold)); Spacer(); Button("完成") { showHistory = false }.buttonStyle(.plain).foregroundStyle(AppTheme.accent).font(.system(size: 13, weight: .medium)) }.padding()
                Color.clear.frame(height: 4)
                CourseHistoryView(channelFilter: channel, store: store)
            }.frame(width: 900, height: 650)
        }
    }
    private var channelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("教室").font(.system(size:20,weight:.semibold)); Spacer()
                Button { creatingRoom=true } label: { Image(systemName:"plus").frame(width:28,height:28) }.buttonStyle(.plain).help("新建教室")
            }.padding(.top,40).padding(.bottom,16)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(AppTheme.textSecondary)
                TextField("搜索教室", text: $search).textFieldStyle(.plain)
            }.font(.system(size: 13)).padding(.horizontal, 10).frame(height: 30).background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(channels, id: \.self) { value in
                        ClassroomDirectoryRow(title: value, subtitle: store.room(value).name, selected: channel == value, room: true, expanded: channel == value && !collapsedChannels.contains(value),
                            canDelete: store.canDeleteClassroomItem(channel: value, lessonID: nil),
                            select: {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                                    if channel == value {
                                        if collapsedChannels.contains(value) { collapsedChannels.remove(value) }
                                        else { collapsedChannels.insert(value) }
                                    } else {
                                        collapsedChannels.remove(value)
                                        channel = value
                                    }
                                }
                            },
                            edit: { requestItem(.edit, channel: value) },
                            rename: { requestItem(.rename, channel: value) },
                            delete: { requestItem(.delete, channel: value) })
                        if channel == value && !collapsedChannels.contains(value) {
                            VStack(alignment:.leading,spacing:3) {
                                ForEach(store.classroomLessons(value)) { lesson in
                                    ClassroomDirectoryRow(title: lesson.title, selected: activeLessonID == lesson.id, status: lesson.status,
                                        canDelete: store.canDeleteClassroomItem(channel: value, lessonID: lesson.id),
                                        select: { selectedLessonID = lesson.id },
                                        edit: { requestItem(.edit, channel: value, lessonID: lesson.id) },
                                        rename: { requestItem(.rename, channel: value, lessonID: lesson.id) },
                                        delete: { requestItem(.delete, channel: value, lessonID: lesson.id) })
                                }
                                if store.room(value).messages.contains(where:{$0.lessonID == nil}) {
                                    Button("历史讨论") { selectedLessonID=nil }.font(.system(size:11)).buttonStyle(.plain).padding(8)
                                }
                            }.padding(.leading,12)
                        }
                    }
                    if channels.isEmpty && !search.isEmpty { Text("未找到教室").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary).padding(.top, 20) }
                }
            }
            // Fixed under the list (doesn't scroll); same 40pt / r10 / 12pt bottom inset as the sidebar appearance strip.
            NewLessonDashedButton(available: expandedChannel != nil, busy: validatingLesson) { if let expandedChannel { createLesson(in: expandedChannel) } }
                .padding(.top, 8).padding(.bottom, 12)
        }.padding(.horizontal, 10).background(AppTheme.pageBackground)
    }
    private func chat(_ channel: String) -> some View {
        let room = store.lessonConversation(channel,lessonID:activeLessonID)
        let busy = store.roomProgress[channel] != nil
        let canChat = activeLessonID != nil || !room.messages.isEmpty
        let stage = store.lessonAssetStage(channel: channel, lessonID: activeLessonID)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.classroomLessons(channel).first(where:{$0.id == activeLessonID})?.title ?? store.classroomTitle(channel)).font(.system(size: 15,weight:.semibold)).lineLimit(1)
                    Text(store.classroomLessons(channel).isEmpty ? "频道 \(channel)" : store.classroomTitle(channel) + " · " + (activeLessonID == nil ? "历史讨论" : store.lessonAssetStage(channel:channel,lessonID:activeLessonID).statusTitle)).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                if let lessonID = activeLessonID {
                    BroadcastLaunchMenu(store: store, channel: channel, lessonID: lessonID)
                }
                Button { showHistory=true } label: { Image(systemName:"clock.arrow.circlepath").frame(width:30,height:30) }.buttonStyle(.plain).help("课程记录管理")
                Button { DropdownGate.toggle($showLibraries) } label: { Image(systemName: "books.vertical").frame(width: 30, height: 30) }
                    .buttonStyle(.plain).help("关联知识库").accessibilityLabel("关联知识库")
                    .background(DropdownPanelAnchor(isPresented: $showLibraries, width: 260, header: "关联知识库（可多选）", empty: "暂无知识库", items: libraryItems(channel)))
            }.padding(.horizontal, 22).padding(.top, 38).padding(.bottom, 15)
            if !canChat { Spacer(minLength: 0) }   // empty classroom: the guide is centred over the whole column (overlay below)
            else {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if room.messages.isEmpty {
                            VStack(spacing: 12) {
                                ClassroomGuideIllustration(newLesson: activeLessonID == nil)
                                Text(activeLessonID == nil ? "这个教室还没有课" : "和\(store.saved.preferences.nickname)聊聊这节课").font(.system(size: 15, weight: .medium))
                                if activeLessonID == nil { Text("点左侧「新建课程」开始备课").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary) }

                            }.frame(maxWidth: .infinity).padding(.top, 36)
                        }
                        ForEach(room.messages) { message in
                            messageRow(message,channel:channel).id(message.id)
                            if let process = store.roomThinking[channel], process.messageID == message.id {
                                RoomThinkingView(process: process).id(process.id)
                            } else if let process = message.thinking {
                                RoomThinkingView(process: process).id(process.id)
                            }
                            ForEach(room.materials.filter { $0.exercise == nil && (message.assetIDs ?? []).contains($0.id) }) { asset in assetCard(asset) }
                        }
                        if let material=room.materials.last, material.exercise == nil, !room.messages.contains(where:{ ($0.assetIDs ?? []).contains(material.id) }) { assetCard(material) }
                        Color.clear.frame(height: 1).id("bottom")
                            .background(GeometryReader { geometry in Color.clear.preference(key: ChatScrollMetrics.self, value: ["bottom": geometry.frame(in: .named("classroom-chat-scroll")).maxY]) })
                    }.padding(22)
                }
                .coordinateSpace(name: "classroom-chat-scroll")
                .background(GeometryReader { geometry in Color.clear.preference(key: ChatScrollMetrics.self, value: ["height": geometry.size.height]) })
                .onPreferenceChange(ChatScrollMetrics.self) { metrics in
                    if let bottom = metrics["bottom"], let height = metrics["height"] { followsOutput = bottom <= height + 70 }
                }
                .onChange(of: room.messages.count) { _, _ in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { reader.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: store.roomStreamingText[channel]) { _, _ in if followsOutput, store.roomRunLesson[channel] == activeLessonID { reader.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: activeLessonID) { _, _ in reader.scrollTo("bottom", anchor: .bottom) }
                .onAppear { reader.scrollTo("bottom", anchor: .bottom) }
            }
            }
            if let error = store.roomErrors[channel] {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 13)).foregroundStyle(AppTheme.danger).textSelection(.enabled)
                    Spacer()
                    if room.messages.last?.role == "user" && !busy { Button("重试") { store.retryRoomAgent(channel, lessonID: activeLessonID) }.controlSize(.small) }
                }.padding(.horizontal, 18).padding(.vertical, 8)
            }
            if canChat && stage != .classroom {
                PreparationToolsBar(store: store, stage: stage, disabled: busy || !canChat,
                    send: { _ = store.sendRoomMessage($0, channel: channel, lessonID: activeLessonID) },
                    edit: { editingShortcut = $0 })
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if canChat {   // no course yet (「这个教室还没有课」): nothing to talk about, so no input box
            VStack(spacing: 8) {
                TextField("发消息，或交给助教一个任务", text: Binding(get: { drafts[channel + (activeLessonID?.uuidString ?? "legacy")] ?? "" }, set: { drafts[channel + (activeLessonID?.uuidString ?? "legacy")] = $0 }), axis: .vertical)
                    .lineLimit(3...6).textFieldStyle(.plain).font(.system(size: 13)).onSubmit { send(channel) }.disabled(!canChat)
                HStack {
                    Spacer()
                    if busy { Button { store.stopRoomAgent(channel) } label: { Image(systemName: "stop.fill").foregroundStyle(AppTheme.stopRed) }.buttonStyle(SendButtonStyle(stop: true)).help("停止").accessibilityLabel("停止") }
                    else { Button("发送", systemImage: "arrow.up") { send(channel) }.buttonStyle(SendButtonStyle()).disabled(!canChat || (drafts[channel + (activeLessonID?.uuidString ?? "legacy")] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
            }
            .padding(14)
            .background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.cardBorder, lineWidth: 1))
            .padding([.horizontal, .bottom], 16)   // floating input card, no full-width strip
            }
        }
        .overlay {
            if !canChat {
                VStack(spacing: 12) {
                    ClassroomGuideIllustration(newLesson: true)
                    Text("这个教室还没有课").font(.system(size: 15, weight: .medium))
                    Text("点左侧「新建课程」开始备课").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary)
                }.allowsHitTesting(false)
            }
        }
        .background(AppTheme.pageBackground)
    }
    private func requestItem(_ action: ClassroomItemRequest.Action, channel: String, lessonID: UUID? = nil) {
        let title = lessonID.flatMap { id in store.classroomLessons(channel).first { $0.id == id }?.title } ?? store.classroomTitle(channel)
        if action == .delete { deleteRequest = .init(channel: channel, lessonID: lessonID, title: title, action: action) }
        else { itemRequest = .init(channel: channel, lessonID: lessonID, title: title, action: action) }
    }
    /// Same store call and follow-up as the former delete sheet; a failure shows in the classroom error line.
    private func confirmDelete(_ request: ClassroomItemRequest) {
        deleteRequest = nil
        do {
            try store.deleteClassroomItem(channel: request.channel, lessonID: request.lessonID)
            if request.lessonID == nil { channel = store.classroomChannels.first }
            selectedLessonID = channel.flatMap { store.classroomLessons($0).first?.id }
            application = nil
        } catch { store.roomErrors[request.channel] = error.localizedDescription }
    }
    private func createLesson(in targetChannel: String) {
        guard !validatingLesson else { return }
        validatingLesson = true
        store.roomErrors[targetChannel] = nil
        lessonCreationTask = Task {
            defer { validatingLesson = false }
            do {
                let id = try await store.createValidatedPreparation(channel: targetChannel, title: "新建课程")
                if channel == targetChannel { selectedLessonID = id; application = nil }
            } catch {
                if !Task.isCancelled { store.roomErrors[targetChannel] = error.localizedDescription }
            }
        }
    }
    private func consumeCourseListRequest() {
        guard store.courseListRequest != nil else { return }
        store.courseListRequest = nil
        search = ""; application = nil
        collapsedChannels.removeAll()
    }
    private func send(_ channel: String) { if store.sendRoomMessage(drafts[channel + (activeLessonID?.uuidString ?? "legacy")] ?? "", channel: channel, lessonID: activeLessonID) { drafts[channel + (activeLessonID?.uuidString ?? "legacy")] = "" } }
    private func assetCard(_ material: RoomMaterial) -> some View {
        Button { assetFocusStage=material.stage ?? .review; assetFocusRequest=UUID(); application="课程产出" } label: {
            HStack(spacing:10) {
                Image(systemName:material.exercise == nil ? "doc.text" : "checklist")
                VStack(alignment:.leading,spacing:4) {
                    Text(material.title).font(.system(size:13,weight:.medium))
                    Text((material.stage ?? .review).rawValue + " · " + (material.exercise == nil ? "文档" : "答题卡")).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
                Spacer(); Image(systemName:"chevron.right").font(.system(size: 11))
            }.padding(12).background(AppTheme.cardFill,in:RoundedRectangle(cornerRadius:12))
        }.buttonStyle(.plain)
    }
    private func messageRow(_ message: RoomMessage, channel: String) -> some View {
        let mine = message.role == "user"
        return HStack(alignment: .top, spacing: 9) {
            if mine { Spacer(minLength: 36) }
            if !mine { Image(systemName: "sparkles").foregroundStyle(AppTheme.accent).frame(width: 28, height: 28).background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8)) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(mine ? "我" : store.saved.preferences.nickname)
                    Text(message.date.formatted(date: .omitted, time: .shortened))
                    if mine {
                        Button {
                            editingShortcut = PreparationShortcut(name: String(message.text.prefix(10)), prompt: message.text)
                        } label: { Image(systemName: "star").frame(width: 24, height: 22) }
                        .buttonStyle(.plain).help("存为常用工具").opacity(hoveredMessage == message.id ? 1 : 0)
                    }
                }.font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                Group {
                    if mine { Text(message.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled) }
                    else { ChatMarkdown(text: message.text) }
                }.padding(12).background(mine ? AppTheme.accent.opacity(0.1) : AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12))
                if !message.sources.isEmpty {
                    DisclosureGroup("查阅来源 · \(message.sources.count)") {
                        ForEach(message.sources) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).fontWeight(.medium)
                                Text(source.text).lineLimit(6).textSelection(.enabled)
                                if let id = source.courseID, let course = store.roomCourses(channel).first(where: { $0.id == id }) {
                                    Button("查看课程") { history = course }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }
                    }.font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                }
            }
            if !mine { Spacer(minLength: 20) }
        }
        .onHover { hoveredMessage = $0 ? message.id : nil }
        .contextMenu {
            if mine {
                Button("存为常用工具", systemImage: "star") {
                    editingShortcut = PreparationShortcut(name: String(message.text.prefix(10)), prompt: message.text)
                }
            }
        }
    }
    private func libraryItems(_ channel: String) -> [DropdownItem] {
        store.saved.libraries.map { library in
            DropdownItem(id: library.id.uuidString, title: library.name, detail: "\(library.documents.count) 份资料", spine: KnowledgeSpine.color(for: library.name),
                         selected: store.room(channel).libraryIDs.contains(library.id), kind: .checkbox) {
                var ids = store.room(channel).libraryIDs
                let enabled = !ids.contains(library.id)
                ids.removeAll { $0 == library.id }; if enabled { ids.append(library.id) }
                store.setRoomLibraries(ids, channel: channel)
            }
        }
    }
    private func toolPanel(_ app: String, channel: String) -> some View {
        if app == "课程产出" || app == "数据" {
            return AnyView(reshapeWorkbench(channel: channel).padding(.top, 28))
        }
        return AnyView(legacyToolPanel(app, channel: channel))
    }
    private func reshapeWorkbench(channel: String) -> some View {
        CourseWorkbenchPanel(
            store: store,
            channel: channel,
            lessonID: activeLessonID,
            focusStage: assetFocusStage,
            focusRequest: assetFocusRequest,
            onSelectLesson: { selectedLessonID = $0 },
            onCopyCourse: {
                guard let lessonID = activeLessonID else { return }
                do {
                    let source = store.preparationForLesson(lessonID, channel: channel)
                        ?? LessonPreparation(title: store.roomCourses(channel).first(where: { $0.id == lessonID })?.title ?? "新建课程")
                    selectedLessonID = try store.copyPreparation(source, channel: channel)
                } catch { store.roomErrors[channel] = error.localizedDescription }
            },
            mode: Binding(
                get: { reshapeMode },
                set: { new in
                    reshapeMode = new
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.14)) {
                        application = new == .assets ? "课程产出" : "数据"
                    }
                }
            )
        )
    }
    private func legacyToolPanel(_ app: String, channel: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(app).font(.system(size: 15, weight: .semibold)); Spacer()
            }.frame(height: 28).padding(.horizontal, 16).padding(.top, 40).padding(.bottom, 14)   // no ×: close via the rail icon or Esc; 14pt to the content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if app == "课程" {
                        HStack { Text("\(store.roomCourses(channel).count) 场课程").foregroundStyle(AppTheme.textSecondary); Spacer(); Button("管理") { showHistory = true } }.font(.system(size: 11))
                        ForEach(store.roomCourses(channel)) { course in
                            Button { history = course } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(course.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(course.started.formatted(date: .abbreviated, time: .shortened) + (course.startTimeVerified == true ? "" : " · 接入时间")).font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                                    Text("\(course.answers.count) 条问答 · \((course.exercises ?? []).count) 道题").font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }.buttonStyle(.plain)
                            Button("复盘这场课") { selectedLessonID=course.id; _ = store.sendRoomMessage("请复盘课程「\(course.title)」，课程ID：\(course.id.uuidString)，并生成复盘资料。", channel: channel, lessonID: course.id); application = nil }.font(.system(size: 11)).disabled(store.roomProgress[channel] != nil)
                        }
                    } else {
                        let materials = store.lessonConversation(channel,lessonID:activeLessonID).materials.filter { app == "资料" || $0.kind == "题目" }
                        ForEach(materials.reversed()) { material in materialView(material, channel: channel) }
                        if app == "题目" {
                            ForEach(store.roomCourses(channel).filter { (activeLessonID == nil || $0.id == activeLessonID) && !($0.exercises ?? []).isEmpty }) { course in
                                DisclosureGroup(course.title) { ExerciseList(store: store, course: course, canSend: false) }.font(.system(size: 13))
                            }
                        }
                        if materials.isEmpty && (app == "资料" || store.roomCourses(channel).allSatisfy({ ($0.exercises ?? []).isEmpty })) {
                            Text(app == "题目" ? "暂无题目" : "暂无课程产出").font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).padding(.top, 20)
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)   // the title row already gives the 14pt top gap
            }
        }
    }
    private func materialView(_ material: RoomMaterial, channel: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(material.title).font(.system(size: 13, weight: .semibold))
            Text(material.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
            DisclosureGroup("来源 · \(material.sources.count)") {
                ForEach(material.sources) { source in
                    VStack(alignment: .leading, spacing: 5) { Text(source.title).fontWeight(.medium); Text(source.text).textSelection(.enabled) }.padding(.vertical, 5)
                }
            }.font(.system(size: 11)).foregroundStyle(AppTheme.textSecondary)
            if store.roomMaterialSaved(material) { Label("已存入知识库", systemImage: "checkmark.circle").font(.system(size: 11)).foregroundStyle(AppTheme.success) }
            else {
                SaveToKnowledgeDropdown(store: store, saved: false) { store.saveRoomMaterial(material.id, channel: channel, libraryID: $0) }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ChatScrollMetrics: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}


/// Bottom of the classroom column, level with the sidebar appearance strip (40 high, r10, 12pt above the bottom).
/// Greyed (not hidden) when no classroom is open; the tooltip says why.
struct NewLessonDashedButton: View {
    var available: Bool
    var busy: Bool
    var action: () -> Void
    var body: some View {
        DashedAddButton(title: "新建课程", available: available, busy: busy,
                        help: available ? "在当前教室新建一节课" : "先选一个教室",
                        unavailableHint: "先选一个教室", action: action)
    }
}

/// Shared dashed 「+ 新建」 button (备课「新建课程」, 知识库「上传资料」, 大模型「添加服务」): 40 high, r10,
/// 1pt dashed [4,3] textHint outline, 13pt textSecondary label with an 11pt semibold icon, hoverFill on hover.
struct DashedAddButton: View {
    var title: String
    var systemImage: String = "plus"
    var available: Bool = true
    var busy: Bool = false
    var help: String = ""
    var unavailableHint: String = ""
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        let enabled = available && !busy
        Button { if enabled { action() } } label: {
            DashedAddLabel(title: title, systemImage: systemImage, hovered: hovered && enabled)
        }
        .buttonStyle(.plain)
        .opacity(available ? 1 : 0.45)
        .onHover { hovered = $0 }
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(available ? "" : unavailableHint)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }
}

/// Appearance only (no action) of `DashedAddButton`, e.g. as a `Menu` label (a Menu label can't hold a Button).
/// Pass `hovered` from outside, or use `DashedAddMenuLabel` which tracks hover itself.
struct DashedAddLabel: View {
    var title: String
    var systemImage: String = "plus"
    var hovered: Bool = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 13))
        }
        .foregroundStyle(AppTheme.textSecondary)
        .frame(maxWidth: .infinity).frame(height: 40)
        .background(hovered ? AppTheme.hoverFill : Color.clear, in: shape)
        .overlay(shape.strokeBorder(AppTheme.textHint, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .contentShape(shape)
    }
}

/// `DashedAddLabel` that tracks its own hover (for `Menu { … } label: { DashedAddMenuLabel(title: "添加服务") }`).
struct DashedAddMenuLabel: View {
    var title: String
    var systemImage: String = "plus"
    @State private var hovered = false
    var body: some View {
        DashedAddLabel(title: title, systemImage: systemImage, hovered: hovered).onHover { hovered = $0 }
    }
}

/// Esc closes the classroom side panel. Leaves Esc alone while a sheet is up, a text field/editor has focus,
/// or a dropdown panel is open (those use Esc themselves).
private struct EscapeKeyCatcher: NSViewRepresentable {
    var action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let v = NSView(); context.coordinator.view = v; context.coordinator.action = action; context.coordinator.install(); return v }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.action = action }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.remove() }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var action: () -> Void = {}
        private var monitor: Any?
        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let self, let window = self.view?.window, event.window === window, window.attachedSheet == nil,
                      !(window.firstResponder is NSText),
                      !(window.childWindows ?? []).contains(where: { $0 is DropdownPanelWindow && $0.isVisible }) else { return event }
                self.action()
                return nil
            }
        }
        func remove() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}

private struct ClassroomGuideIllustration: View {
    var newLesson: Bool
    var body: some View {
        let name = newLesson ? "empty-lesson-guide-v1" : "empty-conversation-guide-v1"
        Group {
            if let url = Bundle.module.url(forResource: name, withExtension: "png"), let picture = NSImage(contentsOf: url) {
                Image(nsImage: picture).resizable().interpolation(.high).scaledToFit()
            }
        }
        .frame(width: 220, height: 150)
        .accessibilityHidden(true)
    }
}
