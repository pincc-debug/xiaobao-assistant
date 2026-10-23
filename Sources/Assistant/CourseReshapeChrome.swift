import SwiftUI
import AssistantCore

// MARK: - Workbench chrome (课后分析台 · 重塑)

/// 右侧栏「课程产出 / 数据」驱动；面板头不再放资产|分析分段。
enum ReshapeMode: String { case assets = "资产", analysis = "分析" }

struct ReshapeStageTabs: View {
    @Binding var stage: LessonAssetStage
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LessonAssetStage.allCases, id: \.self) { item in
                let on = stage == item
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { stage = item }
                } label: {
                    Text(item.groupTitle)
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? AppTheme.textBody : AppTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? AppTheme.cardBorder : Color.clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppTheme.pageBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(AppTheme.cardBorder, lineWidth: 1))
    }
}

struct ReshapePanelHeader: View {
    var eyebrow: String? = nil
    var title: String
    var subtitle: String?
    /// 资产侧才传；分析/数据页不显示备课·课堂记录·复盘分段。
    var stage: Binding<LessonAssetStage>? = nil
    var trailing: AnyView? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let eyebrow, !eyebrow.isEmpty {
                        Text(eyebrow)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppTheme.textMuted)
                            .tracking(0.6)
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.textStrong)
                        .lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let trailing { trailing }
            }
            // 「资产 | 分析」已去掉：分析页走右侧栏「数据」入口，资产侧只留备课/课堂记录/复盘。
            if let stage {
                ReshapeStageTabs(stage: stage).padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [AppTheme.bgHeaderTop, AppTheme.bgPanel], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.borderDefault).frame(height: 1) }
    }
}

struct ReshapeBadge: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AppTheme.badgeFg)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.badgeBg))
    }
}

struct ReshapeMicroTag: View {
    var text: String
    var warn: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(warn ? AppTheme.dangerBright : AppTheme.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(warn ? AppTheme.dangerBright.opacity(0.45) : AppTheme.chipStroke, lineWidth: 1))
    }
}

