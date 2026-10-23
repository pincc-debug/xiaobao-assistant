import SwiftUI
import AppKit
import AssistantCore

// MARK: - Design Tokens & Theme

enum AppTheme {
    // Primary Brand Accent
    static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        func c(_ h: UInt32, _ a: CGFloat) -> NSColor { NSColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255, green: CGFloat((h >> 8) & 0xFF) / 255, blue: CGFloat(h & 0xFF) / 255, alpha: a) }
        return Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? c(dark, da) : c(light, la) })
    }
    // Primary Brand Accent (brand-500 / dark primary)
    static let accent = dyn(0x2469F3, 0x1D4ED8)
    static let stopRed = dyn(0xFF3B30, 0xFF6961)
    /// 「下课」 pill gradient on the live timer (kept as designed, only named here).
    static let liveEndTop = Color(red: 0.90, green: 0.22, blue: 0.22), liveEndBottom = Color(red: 0.76, green: 0.14, blue: 0.14)
    /// Reply-card viewer avatars: accent / teal / orange, used at 15% behind the initial.
    static let avatarSoft: [Color] = [accent, Color(red: 0.19, green: 0.69, blue: 0.70), Color(red: 1.0, green: 0.58, blue: 0.0)]
    static let liveEndTopHover = Color(red: 0.96, green: 0.28, blue: 0.28), liveEndBottomHover = Color(red: 0.82, green: 0.16, blue: 0.16)
    /// Vertical column separators: 0.5pt black 6% / white 8%.
    static let columnLine = dyn(0xE3E7EE, 0x1E293B)
    static let sidebarFill = pageBackground   // rule 1: no extra grey
    /// Pressed
    static let accentDark = dyn(0x2469F3, 0x2563EB)   // SPEC bar-bot; also pressed
    /// Hover
    static let accentLight = dyn(0x1B5DE3, 0x60A5FA)
    /// brand-50 / dark: brand at 18%
    static let brand50 = dyn(0xF2F8FF, 0x132037)
    static let link = dyn(0x1B5DE3, 0x93C5FD)

    static let accentGradient = LinearGradient(
        colors: [dyn(0x3A7BF6, 0x6A9CF9), dyn(0x2469F3, 0x4A86F7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    // Settings surfaces
    static let pageBackground = dyn(0xF5F6F8, 0x0B1220)
    static let cardFill = dyn(0xFFFFFF, 0x0F172A)
    static let inputFill = dyn(0xF5F6F8, 0x1C1C1E)
    /// 进行中卡片 fill (课堂 / 气泡 interaction cards): black 3.5% / white 5%, so it takes the tone of the surface underneath.
    static let liveCardFill = dyn(0x000000, 0xFFFFFF, 0.035, 0.05)
    /// Rule 2: cards carry no shadow (only floating layers do).
    static let cardShadow = Color.clear
    // Rule 5: three text levels.
    static let textSecondary = dyn(0x4B5563, 0x94A3B8)
    static let textHint = dyn(0x6B7280, 0x7C8AA0)
    static let groupTitle = dyn(0x6B7078, 0x8391A7)
    static let rowDivider = dyn(0xCBD2DC, 0x334155)

    // MARK: - Reshape / 课后分析台
    // SPEC §1.1 maps roles onto existing AppTheme names. Only brandStroke is new.
    // Values above (pageBackground / cardFill / …) already carry SPEC dark+light.
    // Aliases below keep reshape views readable; they are NOT extra palettes.
    static let brandStroke = dyn(0xC7D8FB, 0x1E3A5F)   // NEW — 强调描边 / 深色徽章底
    static let brand50End = dyn(0xE8F0FE, 0x172554)    // hero gradient end (brand50 pair)
    /// Title / body ink for reshape panels (Ink.primary is ShapeStyle, not a Color).
    static let textStrong = dyn(0x111827, 0xF8FAFC)
    static let textBody = dyn(0x374151, 0xCBD5E1)
    /// Chart series · 陪练练习 (SPEC accent chart value; button accent stays darker).
    static let accentBright = dyn(0x2469F3, 0x3B82F6)
    /// Correct-rate badge soft pair (SPEC rate-*).
    static let rateBg = dyn(0xFEECEC, 0x7F1D1D)
    static let rateFg = dyn(0xB42318, 0xFECACA)
    static let rateBorder = dyn(0xF9C5C0, 0x991B1B)
    /// Review entry icon soft pairs.
    static let icoCyanBg = dyn(0xE3F5FA, 0x164E63)
    static let icoCyanFg = dyn(0x0E7490, 0x67E8F9)
    static let icoPurpleBg = dyn(0xF1EAFE, 0x4C1D95)
    static let icoPurpleFg = dyn(0x6D28D9, 0xC4B5FD)
    /// Badge pair: light uses brand50-ish tint; dark uses brandStroke.
    static let badgeBg = dyn(0xEAF2FF, 0x1E3A5F)
    static let badgeFg = dyn(0x1B4FC4, 0x93C5FD)

    // Readable aliases → existing SPEC-aligned tokens (no second palette).
    static var bgCanvas: Color { pageBackground }
    static var bgPanel: Color { cardFill }
    static var bgTile: Color { surfaceBackground }
    static var bgTileHead: Color { subtleFill }
    static var bgHeaderTop: Color { brand50 }
    static var bgHeroEnd: Color { brand50End }
    static var borderDefault: Color { cardBorder }
    static var borderAccent: Color { brandStroke }
    static var textMuted: Color { textSecondary }
    static var textFaint: Color { groupTitle }
    static var textHintR: Color { textHint }
    static var accentSolid: Color { accent }
    static var accentSoft: Color { accentLight }
    static var segPractice: Color { accentBright }
    static var segQA: Color { info }
    static var segKP: Color { purple }
    static var segScript: Color { warning }
    static var typeSingle: Color { accentBright }
    static var typeMulti: Color { dyn(0x0891B2, 0x67E8F9) }  // SPEC --type-multi
    static var dangerBright: Color { danger }
    static var dangerSoftBg: Color { rateBg }
    static var placeholderBorder: Color { hairline }
    static var chartGrid: Color { columnLine }
    static var emptyText: Color { textSecondary }
    static var hfBar: Color { dyn(0x0284C7, 0x38BDF8) }  // SPEC --hf-bar
    static var barTop: Color { dyn(0x4F86F7, 0x60A5FA) }  // SPEC --bar-top
    static var barBot: Color { accentDark }
    static var rowStripe: Color { hoverFill }
    static var chipStroke: Color { rowDivider }


    // Semantic Colors
    /// Light values unchanged; dark uses the system colours (.systemGreen / .systemOrange).
    static let success = Color(nsColor: NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemGreen : NSColor(srgbRed: 0.16, green: 0.74, blue: 0.48, alpha: 1) })   // Emerald
    static let warning = dyn(0xB45309, 0xFBBF24)   // SPEC seg-script
    static let danger = dyn(0xC8261B, 0xF87171)   // SPEC danger; stopRed kept for legacy pills
    static let info = dyn(0x0891B2, 0x22D3EE)    // SPEC seg-qa / type-multi / hf-bar family
    static let purple = dyn(0x7C3AED, 0xA78BFA)  // SPEC seg-kp

    // Semantic Category Helpers
    static func color(for kind: PendingMessage.Kind) -> Color {
        switch kind {
        case .question: return accent
        case .notice: return info
        case .technical: return warning
        case .risk: return danger
        case .material: return purple
        }
    }
    
    static func title(for kind: PendingMessage.Kind) -> String {
        switch kind {
        case .question: return "回答问题"
        case .notice: return "发送公告"
        case .technical: return "技术反馈"
        case .risk: return "风险提醒"
        case .material: return "发送资料"
        }
    }
    
    static func icon(for kind: PendingMessage.Kind) -> String {
        switch kind {
        case .question: return "bubble.left.and.text.bubble.right"
        case .notice: return "paperplane"
        case .technical: return "wifi.exclamationmark"
        case .risk: return "exclamationmark.shield"
        case .material: return "doc"
        }
    }
    
    // Backgrounds & Surface Fills
    static let cardBackground = Color(nsColor: .windowBackgroundColor)
    static let surfaceBackground = dyn(0xF8FAFC, 0x111827)
    static let subtleFill = dyn(0xF2F4F7, 0x0B1220)
    static let glassTint = 0.32
    static let glassTintDark = 0.5
    static let hoverFill = dyn(0xF5F7FA, 0x1E293B, 1.0, 0.40)
    static let cardBorder = dyn(0xE3E7EE, 0x1E293B)
    static let hairline = dyn(0x808999, 0x64748B)
    static let strokeRim = Color.white.opacity(0.35)
}

// MARK: - View Modifiers

/// Multi-layered authentic macOS elevation shadow for floating layers
struct FloatingElevationModifier: ViewModifier {
    var radius: CGFloat = 20
    var y: CGFloat = 8
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1.5)
            .shadow(color: Color.black.opacity(0.12), radius: radius, x: 0, y: y)
    }
}

