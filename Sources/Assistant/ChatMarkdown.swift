import SwiftUI

struct ChatMarkdownBlock: Equatable {
    enum Kind: Equatable { case paragraph, heading(Int), quote, list(String), code, table, rule }
    var kind: Kind
    var text: String
    static func parse(_ source: String) -> [Self] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [Self] = [], paragraph: [String] = [], code: [String]? = nil
        func flush() { if !paragraph.isEmpty { blocks.append(.init(kind: .paragraph, text: paragraph.joined(separator: "\n"))); paragraph = [] } }
        var i = 0
        while i < lines.count {
            let line = lines[i], trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if let content = code { blocks.append(.init(kind: .code, text: content.joined(separator: "\n"))); code = nil } else { code = [] }
            } else if code != nil { code?.append(line) }
            else if trimmed.isEmpty { flush() }
            else if i + 1 < lines.count, trimmed.contains("|"), isTableSeparator(lines[i+1]) {
                flush(); var rows = [line]; i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty { rows.append(lines[i]); i += 1 }
                blocks.append(.init(kind: .table, text: rows.joined(separator: "\n"))); continue
            } else if ["---", "***", "___"].contains(trimmed) { flush(); blocks.append(.init(kind: .rule, text: "")) }
            else if let range = trimmed.range(of: #"^#{1,6} "#, options: .regularExpression) {
                flush(); blocks.append(.init(kind: .heading(trimmed[range].count-1), text: String(trimmed[range.upperBound...])))
            } else if trimmed.hasPrefix("> ") { flush(); blocks.append(.init(kind: .quote, text: String(trimmed.dropFirst(2)))) }
            else if let range = trimmed.range(of: #"^(?:[-*+] |[0-9]+[.)] )"#, options: .regularExpression) {
                flush(); let marker = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                blocks.append(.init(kind: .list(marker.count == 1 ? "•" : marker), text: String(trimmed[range.upperBound...])))
            } else { paragraph.append(line) }
            i += 1
        }
        flush(); if let code { blocks.append(.init(kind: .code, text: code.joined(separator: "\n"))) }
        return blocks
    }
    static func cells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }; if value.hasSuffix("|") { value.removeLast() }
        return value.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    private static func isTableSeparator(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy { $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }
    }
}

/// Native text only: no HTML execution or remote image loading.
struct ChatMarkdown: View {
    var text: String
    private func inline(_ value: String) -> Text {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(ChatMarkdownBlock.parse(text).enumerated()), id: \.offset) { _, block in
                switch block.kind {
                case .paragraph: inline(block.text)
                case .heading(let level): inline(block.text).font(.system(size: level == 1 ? 20 : level == 2 ? 15 : 13, weight: .semibold)).padding(.top, 3)
                case .quote: HStack(alignment: .top, spacing: 9) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 3); inline(block.text).foregroundStyle(AppTheme.textSecondary) }.fixedSize(horizontal: false, vertical: true)
                case .list(let marker): HStack(alignment: .top, spacing: 7) { Text(marker).frame(minWidth: 14, alignment: .trailing); inline(block.text) }
                case .code: ScrollView(.horizontal) { Text(block.text).font(.system(size: 13, design: .monospaced)).padding(10) }.background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 6))
                case .rule: Divider()
                case .table:
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            ForEach(Array(block.text.components(separatedBy: "\n").enumerated()), id: \.offset) { row, line in
                                GridRow { ForEach(Array(ChatMarkdownBlock.cells(line).enumerated()), id: \.offset) { _, cell in inline(cell).fontWeight(row == 0 ? .semibold : .regular).frame(maxWidth: 260, alignment: .leading) } }
                            }
                        }.padding(10)
                    }.background(AppTheme.inputFill, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }.font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded })
    }
}
