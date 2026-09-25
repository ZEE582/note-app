import SwiftUI

/// Review sheet for one note's flashcards.
///
/// The queue is snapshotted into `@State` on appear. Earlier versions derived
/// the card list from the live note on every access, so grading a card mutated
/// the very array being indexed and the session could skip or repeat cards.
struct FlashcardsReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Note
    @State private var queue: [UUID] = []
    @State private var position = 0
    @State private var revealed = false
    @State private var scope: ReviewScope = .due
    @State private var reviewedCount = 0
    @State private var cardToDelete: UUID?

    let onChange: (Note) -> Void

    enum ReviewScope: String, CaseIterable, Identifiable {
        case due = "المستحقة"
        case all = "الكل"
        var id: String { rawValue }
    }

    init(note: Note, onChange: @escaping (Note) -> Void = { _ in }) {
        _draft = State(initialValue: note)
        self.onChange = onChange
    }

    // MARK: - Derived queue

    private var eligible: [Flashcard] {
        switch scope {
        case .due: return draft.flashcards.filter(\.isDue)
        case .all: return draft.flashcards
        }
    }

    private var totalInScope: Int { eligible.count }

    private var current: Flashcard? {
        guard queue.indices.contains(position) else { return nil }
        return draft.flashcards.first { $0.id == queue[position] }
    }

    private var isFinished: Bool { current == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                header

                if isFinished {
                    completionView
                } else {
                    cardView
                    Spacer(minLength: 0)
                }
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .navigationTitle("مراجعة البطاقات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إغلاق") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { addCard() } label: {
                            Label("بطاقة جديدة", systemImage: "plus")
                        }
                        Button { deleteAllReviewed() } label: {
                            Label("حذف كل البطاقات", systemImage: "trash")
                        }
                        .disabled(draft.flashcards.isEmpty)
                    } label: {
                        Label("خيارات", systemImage: "ellipsis.circle")
                    }
                }
            }
            .onAppear(perform: rebuildQueue)
            .onChange(of: scope) { rebuildQueue() }
            .alert("حذف البطاقة؟", isPresented: Binding(
                get: { cardToDelete != nil },
                set: { if !$0 { cardToDelete = nil } }
            )) {
                Button("حذف", role: .destructive) { deleteCard(cardToDelete) }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("ستُحذف هذه البطاقة من الملاحظة نهائيًا.")
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 10) {
            Picker("نطاق المراجعة", selection: $scope) {
                ForEach(ReviewScope.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                ProgressView(value: progress)
                    .tint(AppTheme.brand)
                Text(positionLabel)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progress: Double {
        guard totalInScope > 0 else { return 1 }
        return min(1, Double(reviewedCount) / Double(totalInScope))
    }

    private var positionLabel: String {
        guard totalInScope > 0 else { return "0 / 0" }
        return "\(min(position + 1, totalInScope)) / \(totalInScope)"
    }

    private var cardView: some View {
        VStack(spacing: 16) {
            if let current {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { revealed.toggle() }
                } label: {
                    VStack(spacing: 14) {
                        HStack {
                            Label(revealed ? "الإجابة" : "السؤال", systemImage: revealed ? "lightbulb.fill" : "questionmark.circle.fill")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(AppTheme.brand)
                            Spacer()
                            if !current.isFresh {
                                Text("تكرار \(current.repetitions)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(revealed ? current.back : current.front)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 140)
                            .padding(.vertical, 8)

                        Text(revealed ? "اضغط للعودة إلى السؤال" : "اضغط لعرض الإجابة")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .cardSurface(padding: 20, radius: 24)
                }
                .buttonStyle(.plain)

                if revealed {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ReviewQuality.allCases, id: \.self) { quality in
                            Button {
                                review(quality)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: quality.symbolName).font(.headline)
                                    Text(quality.label).font(.subheadline.weight(.bold))
                                    Text(quality.hint).font(.caption2).opacity(0.85)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(.white)
                                .background(quality.tint, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    HStack(spacing: 10) {
                        Button {
                            if let current { cardToDelete = current.id }
                        } label: {
                            Label("حذف البطاقة", systemImage: "trash")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.danger)
                    }
                }
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.success)
            Text(reviewedCount > 0 ? "أحسنت، أنهيت المراجعة" : "لا توجد بطاقات في هذا النطاق")
                .font(.title3.weight(.heavy))
                .multilineTextAlignment(.center)
            Text(reviewedCount > 0
                 ? "راجعت \(Formatters.count(reviewedCount)). البطاقات المستحقة ستعود لاحقًا حسب جدول التكرار المتباعد."
                 : "يمكنك توليد بطاقات من محتوى الملاحظة أو إضافة بطاقات يدوية.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                if totalInScope > 0 {
                    Button {
                        reviewedCount = 0
                        rebuildQueue()
                    } label: {
                        Label("إعادة المراجعة", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
                Button("تم") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func rebuildQueue() {
        position = 0
        revealed = false
        reviewedCount = 0
        queue = eligible.map(\.id)
    }

    private func review(_ quality: ReviewQuality) {
        guard let current,
              let index = draft.flashcards.firstIndex(where: { $0.id == current.id }) else { return }
        draft.flashcards[index] = SpacedRepetition.review(current, quality: quality)
        commit()
        reviewedCount += 1
        // The queue is a stable list of identifiers, so grading a card can
        // never shift the array we are walking.
        position = min(position + 1, queue.count)
        revealed = false
    }

    private func addCard() {
        draft.flashcards.append(Flashcard(front: "سؤال جديد", back: "أدخل الإجابة"))
        commit()
        rebuildQueue()
    }

    private func deleteCard(_ id: UUID?) {
        guard let id else { return }
        draft.flashcards.removeAll { $0.id == id }
        cardToDelete = nil
        commit()
        rebuildQueue()
    }

    private func deleteAllReviewed() {
        draft.flashcards.removeAll()
        commit()
        rebuildQueue()
    }

    private func commit() {
        draft.updatedAt = .now
        onChange(draft)
    }
}

extension ReviewQuality {
    var label: String {
        switch self {
        case .again: return "مرة أخرى"
        case .hard: return "صعب"
        case .good: return "جيد"
        case .easy: return "سهل"
        }
    }

    var hint: String {
        switch self {
        case .again: return "بعد ١٠ دقائق"
        case .hard: return "أقرب موعد"
        case .good: return "الجدول المعتاد"
        case .easy: return "أطول فترة"
        }
    }

    var symbolName: String {
        switch self {
        case .again: return "arrow.counterclockwise"
        case .hard: return "tortoise"
        case .good: return "checkmark"
        case .easy: return "bolt"
        }
    }

    var tint: Color {
        switch self {
        case .again: return AppTheme.danger
        case .hard: return AppTheme.warning
        case .good: return AppTheme.success
        case .easy: return AppTheme.brand
        }
    }
}