/// One material for every pet-related card: clear liquid glass with a faint window tint.
struct GlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var id: String? = nil
    var namespace: Namespace.ID? = nil
    static var tint: Color {
        Color(nsColor: NSColor(name: nil) { a in
            let dark = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.windowBackgroundColor.withAlphaComponent(dark ? AppTheme.glassTintDark : AppTheme.glassTint)
        })
    }
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if let id, let namespace {
                content.glassEffect(.clear.tint(Self.tint), in: shape).glassEffectID(id, in: namespace)
            } else {
                content.glassEffect(.clear.tint(Self.tint), in: shape)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                )
                .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1.5)
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        }
    }
}

/// Lets sibling glass shapes morph into each other (macOS 26+); plain stack before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: spacing) { content } } else { content }
    }
}

struct SettingsCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(AppTheme.cardFill))
            .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 1)
    }
}

/// Inset 0.5pt row divider (rule 4).
struct RowDivider: View {
    var leading: CGFloat = 52
    var body: some View { Rectangle().fill(AppTheme.rowDivider).frame(height: 0.5).padding(.leading, leading) }
}

/// Empty state (consistency spec 7): 28pt light textHint icon (no circle), 15pt semibold title, 13pt textSecondary subtitle;
/// 8 between icon and title, 4 between title and subtitle. Centre it in its area with `.frame(maxWidth:maxHeight: .infinity)`.
struct EmptyStateView: View {
    let systemImage: String
    var title: String? = nil      // nil: hint only (icon + one subtitle-style line)
    var subtitle: String? = nil
    var avatarPet: String? = nil  // set: a 40pt round assistant head (形象与风格 persona) replaces the SF symbol
    var body: some View {
        VStack(spacing: 0) {
            if let avatarPet { AssistantAvatar(pet: avatarPet, size: 40).fixedSize() }
            else { Image(systemName: systemImage).font(.system(size: 28, weight: .light)).foregroundStyle(AppTheme.textHint) }
            if let title { Text(title).font(.system(size: 15, weight: .semibold)).multilineTextAlignment(.center).padding(.top, 8) }
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(AppTheme.textSecondary).multilineTextAlignment(.center).padding(.top, title == nil ? 8 : 4) }
        }
    }
}