struct ReshapeSectionCard<Content: View>: View {
    var title: String
    var color: Color
    var count: Int?
    var emptyHint: String = "暂无"
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(AppTheme.textBody)
                Spacer(minLength: 0)
                if let count { ReshapeBadge(text: "\(count)") }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(AppTheme.bgTileHead)
            .overlay(alignment: .bottom) { Rectangle().fill(AppTheme.borderDefault).frame(height: 1) }
            content()
            if count == 0 {
                Text(emptyHint)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.bgTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.borderDefault, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ReshapeListRow: View {
    var title: String
    var tag: String? = nil
    var warn: Bool = false
    var showsChevron: Bool = true
    var striped: Bool = false
    var action: (() -> Void)? = nil
    var body: some View {
        let row = HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(AppTheme.textBody)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let tag { ReshapeMicroTag(text: tag, warn: warn) }
            if showsChevron {
                Text("›").font(.system(size: 14)).foregroundStyle(AppTheme.textFaint)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 8)
        .background(striped ? AppTheme.rowStripe : Color.clear)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

/// 卡片头像槽：固定尺寸圆角方块。有 Resources/<image>.png 时显示图片，否则显示单字兜底。
struct ReshapeGlyph: View {
    var text: String
    var image: String? = nil
    var bg: Color
    var fg: Color
    var size: CGFloat = 28
    var radius: CGFloat = 8
    private static var cache: [String: NSImage] = [:]
    static func picture(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let hit = cache[name] { return hit }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if let picture = Self.picture(image) {
            Image(nsImage: picture)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(shape)
        } else {
            Text(text)
                .font(.system(size: size > 32 ? 13 : 11, weight: .bold))
                .foregroundStyle(fg)
                .frame(width: size, height: size)
                .background(shape.fill(bg))
        }
    }
}

struct ReshapeDonut: View {
    struct Slice: Identifiable { var id: String { label }; var value: Int; var color: Color; var label: String }
    var slices: [Slice]
    var total: Int { slices.map(\.value).reduce(0, +) }
    var body: some View {
        let safe = max(total, 1)
        ZStack {
            Circle().stroke(AppTheme.borderDefault, lineWidth: 13)
            ForEach(Array(sliceRanges(safe: safe).enumerated()), id: \.offset) { _, item in
                Circle()
                    .trim(from: item.from, to: item.to)
                    .stroke(item.color, style: StrokeStyle(lineWidth: 13, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 1) {
                Text("\(total)")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(AppTheme.textStrong)
                    .monospacedDigit()
                Text("项")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.textBody.opacity(0.7))
            }
        }
        .frame(width: 88, height: 88)
    }
    private func sliceRanges(safe: Int) -> [(from: CGFloat, to: CGFloat, color: Color)] {
        var cursor: CGFloat = 0
        var out: [(CGFloat, CGFloat, Color)] = []
        for slice in slices where slice.value > 0 {
            let next = cursor + CGFloat(slice.value) / CGFloat(safe)
            out.append((cursor, next, slice.color))
            cursor = next
        }
        return out
    }
}

struct ReshapeCompletionArc: View {
    var answered: Int
    var unanswered: Int
    private var total: Int { answered + unanswered }
    private var rate: Double { total == 0 ? 0 : Double(answered) / Double(total) }
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(AppTheme.borderDefault, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: rate)
                    .stroke(AppTheme.accentBright, style: StrokeStyle(lineWidth: 8, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(AppTheme.accentBright)
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("已答 ").font(.system(size: 10)).foregroundStyle(AppTheme.textBody.opacity(0.75))
                + Text("\(answered)").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textBody)
                Text("未答 ").font(.system(size: 10)).foregroundStyle(AppTheme.textBody.opacity(0.75))
                + Text("\(unanswered)").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textBody)
            }
        }
    }
}

struct ReshapeTypeBar: View {
    var single: Int
    var multi: Int
    private var total: Int { max(single + multi, 1) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(AppTheme.typeSingle)
                        .frame(width: geo.size.width * CGFloat(single) / CGFloat(total))
                    Rectangle().fill(AppTheme.typeMulti)
                        .frame(width: geo.size.width * CGFloat(multi) / CGFloat(total))
                }
            }
            .frame(height: 9)
            .clipShape(Capsule())
            HStack {
                Text("单选 ").font(.system(size: 10)).foregroundStyle(AppTheme.textBody.opacity(0.75))
                + Text("\(Int((Double(single) / Double(total) * 100).rounded()))%").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textBody)
                Spacer()
                Text("多选 ").font(.system(size: 10)).foregroundStyle(AppTheme.textBody.opacity(0.75))
                + Text("\(Int((Double(multi) / Double(total) * 100).rounded()))%").font(.system(size: 10, weight: .semibold)).foregroundStyle(AppTheme.textBody)
            }
        }
    }
}

struct ReshapeTrendPlaceholder: View {
    var height: CGFloat = 110
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.placeholderBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            VStack {
                Spacer()
                Rectangle()
                    .fill(AppTheme.placeholderBorder)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 18)
            }
            Text("本场暂无在线数据")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.emptyText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            Canvas { ctx, size in
                let step: CGFloat = 12
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    ctx.stroke(path, with: .color(AppTheme.borderDefault.opacity(0.55)), lineWidth: 6)
                    x += step
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(0.35)
        )
    }
}

struct ReshapeTile<Content: View>: View {
    var title: String
    var meta: String? = nil
    var span2: Bool = false
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.textMuted)
                    .tracking(0.3)
                Spacer(minLength: 0)
                if let meta {
                    Text(meta)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppTheme.textFaint)
                }
            }
            content()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.bgTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.borderDefault, lineWidth: 1))
    }
}

struct ReshapeKPICell: View {
    var title: String
    var value: String
    var warn: Bool = false
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(warn ? AppTheme.dangerBright : AppTheme.textStrong)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(AppTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(AppTheme.bgTile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(AppTheme.borderDefault, lineWidth: 1))
    }
}

struct ReshapeCopyFooter: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(AppTheme.borderDefault).frame(height: 1)
            Button(action: action) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(AppTheme.textMuted, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(AppTheme.borderDefault)
                                .frame(width: 12, height: 12)
                                .offset(x: 3, y: 3)
                        )
                        .frame(width: 16, height: 16)
                    Text("复制为新课程")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(AppTheme.link)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(AppTheme.bgPanel)
    }
}
