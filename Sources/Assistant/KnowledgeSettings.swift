import SwiftUI
import AssistantCore

struct KnowledgeSettingsView: View {
    @ObservedObject var store: Store
    @State private var selected: UUID?
    @State private var document: UUID?
    @State private var creating = false
    @State private var name = ""
    @State private var search = ""
    @State private var deleting: UUID?
    @State private var deletingDocument: UUID?
    @State private var saved = false
    @FocusState private var nameFocused: Bool
    
    var body: some View {
        Group {
            if let id = selected, let index = store.saved.libraries.firstIndex(where: { $0.id == id }) {
                detail(index: index)
            } else {
                libraryList
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        // Detail: the list card's bottom edge lines up with the sidebar appearance switcher (10 sidebar padding + 2 = 12 from the window bottom).
        .padding(.bottom, selected == nil ? 28 : 12)
        .onAppear {
            if CommandLine.arguments.contains("--preview-knowledge-detail"), selected == nil {
                selected = store.saved.libraries.first?.id
                document = store.saved.libraries.first?.documents.first?.id
            }
        }
        .sheet(isPresented: $creating) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(AppTheme.accent.opacity(0.12)).frame(width: 32, height: 32)
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("新建知识库")
                            .font(.system(size: 15, weight: .semibold))
                        Text("按课程建立专属资料库，助教将精准回答学员提问")
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("知识库名称")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    TextField("如：2026 新员工培训课程", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onSubmit(create)
                }
                
                HStack(spacing: 10) {
                    Spacer()
                    Button("取消") { creating = false }
                        .buttonStyle(ModernSecondaryButtonStyle(size: .regular))
                    Button("创建", action: create)
                        .buttonStyle(ModernPrimaryButtonStyle(size: .regular))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(22)
            .frame(width: 380)
            .tint(accent)
        }
        .alert(deletingLibrary.map { "删除“\($0.name)”？" } ?? "删除知识库？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }.keyboardShortcut(.defaultAction)
            Button("删除", role: .destructive) {
                if let id = deleting {
                    store.saved.libraries.removeAll { $0.id == id }
                    store.libraryIDs.remove(id)
                    if selected == id { selected = nil }
                    store.persist()
                }
                deleting = nil
            }
        } message: { Text("其中的 \(deletingLibrary?.documents.count ?? 0) 份资料会一起删除，删除后无法撤销。") }
        .background(AlertEscapeCancels(active: deleting != nil) { deleting = nil })
        .alert(deletingDocumentName.map { "删除“\($0)”？" } ?? "删除这份资料？", isPresented: Binding(get: { deletingDocument != nil }, set: { if !$0 { deletingDocument = nil } })) {
            Button("取消", role: .cancel) { deletingDocument = nil }.keyboardShortcut(.defaultAction)
            Button("删除", role: .destructive) {
                if let index = store.saved.libraries.firstIndex(where: { $0.id == selected }), let id = deletingDocument {
                    // After delete: select the previous entry; if none, the next; empty list → empty state.
                    let docs = store.saved.libraries[index].documents
                    let at = docs.firstIndex { $0.id == id } ?? 0
                    store.saved.libraries[index].documents.removeAll { $0.id == id }
                    let rest = store.saved.libraries[index].documents
                    if document == id || document == nil { document = rest.isEmpty ? nil : rest[max(0, min(at - 1, rest.count - 1))].id }
                    store.persist()
                }
                deletingDocument = nil
            }
        } message: { Text("删除后无法撤销。") }
        .background(AlertEscapeCancels(active: deletingDocument != nil) { deletingDocument = nil })
    }
    private var deletingLibrary: KnowledgeBase? { deleting.flatMap { id in store.saved.libraries.first { $0.id == id } } }
    private var deletingDocumentName: String? {
        guard let id = deletingDocument else { return nil }
        return store.saved.libraries.first { $0.id == selected }?.documents.first { $0.id == id }?.name
    }
    
    // MARK: - 知识库列表
    
    private var libraryList: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.saved.libraries.isEmpty {
                // Empty: same header as the list (no search box, nothing to search), solid 新建知识库 top right, centred empty state.
                HStack(spacing: 12) {
                    Spacer()
                    newLibraryButton
                }
                EmptyStateView(systemImage: "books.vertical", title: "还没有知识库", subtitle: "点右上「新建知识库」开始")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 搜索栏与新建
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.textHint)
                        TextField("搜索知识库…", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        if !search.isEmpty {
                            Button {
                                search = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    // subtleFill: inputFill is the same colour as pageBackground, so the field would vanish
                    .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(maxWidth: 280)
                    
                    Spacer()
                    
                    newLibraryButton
                }
                
                // 知识库书卡网格（顺序同原列表）
                ScrollView {
                    let filtered = store.saved.libraries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
                    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 20) {
                        ForEach(filtered) { library in
                            KnowledgeBookCard(library: library,
                                              open: { selected = library.id; document = nil },
                                              delete: { deleting = library.id },
                                              previewHover: CommandLine.arguments.contains("--preview-kb-hover") && library.id == filtered.dropFirst().first?.id)
                        }
                    }
                    .padding(.vertical, 4)
                    VStack {
                        if filtered.isEmpty && !search.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 26))
                                    .foregroundStyle(AppTheme.textHint)
                                Text("未找到匹配的知识库")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 128pt books (+3pt page edge), 22pt apart; rows 20pt apart.
    static let gridColumns = [GridItem(.adaptive(minimum: 131, maximum: 131), spacing: 22, alignment: .topLeading)]
    
    private var newLibraryButton: some View {
        Button {
            name = ""
            creating = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text("新建知识库")
            }
        }
        .buttonStyle(ModernPrimaryButtonStyle(size: .regular))
    }
    
    
    // MARK: - 知识库详情
    
    private func detail(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // 返回面包屑与状态
            HStack {
                Button {
                    store.persist()
                    selected = nil
                    document = nil
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("全部知识库")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                
                Spacer()
                // 「N 份资料」 pill removed (一致性规范 #3: repeats 「资料列表 N」); save feedback sits left of 「保存资料」.
            }
            
            // 知识库名称与操作：20pt semibold；铅笔（聚焦名称）和「···」都是 28×28 HoverCircle、13pt textSecondary，间距 4，「···」贴内容右边
            HStack(alignment: .center, spacing: 4) {
                TextField("知识库名称", text: $store.saved.libraries[index].name)
                    .font(.system(size: 20, weight: .semibold))
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .onSubmit { store.persist() }
                    .padding(.trailing, 8)
                
                Button { nameFocused = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(HoverCircleButtonStyle())
                .help("重命名")
                .accessibilityLabel("重命名知识库")
                
                Menu {
                    Button("删除知识库", role: .destructive) {
                        deleting = selected
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.button)
                .buttonStyle(HoverCircleButtonStyle())
                .menuIndicator(.hidden)
                .fixedSize()
                .help("更多")
                .accessibilityLabel("更多操作")
            }
            
            // 资料列表与编辑器。上传入口固定在左侧资料列表卡片底部（与备课「新建课程」同一个虚线按钮），点按直接打开文件选择；
            // 不再提供 FAQ / 手动新建入口，已存的旧条目照常显示和读取。
            HStack(alignment: .top, spacing: 16) {
                // 左侧资料列表
                VStack(alignment: .leading, spacing: 8) {
                    GroupTitle(text: "资料列表 \(store.saved.libraries[index].documents.count)")
                    
                    ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(store.saved.libraries[index].documents) { item in
                                let isSelected = document == item.id
                                
                                Button {
                                    store.persist()
                                    document = item.id
                                    saved = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "doc.text.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                                        Text(item.name)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                            .lineLimit(1)
                                            .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(height: 32)
                                    .background(
                                        isSelected ? AppTheme.accent.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain).id(item.id)
                            }
                        }
                    }
                    .onChange(of: document) { _, d in if let d { withAnimation { reader.scrollTo(d, anchor: .center) } } }
                    }
                    // Pinned under the list (the list scrolls above it): 10 from the card's sides and bottom (= card padding).
                    DashedAddButton(title: "上传资料", systemImage: "arrow.up.doc", help: "上传文档到这个知识库") {
                        store.importDocument(into: store.saved.libraries[index].id)
                    }
                }
                .frame(width: 196)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(10)
                .background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                // 右侧文档编辑器
                if let id = document, let d = store.saved.libraries[index].documents.firstIndex(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            HStack(spacing: 8) {
                                Image(systemName: "pencil.line")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.textSecondary)
                                TextField("资料名称", text: $store.saved.libraries[index].documents[d].name)
                                    .font(.system(size: 13, weight: .medium))
                                    .textFieldStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            
                            Button {
                                deletingDocument = id
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.danger)
                                    .frame(width: 30, height: 30)
                                    .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .help("删除此资料")
                        }
                        
                        // 编辑框
                        TextEditor(text: $store.saved.libraries[index].documents[d].text)
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .scrollContentBackground(.hidden)
                            .padding(12)
                            .background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                            )
                        
                        // 底部操作与保存状态
                        HStack(alignment: .center) {
                            Text("\(store.saved.libraries[index].documents[d].text.count) 字符")
                                .font(.system(size: 11))
                                .foregroundStyle(AppTheme.textHint)
                            
                            Spacer()
                            
                            if saved {   // the only save feedback: 11pt success, left of the button
                                Text("已保存")
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.success)
                                    .padding(.trailing, 8)
                            }
                            
                            Button {
                                store.persist()
                                saved = store.error.isEmpty
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("保存资料")
                                }
                            }
                            .buttonStyle(ModernPrimaryButtonStyle(size: .regular))
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.saved.libraries[index].documents.isEmpty {
                    EmptyStateView(systemImage: "arrow.up.doc", title: "还没有资料", subtitle: "点左下「上传资料」开始")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyStateView(systemImage: "arrow.left.circle", subtitle: "选择左侧的资料查看或编辑")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func create() {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let library = KnowledgeBase(name: title)
        store.saved.libraries.append(library)
        store.persist()
        selected = library.id
        document = nil
        creating = false
        if store.libraryIDs.isEmpty {
            store.libraryIDs.insert(library.id)
        }
    }
}

/// Direction B book (simplified): white page, 6pt spine in the name's colour, one page edge peeking out on the right;
/// shows only the name and 「N 份资料」. Hover tints the border and reveals the corner 「⋯」 (delete, also on right-click);
/// pressed / keyboard focus shows the accent border.
struct KnowledgeBookCard: View {
    var library: KnowledgeBase
    var open: () -> Void
    var delete: () -> Void
    var previewHover = false
    @State private var hovered = false
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                Text(library.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .lineSpacing(2)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text("\(library.documents.count) 份资料")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KnowledgeSpine.tagColor(for: library.name))
            }
            .padding(.leading, 20).padding(.trailing, 14).padding(.top, 18).padding(.bottom, 16)
            .frame(width: 128, height: 170, alignment: .topLeading)
        }
        .buttonStyle(BookCardStyle(spine: KnowledgeSpine.color(for: library.name), hovered: hovered))
        .focusEffectDisabled()
        .accessibilityLabel("\(library.name)，\(library.documents.count) 份资料")
        .accessibilityHint("打开知识库")
        .overlay(alignment: .bottomTrailing) {   // corner 「⋯」 sits by the count line, clear of the name
            Menu {
                Button("删除知识库", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(AppTheme.cardFill, in: Circle())
                    .overlay(Circle().strokeBorder(AppTheme.cardBorder, lineWidth: 1))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.bottom, 10).padding(.trailing, 8)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .accessibilityLabel("更多操作")
        }
        .frame(width: 128, height: 170)
        .onHover { hovered = $0 }
        .onAppear { if previewHover { hovered = true } }
        .contextMenu { Button("删除知识库", role: .destructive, action: delete) }
    }
}

private struct BookCardStyle: ButtonStyle {
    var spine: Color
    var hovered: Bool
    func makeBody(configuration: Configuration) -> some View { BookFace(configuration: configuration, spine: spine, hovered: hovered) }
    private struct BookFace: View {
        let configuration: Configuration
        let spine: Color
        let hovered: Bool
        @Environment(\.isFocused) private var focused
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            let shape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 12, topTrailingRadius: 12, style: .continuous)
            let selected = configuration.isPressed || focused
            configuration.label
                .background(AppTheme.cardFill)
                .overlay(alignment: .leading) { Rectangle().fill(spine).frame(width: 6) }
                .clipShape(shape)
                .overlay(shape.strokeBorder(selected ? AppTheme.accent : hovered ? spine.opacity(0.45) : AppTheme.cardBorder, lineWidth: 1))
                .contentShape(shape)
                .background(alignment: .topLeading) {   // one page edge: 3pt to the right, 2pt in at top and bottom
                    shape.fill(AppTheme.cardFill)
                        .overlay(shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.14) : AppTheme.cardBorder, lineWidth: 1))   // dark: white 14%
                        .frame(width: 131, height: 166).offset(y: 2)
                }
        }
    }
}
