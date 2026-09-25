import Foundation
import SwiftUI
#if canImport(Combine)
import Combine
#endif
import SwiftData
import Network

@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    @Published private(set) var syncStatus: SyncStatus = .local
    @Published private(set) var storageError: String?
    @Published private(set) var isOffline = false
    @Published private(set) var activeCollaborators: [CloudKitCollaboration.CollaboratorInfo] = []
    @Published private(set) var hasUnsyncedChanges = false
    /// Text of the transient banner shown above the library. Cleared by the view.
    @Published private(set) var banner: Banner?

    struct Banner: Identifiable, Equatable {
        enum Kind { case info, success, warning, failure }
        let id = UUID()
        let kind: Kind
        let message: String

        var symbolName: String {
            switch kind {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            }
        }

        var tint: Color {
            switch kind {
            case .info: return AppTheme.brand
            case .success: return AppTheme.success
            case .warning: return AppTheme.warning
            case .failure: return AppTheme.danger
            }
        }
    }

    let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.mynotes.network")
    #if canImport(Combine)
    private var cancellables = Set<AnyCancellable>()
    #endif

    enum SyncStatus: Equatable {
        case cloud
        case local

        var label: String {
            switch self {
            case .cloud: return "مزامنة iCloud مفعلة"
            case .local: return "تخزين محلي"
            }
        }

        var symbolName: String {
            switch self {
            case .cloud: return "icloud.and.arrow.up"
            case .local: return "internaldrive"
            }
        }
    }

    init() {
        let schema = Schema([NoteRecord.self])
        let cloudConfiguration = ModelConfiguration(
            "MyNotes",
            schema: schema,
            cloudKitDatabase: .automatic
        )

        if let cloudContainer = try? ModelContainer(for: schema, configurations: [cloudConfiguration]) {
            modelContainer = cloudContainer
            modelContext = cloudContainer.mainContext
            syncStatus = .cloud
        } else {
            let localConfiguration = ModelConfiguration("MyNotesLocal", schema: schema, isStoredInMemoryOnly: false)
            guard let localContainer = try? ModelContainer(for: schema, configurations: [localConfiguration]) else {
                fatalError("Unable to initialize local SwiftData storage.")
            }
            modelContainer = localContainer
            modelContext = localContainer.mainContext
            syncStatus = .local
            storageError = "تعذر تفعيل iCloud حاليًا؛ تم تشغيل التخزين المحلي بأمان."
        }
        importLegacyJSONIfNeeded()
        startConnectivityMonitoring()
        setupCloudKitListeners()
        refresh()
    }

    // MARK: - Selection

    var selectedNote: Note? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    // MARK: - Library queries

    /// Notes that belong in the library surface. Archived notes stay in the
    /// store but are hidden until the user opens the archive.
    var activeNotes: [Note] {
        notes.filter { !$0.isArchived }
    }

    var archivedNotes: [Note] {
        notes.filter(\.isArchived)
    }

    var folders: [String] {
        Array(Set(activeNotes.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    var tags: [String] {
        Array(Set(activeNotes.flatMap(\.tags).filter { !$0.isEmpty })).sorted()
    }

    var pinnedNotes: [Note] {
        activeNotes.filter(\.isPinned)
    }

    var totalDueCards: Int {
        activeNotes.reduce(0) { $0 + $1.dueFlashcards.count }
    }

    var totalCards: Int {
        activeNotes.reduce(0) { $0 + $1.flashcards.count }
    }

    func notes(inFolder folder: String) -> [Note] {
        activeNotes.filter { $0.folder == folder }
    }

    func notes(withTag tag: String) -> [Note] {
        activeNotes.filter { $0.tags.contains(tag) }
    }

    func count(in folder: String) -> Int {
        notes(inFolder: folder).count
    }

    func count(forTag tag: String) -> Int {
        notes(withTag: tag).count
    }

    // MARK: - Mutations

    @discardableResult
    func createNote(title: String = "", content: String = "", folder: String = "الدراسة") -> Note {
        let note = Note(title: title, content: content, folder: folder)
        insert(note)
        selectedNoteID = note.id
        return note
    }

    /// Inserts a fully-formed note (from a template, a share, or an import)
    /// without losing tags, flashcards or attachments the way `createNote`
    /// with only title/content/folder would.
    @discardableResult
    func createNote(from note: Note) -> Note {
        var prepared = note
        if prepared.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prepared.folder = "الدراسة"
        }
        prepared.id = UUID()
        prepared.createdAt = .now
        prepared.updatedAt = .now
        insert(prepared)
        selectedNoteID = prepared.id
        return prepared
    }

    private func insert(_ note: Note) {
        modelContext.insert(NoteRecord(note: note))
        persist()
        SpotlightIndexer.index(note)
    }

    func update(_ note: Note) {
        var updated = note
        updated.updatedAt = .now
        if let record = record(for: updated.id) {
            record.update(from: updated)
            persist()
            SpotlightIndexer.index(updated)
        }
    }

    func togglePin(_ note: Note) {
        var updated = note
        updated.isPinned.toggle()
        update(updated)
    }

    func setArchived(_ archived: Bool, for note: Note) {
        var updated = note
        updated.isArchived = archived
        update(updated)
    }

    func delete(_ note: Note) {
        if let record = record(for: note.id) {
            modelContext.delete(record)
            persist()
            SpotlightIndexer.remove(noteID: note.id)
        }
        if selectedNoteID == note.id {
            selectedNoteID = activeNotes.first?.id
        }
        showBanner(.info, "تم حذف «\(note.displayTitle)»")
    }

    func deleteAllNotes() {
        let identifiers = notes.map(\.id)
        let records = (try? modelContext.fetch(FetchDescriptor<NoteRecord>())) ?? []
        records.forEach(modelContext.delete)
        persist()
        identifiers.forEach(SpotlightIndexer.remove(noteID:))
        selectedNoteID = nil
        showBanner(.warning, "تم حذف كل الملاحظات نهائيًا")
    }

    func refresh() {
        let descriptor = FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        notes = (try? modelContext.fetch(descriptor).map(\.asNote)) ?? []
    }

    // MARK: - Banner

    func showBanner(_ kind: Banner.Kind, _ message: String) {
        storageError = nil
        banner = Banner(kind: kind, message: message)
    }

    func clearBanner() {
        banner = nil
    }

    // MARK: - Persistence

    private func record(for id: UUID) -> NoteRecord? {
        guard let records = try? modelContext.fetch(FetchDescriptor<NoteRecord>()) else { return nil }
        return records.first { $0.id == id }
    }

    /// Saves and re-reads. Spotlight is *not* touched here: callers index the
    /// one note they changed, which keeps autosave proportional to the edit
    /// instead of re-indexing the whole library on every keystroke.
    private func persist() {
        do {
            try modelContext.save()
            refresh()
            if isOffline && syncStatus == .cloud {
                hasUnsyncedChanges = true
            }
        } catch {
            storageError = "تعذر حفظ البيانات محليًا: \(error.localizedDescription)"
            showBanner(.failure, "تعذر حفظ التعديلات محليًا")
        }
    }

    private func startConnectivityMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = path.status != .satisfied
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func importLegacyJSONIfNeeded() {
        guard (try? modelContext.fetch(FetchDescriptor<NoteRecord>()).isEmpty) == true else { return }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = directory.appendingPathComponent("mynotes.json")
        guard let data = try? Data(contentsOf: legacyURL),
              let legacyNotes = try? JSONDecoder().decode([Note].self, from: data) else { return }
        legacyNotes.forEach { modelContext.insert(NoteRecord(note: $0)) }
        try? modelContext.save()
    }

    private func setupCloudKitListeners() {
        guard syncStatus == .cloud else { return }

        #if canImport(Combine)
        Task {
            await CloudKitCollaboration.shared.syncUpdatePublisher
                .sink { [weak self] update in
                    Task { @MainActor in
                        self?.handleCloudKitUpdate(update)
                    }
                }
                .store(in: &cancellables)

            await CloudKitCollaboration.shared.collaboratorPublisher
                .sink { [weak self] collaborators in
                    Task { @MainActor in
                        self?.activeCollaborators = collaborators
                    }
                }
                .store(in: &cancellables)
        }
        #endif
    }

    private func handleCloudKitUpdate(_ update: CloudKitCollaboration.SyncUpdate) {
        guard let index = notes.firstIndex(where: { $0.id == update.noteID }) else { return }

        // Only apply a strictly newer remote version.
        guard update.updatedAt > notes[index].updatedAt else { return }

        var updatedNote = notes[index]
        updatedNote.title = update.title
        updatedNote.content = update.content
        updatedNote.folder = update.folder
        updatedNote.tags = update.tags
        updatedNote.updatedAt = update.updatedAt

        notes[index] = updatedNote

        if let record = record(for: update.noteID) {
            record.update(from: updatedNote)
            try? modelContext.save()
        }
        SpotlightIndexer.index(updatedNote)

        let author: String
        if let collaboratorID = update.collaboratorID,
           let collaborator = activeCollaborators.first(where: { $0.userID == collaboratorID }) {
            author = collaborator.name
        } else {
            author = "مستخدم آخر"
        }
        showBanner(.info, "تم تحديث «\(updatedNote.displayTitle)» بواسطة \(author)")
    }

    // MARK: - Sharing

    func shareNote(_ note: Note) async throws -> URL? {
        guard syncStatus == .cloud else {
            throw NSError(domain: "ShareError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "المشاركة تتطلب مزامنة iCloud. فعّل iCloud من إعدادات النظام ثم أعد المحاولة."
            ])
        }

        let result = try await CloudKitCollaboration.shared.createOrUpdate(note: note)

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index].cloudShareRecordName = result.recordName
            notes[index].cloudShareURL = result.url?.absoluteString
            update(notes[index])
        }

        hasUnsyncedChanges = false
        return result.url
    }

    func startCollaborating(on note: Note) {
        guard syncStatus == .cloud else { return }
        Task {
            try? await CloudKitCollaboration.shared.subscribeToNoteUpdates(noteID: note.id)
            await CloudKitCollaboration.shared.updateCollaboratorPresence(noteID: note.id, isEditing: true)
        }
    }

    func stopCollaborating(on note: Note) {
        guard syncStatus == .cloud else { return }
        Task {
            await CloudKitCollaboration.shared.updateCollaboratorPresence(noteID: note.id, isEditing: false)
        }
    }

    func setCollaboratorName(_ name: String) {
        Task {
            await CloudKitCollaboration.shared.setUserName(name)
        }
    }
}
