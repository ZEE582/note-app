import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(CoreText)
import CoreText
#endif

import UIKit

enum NoteExportFormat: String, CaseIterable, Identifiable {
    case markdown
    case pdf
    case html

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markdown: return "Markdown"
        case .pdf: return "PDF"
        case .html: return "HTML"
        }
    }

    /// Markdown has no system UTType, and one cannot be declared here under the
    /// name `markdown` either: that would collide with this enum's own
    /// `markdown` case. Hence the distinct name, which the cases below refer
    /// to instead of the ambiguous bare `.markdown`.
    static let markdownType = UTType(exportedAs: "com.mynotes.app.markdown")

    var contentType: UTType {
        switch self {
        case .markdown: return NoteExportFormat.markdownType
        case .pdf: return UTType.pdf
        case .html: return UTType.html
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .pdf: return "pdf"
        case .html: return "html"
        }
    }
}

enum NoteExporter {

    // MARK: - Shared blocks

    private static func metadataLines(for note: Note) -> [(String, String)] {
        var rows: [(String, String)] = [("المجلد", note.folder)]
        if !note.tags.isEmpty {
            rows.append(("الوسوم", note.tags.map { "#\($0)" }.joined(separator: " ")))
        }
        rows.append(("آخر تعديل", Formatters.medium(note.updatedAt)))
        if !note.flashcards.isEmpty {
            rows.append(("البطاقات", "\(note.flashcards.count) بطاقة"))
        }
        if note.audioDuration > 0 {
            rows.append(("مدة التسجيل", Formatters.clock(note.audioDuration)))
        }
        if !note.attachments.isEmpty {
            rows.append(("المرفقات", "\(note.attachments.count) ملف"))
        }
        if let pdf = note.pdf {
            rows.append(("ملف مرفق", pdf.name))
        }
        return rows
    }

    // MARK: - Markdown

    static func markdown(for note: Note) -> String {
        var result = "# \(note.displayTitle)\n\n"

        result += "| المعلومات | التفاصيل |\n"
        result += "|-----------|----------|\n"
        for (label, value) in metadataLines(for: note) {
            result += "| **\(label)** | \(escapeMarkdownCell(value)) |\n"
        }
        result += "\n"

        result += "## المحتوى\n\n"
        result += note.content.isEmpty ? "_لا يوجد محتوى._" : note.content
        result += "\n\n"

        if !note.audioAnchors.isEmpty {
            result += "---\n\n## 🎙️ لحظات المحاضرة\n\n"
            for anchor in note.audioAnchors {
                result += "- `\(anchor.timeLabel)` — \(anchor.label)\n"
            }
            if note.audioDuration > 0 {
                result += "\n*المدة الإجمالية: \(Formatters.clock(note.audioDuration))*\n"
            }
            result += "\n"
        }

        if !note.flashcards.isEmpty {
            result += "---\n\n## 📚 بطاقات الاستذكار (\(note.flashcards.count))\n\n"
            for (index, card) in note.flashcards.enumerated() {
                result += "### البطاقة \(index + 1)\n\n"
                result += "**السؤال:** \(card.front)\n\n"
                result += "**الإجابة:** \(card.back)\n\n"
                if card.repetitions > 0 {
                    result += "*التكرار: \(card.repetitions) | الفاصل: \(card.interval) يوم | السهولة: \(String(format: "%.1f", card.ease))*\n\n"
                }
            }
        }

        if !note.attachments.isEmpty {
            result += "---\n\n## 📎 المرفقات (\(note.attachments.count))\n\n"
            for attachment in note.attachments {
                result += "- **\(attachment.name)** — \(attachment.sizeLabel) (`\(attachment.typeIdentifier)`)\n"
            }
            result += "\n"
        }

        if let pdf = note.pdf {
            result += "---\n\n## 📄 ملف PDF مرفق\n\n**\(pdf.name)**\n\n"
        }

        result += "---\n\n*تم التصدير من MyNotes · \(Formatters.medium(.now))*\n"
        return result
    }

    /// A literal `|` inside a Markdown table cell breaks the row, so pipes are
    /// escaped and newlines collapsed before the value is written.
    private static func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    // MARK: - HTML

