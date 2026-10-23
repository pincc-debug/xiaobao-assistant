import SwiftUI
import AssistantCore

struct ModelSettingsView: View {
    @ObservedObject var store: Store
    @State private var section = "大模型"
    @State private var selected: UUID?
    @State private var models: [String] = []
    @State private var pickModel = DropdownPreview.isOpen("model")
    @State private var modelFieldWidth: CGFloat = 0
    @State private var loading = false
    @State private var result = ""
    @State private var fetchTask: Task<Void, Never>?
    @State private var deletingProvider: UUID?   // D7: 「删除服务」 asks first (取消 = Return / Esc)
    
    private let tabs = [
        ("大模型", "cpu"),
        ("消息判断", "brain"),
        ("语音转写", "waveform"),
        ("保利威", "video.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Segmented Tab Picker
            PillSegments(items: tabs.map { ($0.0, $0.0) }, selection: $section)
            
            if section == "大模型" {
                providers
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if section == "消息判断" {
                            jevSection
                        } else if section == "语音转写" {
                            asrSection
                        } else {
                            polyvSection
                        }
                        
                        // Bottom Save Toolbar
                        HStack(alignment: .center) {
                            Button("打开日志") { store.openLogs() }
                                .buttonStyle(ModernSecondaryButtonStyle(size: .regular))
                            if !result.isEmpty {
                                HStack(spacing: 5) {
                                    Image(systemName: result.hasPrefix("已") || result == "连接正常" ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .font(.system(size: 11))
                                    Text(result)
                                        .font(.system(size: 13))
                                }
                                .foregroundStyle(result.hasPrefix("已") || result == "连接正常" ? AppTheme.success : AppTheme.danger)
                            }
                            
                            Spacer()
                            
                            Button {
                                store.saveConnections(section: section)
                                result = store.error.isEmpty ? "已保存配置" : store.error
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("保存配置")
                                }
                            }
                            .buttonStyle(ModernPrimaryButtonStyle(size: .regular))
                        }
                        .padding(.top, 4)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .onAppear {
            selected = store.saved.defaultProviderID ?? store.saved.providers.first?.id
        }
        .alert(deletingProviderName.map { "删除“\($0)”？" } ?? "删除服务？", isPresented: Binding(get: { deletingProvider != nil }, set: { if !$0 { deletingProvider = nil } })) {
            Button("取消", role: .cancel) { deletingProvider = nil }.keyboardShortcut(.defaultAction)
            Button("删除", role: .destructive) { if let id = deletingProvider { deleteProvider(id) }; deletingProvider = nil }
        } message: { Text("这个服务的地址、API Key 和模型设置会从这台电脑上删除。删除后无法撤销。") }
        .background(AlertEscapeCancels(active: deletingProvider != nil) { deletingProvider = nil })
        .onChange(of: selected) { _, _ in reset() }
        .onChange(of: section) { _, _ in reset() }
        .onChange(of: store.jevKey) { _, _ in result = "" }
        .onChange(of: store.dashKey) { _, _ in result = "" }
        .onChange(of: store.polyvSecret) { _, _ in result = "" }
        .onChange(of: store.saved.preferences.userID) { _, _ in result = "" }
        .onChange(of: store.saved.preferences.appID) { _, _ in result = "" }
        .onDisappear { fetchTask?.cancel() }
    }
    
    // MARK: - 大模型 Providers
    
    private var providers: some View {
        HStack(alignment: .top, spacing: 18) {
            // 左侧服务列表
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    GroupTitle(text: store.saved.providers.isEmpty ? "服务列表" : "服务列表 \(store.saved.providers.count)")
                    Spacer()
                }
                
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(store.saved.providers) { provider in
                            let isSelected = selected == provider.id
                            let isDefault = store.saved.defaultProviderID == provider.id
                            
                            Button {
                                selected = provider.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "cpu")
                                        .font(.system(size: 13))
                                        .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(provider.name)
                                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                                            .lineLimit(1)
                                        Text(provider.kind.rawValue)
                                            .font(.system(size: 11))
                                            .foregroundStyle(AppTheme.textHint)
                                    }
                                    
                                    Spacer(minLength: 0)
                                    
                                    if isDefault {
                                        StatusTag(text: "默认", color: AppTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected ? AppTheme.accent.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // 添加服务菜单：同「新建课程」的虚线按钮外观，固定在卡片底部；菜单项不变
                Menu {
                    addServiceItems
                } label: {
                    DashedAddMenuLabel(title: "添加服务")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("添加大模型服务")
                .accessibilityLabel("添加服务")
            }
            .frame(width: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(10)
            .background(AppTheme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            
            // 右侧配置表单
            if let id = selected, let index = store.saved.providers.firstIndex(where: { $0.id == id }) {
                let provider = store.saved.providers[index]
                let isDefault = store.saved.defaultProviderID == id
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Header
                        HStack(alignment: .center) {
                            HStack(spacing: 8) {
                                Image(systemName: "cpu.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(AppTheme.accent)
                                TextField("服务名称", text: $store.saved.providers[index].name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .textFieldStyle(.plain)
                            }
                            
                            Spacer()
                            
                            if isDefault { StatusTag(text: "默认", color: AppTheme.accent) }
                            
                            Menu {
                                if !isDefault {
                                    Button("设为默认") { store.saved.defaultProviderID = id; store.persist() }
                                }
                                Button("删除服务", role: .destructive) {
                                    deletingProvider = id
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: 24, height: 24)
                                    .background(Color.primary.opacity(0.04), in: Circle())
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        
                        Color.clear.frame(height: 16)
                        
                        // Form
                        VStack(alignment: .leading, spacing: 14) {
                            
                            field("Base URL", text: $store.saved.providers[index].baseURL, placeholder: "如：https://api.openai.com/v1")
                            
                            secure("API Key", text: Binding(get: {
                                store.providerKeys[id] ?? ""
                            }, set: {
                                store.providerKeys[id] = $0
                                reset()
                            }), placeholder: "输入 API 密钥")
                            VStack(alignment: .leading, spacing: 6) {
                                Text("模型 ID")
                                    .font(.system(size: 13, weight: .medium))
                                HStack(spacing: 8) {
                                    TextField("例如：gpt-4o-mini 或 deepseek-chat", text: $store.saved.providers[index].model)
                                        .textFieldStyle(FilledFieldStyle())
                                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { modelFieldWidth = $0 }
                                    
                                    if !models.isEmpty {
                                        // Same choices as before; the current model now carries a checkmark (display only).
                                        let current = store.saved.providers[index].model
                                        ModelPickerButton(isOpen: pickModel) { DropdownGate.toggle($pickModel) }
                                            .background(DropdownPanelAnchor(isPresented: $pickModel, leadingExtension: modelFieldWidth + 8, items: models.map { model in
                                                DropdownItem(id: model, title: model, selected: model == current) { store.saved.providers[index].model = model }
                                            }))
                                    }
                                    
                                    Button {
                                        refresh(provider)
                                    } label: {
                                        if loading {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 13))
                                        }
                                    }
                                    .disabled(loading)
                                    .help("获取远程可用模型列表")
                                }
                            }
                        }
                        
                        if !result.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: result.hasPrefix("已") || result == "连接正常" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                Text(result)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(result.hasPrefix("已") || result == "连接正常" ? AppTheme.success : AppTheme.danger)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background((result.hasPrefix("已") || result == "连接正常" ? AppTheme.success : AppTheme.danger).opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        
                        // Actions
                        HStack {
                            Button {
                                test(provider)
                            } label: {
                                HStack(spacing: 5) {
                                    if loading {
                                        ProgressView().controlSize(.small)
                                    }
                                    Text("测试连接")
                                }
                            }
                            .buttonStyle(ModernSecondaryButtonStyle(size: .regular))
                            .disabled(loading || provider.model.isEmpty)
                            
                            Spacer()
                            
                            Button {
                                save(provider)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                    Text("保存服务")
                                }
                            }
                            .buttonStyle(ModernPrimaryButtonStyle(size: .regular))
                        }
                    }
                    .settingsCard()
                }
                .onChange(of: provider.baseURL) { _, _ in reset() }
                .onChange(of: provider.kind) { _, _ in reset() }
            } else {
                VStack(spacing: 16) {
                    if store.saved.providers.isEmpty {
                        // 一致性规范 #11: text only — the sidebar 「添加服务」 is the single entry.
                        EmptyStateView(systemImage: "cpu", title: "还没有大模型服务", subtitle: "支持 OpenAI 兼容接口和 Anthropic，点左下「添加服务」开始")
                    } else {
                        EmptyStateView(systemImage: "cpu", title: "选择左侧的服务查看设置")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Jev 配置
    
    private var jevSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("消息判断")
                        .font(.system(size: 15, weight: .semibold))
                    Text("识别问题与违规消息")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                StatusTag(text: store.jevKey.isEmpty ? "未配置" : "已配置", color: store.jevKey.isEmpty ? .secondary : AppTheme.success)
            }
            
            Color.clear.frame(height: 16)
            
            secure("API Key", text: $store.jevKey, placeholder: "输入访问密钥")
        }
        .settingsCard()
    }
    
    // MARK: - ASR 配置
    
    private var asrSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.info.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.info)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("语音转写")
                        .font(.system(size: 15, weight: .semibold))
                    Text("记录讲课内容与语音指令")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                StatusTag(text: store.dashKey.isEmpty ? "未配置" : "已配置", color: store.dashKey.isEmpty ? .secondary : AppTheme.success)
            }
            
            Color.clear.frame(height: 16)
            
            secure("API Key", text: $store.dashKey, placeholder: "输入百炼北京地域 API Key")
            
        }
        .settingsCard()
    }
    
    // MARK: - 保利威配置
    
    private var polyvSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: "video.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("保利威直播间连接")
                        .font(.system(size: 15, weight: .semibold))
                    Text("接入保利威聊天室 WebSocket，监听学员提问并推送助教回复")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                StatusTag(text: store.polyvConfigured ? "已配置" : "未配置", color: store.polyvConfigured ? AppTheme.success : .secondary)
            }
            
            Color.clear.frame(height: 16)
            
            field("用户 ID (User ID)", text: $store.saved.preferences.userID, placeholder: "例如：12345678")
            field("应用 ID (App ID)", text: $store.saved.preferences.appID, placeholder: "例如：e8abc123...")
            secure("应用密钥 (App Secret)", text: $store.polyvSecret, placeholder: "输入分配的 App Secret")
        }
        .settingsCard()
    }
    