/// Group title above a settings card (rule 3).
struct GroupTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(AppTheme.textSecondary).padding(.leading, 4) }
}

/// Segmented control (rule 9).
struct PillSegments<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let on = item.0 == selection
                Button { selection = item.0 } label: {
                    Text(item.1).font(.system(size: 13, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? AnyShapeStyle(AppTheme.accent) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, 14).frame(height: 28)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(AppTheme.dyn(0xFFFFFF, 0x48484A)).shadow(color: .black.opacity(0.08), radius: 2, y: 1) }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2).frame(height: 32)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

extension View {
    func floatingElevation(radius: CGFloat = 20, y: CGFloat = 8) -> some View {
        modifier(FloatingElevationModifier(radius: radius, y: y))
    }
    
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
    func glassCard(cornerRadius: CGFloat = 18, id: String, in namespace: Namespace.ID) -> some View {
        modifier(GlassModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), id: id, namespace: namespace))
    }
    func glass<S: Shape>(_ shape: S) -> some View {
        modifier(GlassModifier(shape: shape))
    }
    
    func settingsCard(cornerRadius: CGFloat = 14, padding: CGFloat = 18) -> some View {
        modifier(SettingsCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

// MARK: - Reusable UI Components

struct CategoryBadge: View {
    let kind: PendingMessage.Kind
    var iconOnly: Bool = false
    
    var body: some View {
        let color = AppTheme.color(for: kind)
        let title = AppTheme.title(for: kind)
        let icon = AppTheme.icon(for: kind)
        
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            if !iconOnly {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, iconOnly ? 6 : 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatusTag: View {
    let text: String
    var color: Color = AppTheme.accent
    var isLive: Bool = false
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(color.opacity(0.1), in: Capsule())
    }
}

struct WaveformVisualizer: View {
    @State private var phase = 0.0
    var active: Bool = true
    var barCount: Int = 4
    var color: Color = AppTheme.accent
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: 3, height: active ? height(for: index) : 4)
                    .animation(
                        active ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(index) * 0.12) : .default,
                        value: phase
                    )
            }
        }
        .frame(height: 18)
        .onAppear {
            if active { phase = 1.0 }
        }
        .onChange(of: active) { _, isActive in
            phase = isActive ? 1.0 : 0.0
        }
    }
    
    private func height(for index: Int) -> CGFloat {
        if phase == 0.0 { return 4 }
        let heights: [CGFloat] = [14, 18, 12, 16]
        return heights[index % heights.count]
    }
}