    static func html(for note: Note) -> String {
        let title = escapeHTML(note.displayTitle)

        var metadata = ""
        for (label, value) in metadataLines(for: note) {
            metadata += """
                    <div class="metadata-item">
                        <span class="metadata-label">\(escapeHTML(label)):</span>
                        <span>\(escapeHTML(value))</span>
                    </div>

            """
        }

        var cards = ""
        if !note.flashcards.isEmpty {
            cards = "<div class=\"section\"><div class=\"section-title\">📚 بطاقات الاستذكار (\(note.flashcards.count))</div>"
            for card in note.flashcards {
                cards += "<div class=\"card\">"
                cards += "<div class=\"card-question\">س: \(escapeHTML(card.front))</div>"
                cards += "<div class=\"card-answer\">ج: \(escapeHTML(card.back))</div>"
                if card.repetitions > 0 {
                    cards += "<div class=\"card-meta\">التكرار: \(card.repetitions) | الفاصل: \(card.interval) يوم | السهولة: \(String(format: "%.1f", card.ease))</div>"
                }
                cards += "</div>"
            }
            cards += "</div>"
        }

        var anchors = ""
        if !note.audioAnchors.isEmpty {
            anchors = "<div class=\"section\"><div class=\"section-title\">🎙️ لحظات المحاضرة</div>"
            for anchor in note.audioAnchors {
                anchors += "<div class=\"anchor\"><span class=\"chip\">⏱️ \(anchor.timeLabel)</span><span>\(escapeHTML(anchor.label))</span></div>"
            }
            if note.audioDuration > 0 {
                anchors += "<div class=\"card-meta\">المدة الإجمالية: \(Formatters.clock(note.audioDuration))</div>"
            }
            anchors += "</div>"
        }

        var attachments = ""
        if !note.attachments.isEmpty {
            attachments = "<div class=\"section\"><div class=\"section-title\">📎 المرفقات (\(note.attachments.count))</div>"
            for attachment in note.attachments {
                attachments += "<div class=\"anchor\"><span class=\"chip\">\(escapeHTML(attachment.sizeLabel))</span><span>\(escapeHTML(attachment.name))</span></div>"
            }
            attachments += "</div>"
        }

        var pdfBlock = ""
        if let pdf = note.pdf {
            pdfBlock = "<div class=\"section\"><div class=\"section-title\">📄 ملف PDF مرفق</div>"
            pdfBlock += "<div class=\"anchor\"><span>\(escapeHTML(pdf.name))</span></div></div>"
        }

        var tags = ""
        if !note.tags.isEmpty {
            tags = note.tags
                .map { "<span class=\"tag\">\(escapeHTML($0))</span>" }
                .joined(separator: " ")
        }

        return """
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    line-height: 1.75;
                    color: #2f2d3d;
                    background: #f4f3f8;
                    padding: 24px;
                }
                .container {
                    max-width: 860px;
                    margin: 0 auto;
                    background: #fff;
                    padding: 40px;
                    border-radius: 18px;
                    box-shadow: 0 8px 32px rgba(0,0,0,0.08);
                }
                h1 {
                    font-size: 2.1em;
                    border-bottom: 3px solid #6C63FF;
                    padding-bottom: 14px;
                    margin-bottom: 20px;
                }
                .metadata {
                    background: #f7f6fc;
                    padding: 16px;
                    border-radius: 12px;
                    border-right: 4px solid #6C63FF;
                    margin-bottom: 24px;
                }
                .metadata-item { margin: 6px 0; font-size: 0.95em; }
                .metadata-label { font-weight: 700; color: #5b5872; }
                .content {
                    font-size: 1.05em;
                    line-height: 1.9;
                    white-space: pre-wrap;
                    word-break: break-word;
                    margin: 24px 0;
                }
                .section { margin: 26px 0; padding: 18px; background: #f7f6fc; border-radius: 12px; }
                .section-title {
                    font-size: 1.25em;
                    color: #6C63FF;
                    font-weight: 700;
                    margin-bottom: 12px;
                }
                .card {
                    background: #fff;
                    padding: 14px;
                    margin: 8px 0;
                    border-radius: 10px;
                    border: 1px solid #e4e2f0;
                }
                .card-question { font-weight: 700; margin-bottom: 6px; }
                .card-answer { color: #55525f; }
                .card-meta { font-size: 0.85em; color: #8b88a0; margin-top: 8px; }
                .anchor { display: flex; gap: 10px; align-items: center; padding: 10px; background: #fff; border-radius: 8px; margin: 6px 0; }
                .chip { background: #6C63FF; color: #fff; border-radius: 999px; padding: 2px 10px; font-size: 0.8em; white-space: nowrap; }
                .tag { display: inline-block; background: #6C63FF; color: #fff; padding: 3px 12px; border-radius: 999px; font-size: 0.85em; margin: 4px 4px 0 0; }
                .footer { text-align: center; margin-top: 36px; padding-top: 18px; border-top: 1px solid #e4e2f0; color: #8b88a0; font-size: 0.9em; }
                @media (max-width: 600px) { body { padding: 12px; } .container { padding: 20px; } h1 { font-size: 1.5em; } }
                @media print { body { background: #fff; padding: 0; } .container { box-shadow: none; } }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>\(title)</h1>

                <div class="metadata">
        \(metadata)    </div>

                \(tags.isEmpty ? "" : "<div style=\"margin-bottom:20px\">\(tags)</div>")

                <div class="content">
        \(escapeHTML(note.content))
                </div>

        \(cards)
        \(anchors)
        \(attachments)
        \(pdfBlock)

                <div class="footer">
                    <p>تم التصدير من MyNotes</p>
                    <p>\(Formatters.medium(.now))</p>
                </div>
            </div>
        </body>
        </html>

        """
    }

    /// Note content and titles are user text injected straight into a document
    /// body, so every interpolation above goes through this first.
    static func escapeHTML(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    // MARK: - PDF

    static func pdf(for note: Note) -> Data {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 48
        let contentRect = CGRect(x: margin, y: margin,
                                  width: pageSize.width - margin * 2,
                                  height: pageSize.height - margin * 2)
        let body = pdfBody(for: note)
        let ranges = pageRanges(for: body, in: contentRect)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for range in ranges {
                context.beginPage()
                draw(range: range, of: body, in: contentRect, context: context.cgContext)
            }
        }
    }

