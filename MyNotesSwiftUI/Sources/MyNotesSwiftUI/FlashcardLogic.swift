import Foundation

// MARK: - Generation

enum FlashcardGenerator {
    /// Line count ceiling so one long note cannot generate an unusable pile.
    static let maximumCards = 20

    /// Turns note content into flashcards. Lines that look like
    /// `term: definition` or `term - definition` become real question/answer
    /// pairs; other prose becomes a recall prompt for the whole line.
    static func generate(from content: String) -> [Flashcard] {
        var inCodeFence = false
        var cards: [Flashcard] = []

        for rawLine in content.components(separatedBy: .newlines) {
            if cards.count >= maximumCards { break }

            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeFence.toggle()
                continue
            }
            if inCodeFence { continue }
            guard isProseLine(line) else { continue }

            let body = line
                .replacingOccurrences(of: #"^\s{0,4}([-*•]|\d+[.)])\s+"#,
                                      with: "",
                                      options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard body.count >= 8 else { continue }

            cards.append(makeCard(from: body))
        }
        return cards
    }

    /// Skips structural Markdown that is not worth a flashcard: headings,
    /// table rows, block quotes, and link/image-only lines.
    private static func isProseLine(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if line.hasPrefix("#") { return false }
        if line.hasPrefix(">") { return false }
        if line.hasPrefix("|") || line.hasPrefix("---") { return false }
        if line.range(of: #"^\s*(!?\[[^\]]*\]\([^)]*\)\s*)+$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static let separators = [":", "：", "=", "–", "—", "-"]

    private static func makeCard(from line: String) -> Flashcard {
        guard let split = separators.compactMap({ line.firstRange(of: $0) })
            .min(by: { $0.lowerBound < $1.lowerBound }),
              split.lowerBound > line.startIndex,
              split.upperBound < line.endIndex else {
            return Flashcard(front: "ما الفكرة الأساسية في: \(String(line.prefix(70)))؟", back: line)
        }

        let front = String(line[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
        let back = String(line[split.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard front.count >= 2, !back.isEmpty else {
            return Flashcard(front: "ما الفكرة الأساسية في: \(String(line.prefix(70)))؟", back: line)
        }
        return Flashcard(front: front, back: back)
    }
}

// MARK: - Scheduling

/// A compact SM-2 style scheduler. `again` resets the card and re-queues it in
/// ten minutes, `hard` grows the interval more slowly than `good`, and `easy`
/// gets the usual bonus on top of the base interval.
enum SpacedRepetition {
    static let minimumEase = 1.3
    static let relearnDelay: TimeInterval = 10 * 60
    /// Uncapped SM-2 intervals run away to decades after a dozen easy
    /// answers, which makes the card effectively unreviewable. One year is the
    /// usual ceiling and keeps the queue meaningful.
    static let maximumInterval = 365

    static func review(_ card: Flashcard, quality: ReviewQuality) -> Flashcard {
        var result = card
        result.lastReviewedAt = .now

        switch quality {
        case .again:
            result.interval = 0
            result.repetitions = 0
            result.ease = max(minimumEase, result.ease - 0.2)
            result.dueAt = .now.addingTimeInterval(relearnDelay)
        case .hard, .good, .easy:
            result.repetitions += 1
            result.ease = max(minimumEase, result.ease + easeDelta(for: quality))
            let base = intervalFor(repetitions: result.repetitions,
                                   previous: result.interval,
                                   ease: result.ease,
                                   quality: quality)
            result.interval = min(maximumInterval, base)
            result.dueAt = .now.addingTimeInterval(Double(result.interval) * 24 * 60 * 60)
        }
        return result
    }

    private static func easeDelta(for quality: ReviewQuality) -> Double {
        switch quality {
        case .again: return -0.2
        case .hard: return -0.15
        case .good: return 0
        case .easy: return 0.15
        }
    }

    private static func intervalFor(repetitions: Int, previous: Int, ease: Double, quality: ReviewQuality) -> Int {
        switch repetitions {
        case 1: return 1
        case 2: return quality == .hard ? 2 : 3
        default:
            let grown = Int((Double(max(1, previous)) * ease).rounded())
            let base = max(1, grown)
            switch quality {
            case .hard: return max(1, Int(Double(base) * 0.8))
            case .easy: return max(base + 1, Int(Double(base) * 1.3))
            case .again, .good: return base
            }
        }
    }
}

enum ReviewQuality: String, CaseIterable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: String { rawValue }
}