    // MARK: - 辅助方法
    
    /// Menu entries for the sidebar 「添加服务」.
    @ViewBuilder private var addServiceItems: some View {
        Button("Anthropic 协议") { add("Anthropic", kind: .anthropic, url: "https://api.anthropic.com/v1") }
        Button("OpenAI 兼容协议") { add("OpenAI 兼容", kind: .compatible, url: "") }   // OpenAI-compatible: URL / key / model
    }

    private func add(_ name: String, kind: ModelProvider.Kind, url: String, model: String = "") {
        var provider = ModelProvider()
        provider.name = name
        provider.kind = kind
        provider.baseURL = url
        provider.model = model
        store.saved.providers.append(provider)
        selected = provider.id
        if store.saved.defaultProviderID == nil || !store.saved.providers.contains(where: { $0.id == store.saved.defaultProviderID }) {
            store.saved.defaultProviderID = provider.id
        }
        store.persist()
    }
    
    private func save(_ provider: ModelProvider) {
        if store.previewMode { store.persist(); result = "已保存"; return }
        do {
            _ = try provider.endpoint("models")
            try Vault.write(store.providerKeys[provider.id] ?? "", name: "provider." + provider.id.uuidString)
            store.persist()
            result = store.error.isEmpty ? "已保存" : store.error
        } catch {
            result = error.localizedDescription
        }
    }
    