// MARK: - Button Styles

struct ModernPrimaryButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    var cornerRadiusOverride: CGFloat? = nil
    var horizontalPaddingOverride: CGFloat? = nil
    var verticalPaddingOverride: CGFloat? = nil
    var disabledLook = false
    
    init(size: ControlSize = .regular, cornerRadius: CGFloat? = nil, horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil, disabledLook: Bool = false) {
        self.size = size
        self.cornerRadiusOverride = cornerRadius
        self.horizontalPaddingOverride = horizontalPadding
        self.verticalPaddingOverride = verticalPadding
        self.disabledLook = disabledLook
    }
    
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, shape: RoundedRectangle(cornerRadius: cornerRadiusOverride ?? cornerRadius, style: .continuous),
                    fontSize: fontSize, hPad: horizontalPaddingOverride ?? horizontalPadding, vPad: verticalPaddingOverride ?? verticalPadding, height: fixedHeight, disabledLook: disabledLook)
    }
    /// small / mini: 28 high like QuietFill and Send (unless a vertical padding is given explicitly).
    private var fixedHeight: CGFloat? { (size == .small || size == .mini) && verticalPaddingOverride == nil ? 28 : nil }
    /// Not clickable (`.disabled` or `disabledLook`) = grey, not pale blue: black 6% / white 8% fill, textHint label, no scale.
    private struct PrimaryBody: View {
        let configuration: Configuration
        let shape: RoundedRectangle
        let fontSize: CGFloat, hPad: CGFloat, vPad: CGFloat
        let height: CGFloat?
        let disabledLook: Bool
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let off = disabledLook || !isEnabled
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(off ? AppTheme.textHint : Color.white)
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .frame(height: height)
                .background { if off { shape.fill(AppTheme.dyn(0x000000, 0xFFFFFF, 0.06, 0.08)) } else { shape.fill(configuration.isPressed ? AppTheme.accentDark : AppTheme.accent) } }   // solid, no shadow (rule 2)
                .scaleEffect(configuration.isPressed && !off ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .mini, .small: return 13   // type scale is 11 / 13 / 15 (no 12)
        case .regular: return 13
        case .large, .extraLarge: return 14
        @unknown default: return 13
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .mini, .small: return 10
        case .regular: return 14
        case .large, .extraLarge: return 18
        @unknown default: return 14
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .mini, .small: return 0    // small is a fixed 28 high (see fixedHeight)
        case .regular: return 7
        case .large, .extraLarge: return 9
        @unknown default: return 7
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .mini, .small: return 8
        case .regular: return 9
        case .large, .extraLarge: return 11
        @unknown default: return 9
        }
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    var cornerRadiusOverride: CGFloat? = nil
    var horizontalPaddingOverride: CGFloat? = nil
    var verticalPaddingOverride: CGFloat? = nil
    
    init(size: ControlSize = .regular, cornerRadius: CGFloat? = nil, horizontalPadding: CGFloat? = nil, verticalPadding: CGFloat? = nil) {
        self.size = size
        self.cornerRadiusOverride = cornerRadius
        self.horizontalPaddingOverride = horizontalPadding
        self.verticalPaddingOverride = verticalPadding
    }
    
    func makeBody(configuration: Configuration) -> some View {
        let cr = cornerRadiusOverride ?? cornerRadius
        let hp = horizontalPaddingOverride ?? horizontalPadding
        let vp = verticalPaddingOverride ?? verticalPadding
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, hp)
            .padding(.vertical, vp)
            .frame(height: (size == .small || size == .mini) && verticalPaddingOverride == nil ? 28 : nil)
            .background(
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
    
    private var fontSize: CGFloat {
        switch size {
        case .mini, .small: return 13   // type scale is 11 / 13 / 15 (no 12)
        case .regular: return 13
        case .large, .extraLarge: return 14
        @unknown default: return 13
        }
    }
    
    private var horizontalPadding: CGFloat {
        switch size {
        case .mini, .small: return 10
        case .regular: return 14
        case .large, .extraLarge: return 18
        @unknown default: return 14
        }
    }
    
    private var verticalPadding: CGFloat {
        switch size {
        case .mini, .small: return 0    // small is a fixed 28 high (see fixedHeight)
        case .regular: return 7
        case .large, .extraLarge: return 9
        @unknown default: return 7
        }
    }
    
    private var cornerRadius: CGFloat {
        switch size {
        case .mini, .small: return 8
        case .regular: return 9
        case .large, .extraLarge: return 11
        @unknown default: return 9
        }
    }
}


/// 「依据：…」 under an answer: 11pt secondary grey, doc.text glyph, one line, tail-truncated, plain (not a link).
struct SourceLine: View {
    let text: String
    var body: some View {
        Label { Text(text).lineLimit(1).truncationMode(.tail) } icon: { Image(systemName: "doc.text").font(.system(size: 11)) }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11))
            .foregroundStyle(AppTheme.dyn(0x8A8F99, 0x8E8E93))
    }
}

