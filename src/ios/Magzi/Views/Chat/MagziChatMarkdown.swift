import SwiftUI
import UIKit

/// Lightweight markdown for Magzi replies: inline markdown via `AttributedString`, fenced code blocks,
/// headings and bullets. Optionally appends the inline mint streaming dot after the last character.
struct MagziChatMarkdownText: View {
    let text: String
    var showsStreamingDot = false

    var body: some View {
        let blocks = MagziChatMarkdownParser.blocks(from: text)
        VStack(alignment: .leading, spacing: MagziDesign.Spacing.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isLast = index == blocks.count - 1
                switch block {
                case .text(let string):
                    textView(string, dot: isLast && showsStreamingDot)
                case .code(let language, let code):
                    MagziChatCodeBlock(language: language, code: code)
                    if isLast && showsStreamingDot { streamingDot }
                }
            }
            if blocks.isEmpty && showsStreamingDot { streamingDot }
        }
    }

    private func textView(_ string: String, dot: Bool) -> some View {
        let base = Text(MagziChatMarkdownParser.attributed(string))
        let full = dot ? base + Text(" ") + Self.dotText : base
        return full
            .font(MagziDesign.Typography.body)
            .foregroundColor(MagziDesign.label)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private static var dotText: Text {
        Text(Image(systemName: "circle.fill"))
            .font(.system(size: 6))
            .foregroundColor(MagziDesign.mint)
            .baselineOffset(2)
    }

    private var streamingDot: some View {
        Circle().fill(MagziDesign.mint).frame(width: 6, height: 6)
    }
}

enum MagziChatMarkdownParser {
    enum Block: Hashable {
        case text(String)
        case code(language: String?, code: String)
    }

    static func blocks(from raw: String) -> [Block] {
        var blocks: [Block] = []
        var buffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushText() {
            let joined = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !joined.isEmpty { blocks.append(.text(joined)) }
            buffer = []
        }

        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
                    codeBuffer = []
                    codeLanguage = nil
                    inCode = false
                } else {
                    flushText()
                    let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
                continue
            }
            if inCode { codeBuffer.append(line) } else { buffer.append(line) }
        }
        if inCode {
            // Unterminated fence while streaming: still show it as code.
            blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
        }
        flushText()
        return blocks
    }

    static func attributed(_ string: String) -> AttributedString {
        let prepared = string
            .components(separatedBy: "\n")
            .map(prepareLine)
            .joined(separator: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(string)
    }

    /// Block-level syntax that inline parsing would show literally.
    private static func prepareLine(_ line: String) -> String {
        let leading = line.prefix { $0 == " " }
        let body = line.dropFirst(leading.count)
        if let range = body.range(of: "^#{1,6} +", options: .regularExpression) {
            let title = body[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? "" : "**\(title)**"
        }
        if body.hasPrefix("- ") || body.hasPrefix("* ") || body.hasPrefix("+ ") {
            return "\(leading)\u{2022} " + body.dropFirst(2)
        }
        if body == "---" || body == "***" { return "" }
        return line
    }
}

private struct MagziChatCodeBlock: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.isEmpty ? " " : code)
                    .font(MagziDesign.Typography.mono)
                    .foregroundStyle(MagziDesign.label)
                    .fixedSize(horizontal: true, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, MagziDesign.Spacing.m)
                    .padding(.vertical, MagziDesign.Spacing.m)
                    .padding(.trailing, 28)
            }
            Button {
                UIPasteboard.general.string = code
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(copied ? MagziDesign.mint : MagziDesign.labelSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy code")
            .padding(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MagziDesign.surfaceSecondary)
        )
    }
}
