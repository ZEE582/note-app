import Foundation

#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
import PencilKit
import UIKit
import Vision

enum SpotlightIndexer {
    private static let index = CSSearchableIndex.default()
    private static let domain = "com.mynotes.notes"

    static func index(_ note: Note) {
        index(note, handwriting: nil)
        recognizeHandwriting(in: note)
    }

    private static func index(_ note: Note, handwriting: String?) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = note.title.isEmpty ? "ملاحظة بدون عنوان" : note.title
        let handwritingText = handwriting?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        attributes.contentDescription = [note.content, handwritingText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        attributes.keywords = [note.folder] + note.tags
        attributes.relatedUniqueIdentifier = note.id.uuidString
        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domain,
            attributeSet: attributes
        )
        index.indexSearchableItems([item])
    }

    private static func recognizeHandwriting(in note: Note) {
        guard let data = note.drawingData,
              let drawing = try? PKDrawing(data: data),
              !drawing.bounds.isEmpty else { return }

        let bounds = drawing.bounds.insetBy(dx: -20, dy: -20)
        guard let image = drawing.image(from: bounds, scale: 2).cgImage else { return }
        let request = VNRecognizeTextRequest { request, _ in
            let text = (request.results as? [VNRecognizedTextObservation] ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            guard !text.isEmpty else { return }
            Task { @MainActor in
                index(note, handwriting: text)
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ar", "en-US"]

        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        }
    }

    static func remove(noteID: UUID) {
        index.deleteSearchableItems(withIdentifiers: [noteID.uuidString])
    }

    static func removeAll() {
        index.deleteSearchableItems(withDomainIdentifiers: [domain])
    }
}
#else
enum SpotlightIndexer {
    static func index(_ note: Note) {}
    static func remove(noteID: UUID) {}
    static func removeAll() {}
}
#endif