/// Small secondary accent button: 26 high, accent text on accent 10%.
struct SmallAccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(enabled ? AppTheme.accent : Color.secondary)
            .padding(.horizontal, 12).frame(height: 24)
            .background(Capsule().fill((enabled ? AppTheme.accent : Color.secondary).opacity(configuration.isPressed ? 0.18 : 0.12)))
            .contentShape(Capsule())
    }
}

/// One-shot shortcuts: accent only while pressed, never for hover or matching content.
struct PromptCapsuleStyle: ButtonStyle {
    var fontSize: CGFloat = 13
    var horizontalPadding: CGFloat = 14
    var height: CGFloat = 30
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let pressed = enabled && configuration.isPressed
        configuration.label
            .font(.system(size: fontSize))
            .foregroundStyle(pressed ? AppTheme.accent : AppTheme.textSecondary)
            .padding(.horizontal, horizontalPadding).frame(height: height)
            .background(Capsule().fill(pressed ? AppTheme.accent.opacity(0.12) : AppTheme.dyn(0x000000, 0xFFFFFF, 0.04, 0.06)))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.5)
    }
}

/// 教室 course status dot (display only, mapped from the existing ClassroomLesson.status text).
struct LessonStatusDot: View {
    enum Phase { case before, live, after
        init(status: String) { self = status == LessonAssetStage.classroom.statusTitle ? .live : status == LessonAssetStage.review.statusTitle ? .after : .before }
        var help: String { switch self { case .before: LessonAssetStage.preparation.statusTitle; case .live: LessonAssetStage.classroom.statusTitle; case .after: LessonAssetStage.review.statusTitle } }
    }
    let phase: Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            switch phase {
            case .before: Circle().fill(AppTheme.textHint)
            case .after: Circle().fill(AppTheme.success)
            case .live:
                if !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { t in
                        let k = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                        Circle().fill(AppTheme.stopRed.opacity(0.4 * (1 - k))).scaleEffect(1 + 1.2 * k)
                    }
                }
                Circle().fill(AppTheme.stopRed)
            }
        }
        .frame(width: 8, height: 8).accessibilityLabel(phase.help)
    }
}

/// 教室 发送: solid accent only when enabled (has content); otherwise black 6% + hint text.
struct SendButtonStyle: ButtonStyle {
    /// 停止: same shape/size as 发送, neutral fill, the label carries only a red icon.
    var stop = false
    func makeBody(configuration: Configuration) -> some View {
        if stop {
            configuration.label.font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.dyn(0x000000, 0xFFFFFF, configuration.isPressed ? 0.10 : 0.06, configuration.isPressed ? 0.12 : 0.08)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        } else { SendLabel(configuration: configuration) }
    }
    private struct SendLabel: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label.font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? Color.white : AppTheme.textHint)
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(enabled ? AnyShapeStyle(configuration.isPressed ? AppTheme.accentDark : AppTheme.accent) : AnyShapeStyle(AppTheme.dyn(0x000000, 0xFFFFFF, 0.06, 0.08))))
        }
    }
}

/// Big card footer / panel secondary buttons: no stroke, black 4% / white 6%, 28 high, r8, 13pt.
struct QuietFillButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 13
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: fontSize)).foregroundStyle(.primary)
            .padding(.horizontal, 12).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(AppTheme.dyn(0x000000, 0xFFFFFF, configuration.isPressed ? 0.08 : 0.04, configuration.isPressed ? 0.10 : 0.06)))
    }
}

