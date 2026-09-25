import Foundation
import SwiftData

struct AudioAnchor: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var time: TimeInterval
    var label: String

    var timeLabel: String { Formatters.clock(time) }
}

struct PDFAttachment: Codable, Hashable {
    var name: String
    var bookmark: Data?

    /// A bookmark can go stale when the file moves or the sandbox changes.
    /// Resolving reports staleness so callers can re-create the bookmark
    /// instead of silently failing to open the document.
    ///
    /// `.withSecurityScope` is macOS-only; iOS documents live inside the app
    /// container and are reachable without a security scope, so the option is
    /// applied only where it exists. `.minimalBookmark` is available on both.
    func resolve() -> (url: URL, wasStale: Bool)? {
        var isStale = false
        var options: URL.BookmarkResolutionOptions = []
        #if os(macOS)
        options.insert(.withSecurityScope)
        #endif
        guard let bookmark,
              let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: options,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return nil }
        return (url, isStale)
    }

    /// Re-captures the bookmark after the caller re-imports the same document.
    mutating func refreshBookmark(for url: URL) {
        var options: URL.BookmarkCreationOptions = .minimalBookmark
        #if os(macOS)
        options.insert(.withSecurityScope)
        #endif
        bookmark = try? url.bookmarkData(options: options,
                                         includingResourceValuesForKeys: nil,
                                         relativeTo: nil)
    }
}

struct NoteAttachment: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var typeIdentifier: String
    var data: Data

    var sizeLabel: String {
        let bytes = Double(data.count)
        let units = ["بايت", "ك.ب", "م.ب", "ج.ب"]
        var value = bytes
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return unit == 0 ? "\(Int(value)) \(units[unit])" : String(format: "%.1f %@", value, units[unit])
    }

    var symbolName: String {
        if typeIdentifier.contains("image") { return "photo" }
        if typeIdentifier.contains("pdf") { return "doc.richtext" }
        if typeIdentifier.contains("audio") { return "waveform" }
        if typeIdentifier.contains("text") { return "doc.text" }
        return "doc"
    }
}

struct Flashcard: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var front: String
    var back: String
    var interval: Int = 0
    var ease: Double = 2.5
    var repetitions: Int = 0
    var dueAt: Date = .now
    var lastReviewedAt: Date?

    var isDue: Bool { dueAt <= .now }
    var isFresh: Bool { repetitions == 0 }
}

struct Note: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var folder: String = "الدراسة"
    var tags: [String] = []
    var drawingData: Data?
    var audioFileName: String?
    var audioDuration: TimeInterval = 0
    var audioAnchors: [AudioAnchor] = []
    var pdf: PDFAttachment?
    var attachments: [NoteAttachment] = []
    var flashcards: [Flashcard] = []
    /// CloudKit sharing metadata. The source note remains local/SwiftData-owned.
    var cloudShareRecordName: String?
    var cloudShareURL: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = .now
    var updatedAt: Date = .now

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "ملاحظة بدون عنوان" : trimmed
    }

    var excerpt: String {
        let collapsed = content
            .replacingOccurrences(of: "[\\*_`#>\\-\\[\\]\\(\\)]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty { return "ابدأ بالكتابة هنا..." }
        return collapsed
    }

    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && drawingData == nil
            && audioFileName == nil
    }

    /// Everything the library and Spotlight search on, in one lowercase blob.
    var searchHaystack: String {
        ([title, content, folder] + tags).joined(separator: " ").lowercased()
    }

    var dueFlashcards: [Flashcard] {
        flashcards.filter(\.isDue)
    }

    var badgeCount: Int {
        var total = 0
        if !flashcards.isEmpty { total += 1 }
        if audioFileName != nil { total += 1 }
        if pdf != nil { total += 1 }
        if !attachments.isEmpty { total += 1 }
        if drawingData != nil { total += 1 }
        return total
    }
}

@Model
final class NoteRecord {
    // Every stored property carries a default and every relationship-free
    // property is either optional or defaulted. CloudKit-backed SwiftData
    // rejects the schema at runtime otherwise: a field that arrives from iCloud
    // without a value has nowhere to land, and the store throws on first fetch
    // instead of failing the build.
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var folder: String = ""
    var tagsJSON: String = "[]"
    var drawingData: Data?
    var audioFileName: String?
    var audioDuration: Double = 0
    var audioAnchorsJSON: String = "[]"
    var pdfName: String?
    var pdfBookmark: Data?
    var attachmentsJSON: String = "[]"
    var flashcardsJSON: String = "[]"
    var cloudShareRecordName: String?
    var cloudShareURL: String?
    var isPinned: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(note: Note) {
        id = note.id
        title = note.title
        content = note.content
        folder = note.folder
        tagsJSON = Self.encode(note.tags)
        drawingData = note.drawingData
        audioFileName = note.audioFileName
        audioDuration = note.audioDuration
        audioAnchorsJSON = Self.encode(note.audioAnchors)
        pdfName = note.pdf?.name
        pdfBookmark = note.pdf?.bookmark
        attachmentsJSON = Self.encode(note.attachments)
        flashcardsJSON = Self.encode(note.flashcards)
        cloudShareRecordName = note.cloudShareRecordName
        cloudShareURL = note.cloudShareURL
        isPinned = note.isPinned
        isArchived = note.isArchived
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    func update(from note: Note) {
        title = note.title
        content = note.content
        folder = note.folder
        tagsJSON = Self.encode(note.tags)
        drawingData = note.drawingData
        audioFileName = note.audioFileName
        audioDuration = note.audioDuration
        audioAnchorsJSON = Self.encode(note.audioAnchors)
        pdfName = note.pdf?.name
        pdfBookmark = note.pdf?.bookmark
        attachmentsJSON = Self.encode(note.attachments)
        flashcardsJSON = Self.encode(note.flashcards)
        cloudShareRecordName = note.cloudShareRecordName
        cloudShareURL = note.cloudShareURL
        isPinned = note.isPinned
        isArchived = note.isArchived
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    func asNote() -> Note {
        Note(
            id: id,
            title: title,
            content: content,
            folder: folder,
            tags: Self.decode(tagsJSON, as: [String].self) ?? [],
            drawingData: drawingData,
            audioFileName: audioFileName,
            audioDuration: audioDuration,
            audioAnchors: Self.decode(audioAnchorsJSON, as: [AudioAnchor].self) ?? [],
            pdf: pdfName.map { PDFAttachment(name: $0, bookmark: pdfBookmark) },
            attachments: Self.decode(attachmentsJSON, as: [NoteAttachment].self) ?? [],
            flashcards: Self.decode(flashcardsJSON, as: [Flashcard].self) ?? [],
            cloudShareRecordName: cloudShareRecordName,
            cloudShareURL: cloudShareURL,
            isPinned: isPinned,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ value: String, as type: T.Type) -> T? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