    /// Splits the attributed string into the character ranges that fit one
    /// page each. The previous implementation emitted a single page and let
    /// CoreText clip everything after the first fold.
    private static func pageRanges(for body: NSAttributedString, in rect: CGRect) -> [CFRange] {
        #if canImport(CoreText)
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        let path = CGPath(rect: CGRect(x: rect.minX, y: 0,
                                       width: rect.width, height: rect.height),
                          transform: nil)
        var ranges: [CFRange] = []
        var consumed = 0
        // Bounded so a pathological layout can never spin forever.
        for _ in 0..<200 {
            guard consumed < body.length else { break }
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(consumed, 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            if visible.length <= 0 { break }
            ranges.append(CFRangeMake(consumed, visible.length))
            consumed += visible.length
        }
        return ranges.isEmpty ? [CFRangeMake(0, body.length)] : ranges
        #else
        return [CFRangeMake(0, body.length)]
        #endif
    }

    private static func draw(range: CFRange,
                             of body: NSAttributedString,
                             in rect: CGRect,
                             context cgContext: CGContext) {
        #if canImport(CoreText)
        let framesetter = CTFramesetterCreateWithAttributedString(body)
        let path = CGPath(rect: CGRect(x: rect.minX, y: 0,
                                       width: rect.width, height: rect.height),
                          transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
        cgContext.saveGState()
        cgContext.textMatrix = .identity
        cgContext.translateBy(x: 0, y: rect.minY + rect.height)
        cgContext.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, cgContext)
        cgContext.restoreGState()
        #else
        let substring = NSRange(location: range.location, length: range.length)
        body.attributedSubstring(from: substring).draw(in: rect)
        #endif
    }

    private static func pdfBody(for note: Note) -> NSMutableAttributedString {
        let body = NSMutableAttributedString()
        // UIKit, not AppKit: the macOS branch is gone and the PDF renderer
        // draws into a UIKit context.
        let titleFont = UIFont.boldSystemFont(ofSize: 24)
        let sectionFont = UIFont.boldSystemFont(ofSize: 15)
        let bodyFont = UIFont.systemFont(ofSize: 13)
        let metaFont = UIFont.systemFont(ofSize: 11)

        func append(_ text: String, font: UIFont, color: UIColor = .label, spacing: CGFloat = 4) {
            body.append(NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle(spacing: spacing)
            ]))
        }

        append(note.displayTitle, font: titleFont, spacing: 10)

        for (label, value) in metadataLines(for: note) {
            body.append(NSAttributedString(string: "\(label): ", attributes: [
                .font: metaFont,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle(spacing: 2)
            ]))
            body.append(NSAttributedString(string: "\(value)\n", attributes: [
                .font: metaFont,
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraphStyle(spacing: 2)
            ]))
        }
        append("\n", font: bodyFont, spacing: 8)

        if !note.content.isEmpty {
            append(note.content, font: bodyFont, spacing: 8)
        }

        if !note.audioAnchors.isEmpty {
            append("\nلحظات المحاضرة", font: sectionFont, spacing: 6)
            for anchor in note.audioAnchors {
                append("• \(anchor.timeLabel) — \(anchor.label)", font: bodyFont, spacing: 2)
            }
        }

        if !note.flashcards.isEmpty {
            append("\nبطاقات الاستذكار (\(note.flashcards.count))", font: sectionFont, spacing: 6)
            for (index, card) in note.flashcards.enumerated() {
                append("\(index + 1). \(card.front)", font: sectionFont, spacing: 2)
                append("   \(card.back)", font: bodyFont, spacing: 6)
            }
        }

        if !note.attachments.isEmpty {
            append("\nالمرفقات", font: sectionFont, spacing: 6)
            for attachment in note.attachments {
                append("• \(attachment.name) — \(attachment.sizeLabel)", font: bodyFont, spacing: 2)
            }
        }

        if let pdf = note.pdf {
            append("\nملف PDF مرفق", font: sectionFont, spacing: 6)
            append("• \(pdf.name)", font: bodyFont, spacing: 2)
        }

        append("\nتم التصدير من MyNotes · \(Formatters.medium(.now))",
               font: metaFont,
               color: UIColor.secondaryLabel,
               spacing: 0)
        return body
    }

    private static func paragraphStyle(spacing: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        style.paragraphSpacing = spacing
        return style
    }
}

// MARK: - FileDocument

struct NoteExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [NoteExportFormat.markdownType, .pdf, .html] }

    let data: Data
    let format: NoteExportFormat

    init(note: Note, format: NoteExportFormat) {
        self.format = format
        switch format {
        case .markdown:
            data = Data(NoteExporter.markdown(for: note).utf8)
        case .pdf:
            data = NoteExporter.pdf(for: note)
        case .html:
            data = Data(NoteExporter.html(for: note).utf8)
        }
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        format = .markdown
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