    /// ⋯ › 删除服务: deletes immediately, no confirmation.
    private var deletingProviderName: String? { deletingProvider.flatMap { id in store.saved.providers.first { $0.id == id }?.name } }
    private func deleteProvider(_ id: UUID) {
        do { if !store.previewMode { try Vault.write("", name: "provider." + id.uuidString) } } catch { store.error = error.localizedDescription; return }
        let at = store.saved.providers.firstIndex { $0.id == id } ?? 0
        store.saved.providers.removeAll { $0.id == id }
        store.providerKeys.removeValue(forKey: id)
        // Deleting the default promotes the next remaining service (or the previous one if it was last).
        let next = store.saved.providers.isEmpty ? nil : store.saved.providers[min(at, store.saved.providers.count - 1)].id
        if store.saved.defaultProviderID == id || !store.saved.providers.contains(where: { $0.id == store.saved.defaultProviderID }) { store.saved.defaultProviderID = next }
        selected = next
        store.persist()
    }
    private func reset() {
        fetchTask?.cancel()
        loading = false
        loadCachedModels()
        result = ""
    }
    
    private func loadCachedModels() {
        guard let provider = store.saved.providers.first(where: { $0.id == selected }) else { models = []; return }
        let cache = provider.availableCachedModels
        models = cache.isEmpty && !provider.model.isEmpty ? [provider.model] : cache
    }
    private func refresh(_ provider: ModelProvider) {
        let key = store.providerKeys[provider.id] ?? ""
        loading = true
        result = ""
        fetchTask = Task {
            do {
                let values = try await ProviderAPI.models(provider, key: key)
                guard !Task.isCancelled, selected == provider.id, let current = store.saved.providers.first(where: { $0.id == provider.id }), current.modelsContext == provider.modelsContext else { if selected == provider.id { loading = false }; return }
                models = values
                if let i = store.saved.providers.firstIndex(where: { $0.id == provider.id }) {
                    store.saved.providers[i].cachedModels = values
                    store.saved.providers[i].cachedModelsContext = provider.modelsContext
                    store.saved.providers[i].modelsRefreshedAt = Date()
                    store.persist()
                }
                result = "已获取 \(values.count) 个可用模型"
            } catch {
                if !Task.isCancelled {
                    result = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                loading = false
            }
        }
    }
    
    private func test(_ provider: ModelProvider) {
        let key = store.providerKeys[provider.id] ?? ""
        loading = true
        result = ""
        fetchTask = Task {
            do {
                let output = try await ProviderAPI.generate(provider, key: key, system: "只返回JSON：{\"ok\":true}", input: ["test": "connection"])
                guard !Task.isCancelled else { return }
                result = output["ok"] as? Bool == true ? "连接正常" : "模型返回格式异常"
            } catch {
                if !Task.isCancelled {
                    result = error.localizedDescription
                }
            }
            if !Task.isCancelled {
                loading = false
            }
        }
    }
    
    private func field(_ title: String, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            TextField(placeholder, text: text)
                .textFieldStyle(FilledFieldStyle())
        }
    }
    
    private func secure(_ title: String, text: Binding<String>, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            SecureField(placeholder, text: text)
                .textFieldStyle(FilledFieldStyle())
        }
    }
}

/// 32×32 square chevron next to the 模型 ID field; accent border and chevron while its list is open.
private struct ModelPickerButton: View {
    var isOpen: Bool
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            DropdownChevron(open: isOpen, color: isOpen ? AppTheme.accent : AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(AppTheme.cardFill, in: shape)
                .overlay(shape.strokeBorder(isOpen ? AppTheme.accent : hovered ? Color.primary.opacity(0.25) : AppTheme.cardBorder, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isOpen)
        .help("选择已获取的模型")
        .accessibilityLabel("选择模型")
        .accessibilityHint("弹出选项列表")
    }
}