/// Big card + bubble surface: thick, high-contrast "mostly solid" glass (material + near-opaque tint).
struct CardSurface<S: Shape>: ViewModifier {
    var shape: S
    var id: String? = nil
    var namespace: Namespace.ID? = nil
    var shadow = true
    var stroke = true
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        let base = content
            .environment(\.cardInk, true)
            .foregroundStyle(Ink.primary)
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [AppTheme.dyn(0xFFFFFF, 0x161B28, 0.94, 0.90), AppTheme.dyn(0xFFFFFF, 0x0C1220, 0.94, 0.82)], startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(shape.stroke(AppTheme.dyn(0x000000, 0xFFFFFF, 0.08, 0.10), lineWidth: dark ? 2 : 1).clipShape(shape).opacity(stroke ? 1 : 0).allowsHitTesting(false))   // inner stroke 1pt / 0.5pt
            .overlay(
                shape.stroke(Color.white.opacity(dark && stroke ? 0.14 : 0), lineWidth: 2).clipShape(shape)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.08)))
                    .allowsHitTesting(false)
            )
        Group {
            if #available(macOS 26.0, *), let id, let namespace {
                base.glassEffect(.clear, in: shape).glassEffectID(id, in: namespace)   // morph identity only
            } else { base }
        }
        .shadow(color: .black.opacity(shadow ? (dark ? 0 : 0.04) : 0), radius: 1, x: 0, y: 0.5)
        .shadow(color: .black.opacity(shadow ? (dark ? 0 : 0.06) : 0), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(shadow ? (dark ? 0.18 : 0.12) : 0), radius: dark ? 8 : 20, x: 0, y: dark ? 3 : 8)
    }
}

// MARK: - Card-scoped ink (big card + bubble only; settings resolve to the normal AppTheme tokens)

private struct CardInkKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var cardInk: Bool { get { self[CardInkKey.self] } set { self[CardInkKey.self] = newValue } }
}

/// Resolves to the card palette inside `CardSurface`, otherwise to the existing token.
struct Ink: ShapeStyle {
    enum Role { case primary, secondary, group, divider, accent, segTrack, segThumb, segStroke }
    var role: Role
    var alpha: Double = 1
    static let primary = Ink(role: .primary), secondary = Ink(role: .secondary), group = Ink(role: .group)
    static let divider = Ink(role: .divider), accent = Ink(role: .accent)
    static let segTrack = Ink(role: .segTrack), segThumb = Ink(role: .segThumb), segStroke = Ink(role: .segStroke)
    func opacity(_ a: Double) -> Ink { Ink(role: role, alpha: alpha * a) }
    func resolve(in env: EnvironmentValues) -> Color {
        let dark = env.colorScheme == .dark
        let c: Color
        if env.cardInk {
            switch role {
            case .primary: c = dark ? .white : Color(red: 0x1D/255, green: 0x1D/255, blue: 0x1F/255)
            case .secondary: c = dark ? .white.opacity(0.62) : .black.opacity(0.60)
            case .group: c = dark ? .white.opacity(0.40) : .black.opacity(0.38)
            case .divider: c = dark ? .white.opacity(0.08) : .black.opacity(0.06)
            case .accent: c = dark ? Color(red: 0x5A/255, green: 0xA2/255, blue: 1) : Color(red: 0x24/255, green: 0x69/255, blue: 0xF3/255)
            case .segTrack: c = dark ? .white.opacity(0.07) : Color(red: 0x76/255, green: 0x76/255, blue: 0x80/255).opacity(0.12)
            case .segThumb: c = dark ? .white.opacity(0.16) : .white
            case .segStroke: c = dark ? .white.opacity(0.20) : .clear
            }
        } else {
            switch role {
            case .primary: c = .primary
            case .secondary: c = AppTheme.textSecondary
            case .group: c = AppTheme.groupTitle
            case .divider: c = AppTheme.rowDivider
            case .accent: c = AppTheme.accent
            case .segTrack: c = AppTheme.dyn(0xEEF0F3, 0x0B1220)
            case .segThumb: c = AppTheme.dyn(0xFFFFFF, 0x1E293B)
            case .segStroke: c = AppTheme.dyn(0xDDE1E7, 0x1E293B)
            }
        }
        return c.opacity(alpha)
    }
}

/// Dialog text inputs: filled, no border (r8).
struct FilledFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 10).frame(height: 30)
            .background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Small round icon buttons (start card 设置/关闭): transparent at rest, 4% on hover, 8% pressed.
struct HoverCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverLabel(configuration: configuration) }
    private struct HoverLabel: View {
        let configuration: Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.08 : hovered ? 0.04 : 0)))
                .contentShape(Circle())
                .onHover { hovered = $0 }
        }
    }
}
