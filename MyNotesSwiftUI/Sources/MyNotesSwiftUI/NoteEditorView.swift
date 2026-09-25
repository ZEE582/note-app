import SwiftUI
import UniformTypeIdentifiers
import Foundation

import UIKit

struct NoteEditorView: View {
    @EnvironmentObject private var store: NotesStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var note: Note
    @State private var showingManualCard = false
    @State private var showingReview = false
    @State private var showingImporter = false
    @State private var showingDrawing = false
    @StateObject private var audio = AudioRecorder()
    @State private var distractionFree = false
    @State private var paperTemplate: PaperTemplate = .lined
    @State private var inkColor: InkColor = .indigo
    @State private var penWidth: PenWidth = .medium
    @State private var isDropTargeted = false
    @State private var showingExporter = false
    @State private var exportDocument: NoteExportDocument?
    @State private var exportFormat: NoteExportFormat = .markdown
    @State private var shareURL: URL?
    @State private var shareMessage: String?
    @State private var errorMessage: String?
    @State private var showingCollaborationSettings = false
    @State private var collaboratorName = ""
    @State private var isDirty = false
    @State private var attachmentToDelete: NoteAttachment?
    @State private var showingDeleteNote = false

    private let autosave: TimeInterval = 1.2

    init(note: Note) {
        _note = State(initialValue: note)
    }

    var body: some View {
        editorScaffold
        .noteEditorSheets(
            note: $note,
            inkColor: inkColor.color,
            penStrokeWidth: penWidth.strokeWidth,
            exportFilename: exportFilename,
            showingImporter: $showingImporter,
            showingManualCard: $showingManualCard,
            showingReview: $showingReview,
            showingDrawing: $showingDrawing,
            showingCollaborationSettings: $showingCollaborationSettings,
            showingExporter: $showingExporter,
            exportDocument: $exportDocument,
            exportFormat: $exportFormat,
            collaboratorName: $collaboratorName,
            errorMessage: $errorMessage,
            onImportPDF: importPDF,
            onMarkDirty: markDirty,
            onSaveCollaborator: { name in
                store.setCollaboratorName(name)
                collaboratorName = name
            },
            onExportFinished: { error in
                if let error {
                    errorMessage = "تعذر تصدير الملف: \(error.localizedDescription)"
                } else {
                    errorMessage = nil
                }
            }
        )
        .noteEditorDialogs(
            shareMessage: $shareMessage,
            errorMessage: $errorMessage
        )
        .noteEditorDelete(
            note: note,
            showingDeleteNote: $showingDeleteNote,
            attachmentToDelete: $attachmentToDelete,
            onDeleteNote: {
                flush()
                store.delete(note)
                dismiss()
            },
            onDeleteAttachment: { attachment in
                note.attachments.removeAll { $0.id == attachment.id }
                markDirty()
            },
            onMarkDirty: markDirty
        )
        .noteEditorLifecycle(
            note: note,
            store: store,
            audio: audio,
            distractionFree: distractionFree,
            onMarkDirty: markDirty,
            onFlush: flush,
            onAutosave: autosaveLoop
        )
    }

    /// Split out of `body` so that neither the navigation scaffold nor
    /// the modifier chain is a single large expression. The type-checker
    /// walks one expression as a unit; chained here it stopped being able
    /// to produce any diagnostic at all for `body`, let alone a useful one.
    private var editorScaffold: some View {
        NavigationStack {
            editorContent
        }
        .navigationTitle(distractionFree ? "" : "تحرير الملاحظة")
        .toolbar { editorToolbar }
    }

    /// Built as its own value rather than inline in the toolbar closure.
    /// `.toolbar` has several overloads and the builder could not pick one
    /// for a twenty-two argument call; a single expression of a known type
    /// gives it nothing to choose between.
    private var editorToolbar: NoteEditorToolbar {
            NoteEditorToolbar(
                store: store,
                note: note,
                audio: audio,
                isDirty: isDirty,
                shareURL: shareURL,
                distractionFree: $distractionFree,
                paperTemplate: $paperTemplate,
                inkColor: $inkColor,
                penWidth: $penWidth,
                showingCollaborationSettings: $showingCollaborationSettings,
                showingManualCard: $showingManualCard,
                showingReview: $showingReview,
                showingDrawing: $showingDrawing,
                showingImporter: $showingImporter,
                onExport: { export($0) },
                onToggleAudio: { toggleAudio() },
                onAddAudioAnchor: { addAudioAnchor() },
                onGenerateCards: { generateCards() },
                onCreateReadOnlyLink: { createReadOnlyLink() },
                onFlush: { flush() },
                onCopyMarkdown: { copyMarkdown() },
                onToggleFocus: { withAnimation(.snappy) { distractionFree.toggle() } }
            )
    }

    @ViewBuilder
    private var editorContent: some View {
        // An explicit conditional rather than a `Group` wrapping both
        // branches: the two layouts are large enough that the ViewBuilder
        // exceeded the type-checker's budget and failed the build.
        if distractionFree {
            focusLayout
        } else {
            standardLayout
        }
    }

    // MARK: - Standard layout

    private var standardLayout: some View {
        Form {
            Section {
                TextField("عنوان الملاحظة", text: $note.title, axis: .vertical)
                    .font(.title3.weight(.bold))
                HStack {
                    Label("المجلد", systemImage: "folder")
                        .foregroundStyle(.secondary)
                    TextField("الدراسة", text: $note.folder)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Label("الوسوم", systemImage: "tag")
                        .foregroundStyle(.secondary)
                    TextField("افصل بفاصلة", text: tagsBinding)
                        .multilineTextAlignment(.trailing)
                }
                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(note.tags, id: \.self) { tag in
                                TagChip(text: "#\(tag)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollDisabled(true)
                }
            }

            Section("المحتوى") {
                editorSurface
            }

            if !note.attachments.isEmpty || note.pdf != nil || note.drawingData != nil || note.audioFileName != nil {
                Section("المرفقات والملاحظات") {
                    attachmentRows
                }
            }

            Section {
                if note.flashcards.isEmpty {
                    Text("لا توجد بطاقات بعد. ولّدها من المحتوى أو أضف بطاقة يدوية.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        generateCards()
                    } label: {
                        Label("توليد بطاقات من المحتوى", systemImage: "wand.and.stars")
                    }
                    .disabled(note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    HStack {
                        Label("\(note.flashcards.count) بطاقة", systemImage: "rectangle.stack")
                        Spacer()
                        if !note.dueFlashcards.isEmpty {
                            Text("\(note.dueFlashcards.count) مستحقة")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.success)
                        }
                    }
                    Button {
                        showingReview = true
                    } label: {
                        Label("ابدأ المراجعة", systemImage: "play.circle")
                    }
                }
                Button {
                    showingManualCard = true
                } label: {
                    Label("إضافة بطاقة يدوية", systemImage: "plus.rectangle.on.rectangle")
                }
            } header: {
                Text("بطاقات الاستذكار")
            }

            if !note.audioAnchors.isEmpty {
                Section("لحظات المحاضرة") {
                    ForEach(note.audioAnchors) { anchor in
                        HStack {
                            Label(anchor.timeLabel, systemImage: "bookmark.fill")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(AppTheme.brand)
                            Text(anchor.label)
                                .font(.subheadline)
                                .lineLimit(2)
                            Spacer()
                        }
                    }
                    Button(role: .destructive) {
                        note.audioAnchors.removeAll()
                        markDirty()
                    } label: {
                        Label("حذف كل اللحظات", systemImage: "trash")
                    }
                }
            }

            Section("إحصاءات") {
                HStack(spacing: 10) {
                    StatPill(icon: "textformat", value: "\(wordCount)", label: "كلمة")
                    StatPill(icon: "character", value: "\(characterCount)", label: "حرف", tint: .teal)
                    StatPill(icon: "clock", value: Formatters.medium(note.updatedAt), label: "آخر تعديل", tint: .orange)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteNote = true
                } label: {
                    Label("حذف الملاحظة", systemImage: "trash")
                }
            }
        }
    }

    private var editorSurface: some View {
        TextEditor(text: $note.content)
            .frame(minHeight: 280)
            .font(.system(size: penWidth.fontSize))
            .foregroundStyle(inkColor.color)
            .scrollContentBackground(.hidden)
            .background(PaperBackground(template: paperTemplate))
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.brand, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.text, .url, .image, .fileURL, .data],
                    isTargeted: $isDropTargeted,
                    perform: receiveDrop)
    }

    @ViewBuilder
    private var attachmentRows: some View {
        if note.drawingData != nil {
            HStack {
                Label("رسمة PencilKit", systemImage: "pencil.tip")
                Spacer()
                Button("تعديل") { showingDrawing = true }
                    .buttonStyle(.borderless)
                Button {
                    note.drawingData = nil
                    markDirty()
                } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.borderless)
            }
        }
        if note.audioFileName != nil {
            HStack {
                Label(Formatters.clock(note.audioDuration), systemImage: "waveform")
                Spacer()
                if audio.isRecording {
                    Button("تثبيت لحظة (\(Formatters.clock(audio.duration)))") { addAudioAnchor() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.danger)
                } else {
                    Button("تسجيل") { audio.start() }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            HStack {
                Label("لا يوجد تسجيل", systemImage: "waveform")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(audio.isRecording ? "إيقاف (\(Formatters.clock(audio.duration)))" : "تسجيل المحاضرة") {
                    toggleAudio()
                }
                .buttonStyle(.bordered)
                .tint(audio.isRecording ? AppTheme.danger : AppTheme.brand)
            }
        }
        if let pdf = note.pdf {
            HStack {
                Button {
                    openPDF(pdf)
                } label: {
                    Label(pdf.name, systemImage: "doc.richtext").lineLimit(1)
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    note.pdf = nil
                    markDirty()
                } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.borderless)
            }
        }
        ForEach(note.attachments) { attachment in
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.name).lineLimit(1)
                        Text(attachment.sizeLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: attachment.symbolName)
                }
                Spacer()
                Button {
                    attachmentToDelete = attachment
                } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                }
                .buttonStyle(.borderless)
            }
        }
        Button {
            showingImporter = true
        } label: {
            Label("إرفاق ملف PDF", systemImage: "doc.badge.plus")
        }
    }

    // MARK: - Focus mode

    private var focusLayout: some View {
        VStack(spacing: 0) {
            HStack {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(Formatters.clock(note.audioDuration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ScrollView {
                TextEditor(text: $note.content)
                    .frame(minHeight: 420)
                    .font(.system(size: penWidth.fontSize))
                    .foregroundStyle(inkColor.color)
                    .scrollContentBackground(.hidden)
                    .background(PaperBackground(template: paperTemplate))
                    .padding(.horizontal, 20)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Bindings and derived values

    private var tagsBinding: Binding<String> {
        Binding(
            get: { note.tags.joined(separator: "، ") },
            set: { value in
                note.tags = value
                    .split(whereSeparator: { $0 == "," || $0 == "،" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var wordCount: Int {
        note.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var characterCount: Int {
        note.content.count
    }

    private var exportFilename: String {
        let base = note.displayTitle.replacingOccurrences(of: "/", with: "-")
        return "\(base).\(exportFormat.fileExtension)"
    }

    // MARK: - Saving

    @MainActor
    private func markDirty() {
        guard !isDirty else { return }
        isDirty = true
    }

    /// Persists immediately. Safe to call repeatedly; a no-op when unchanged.
    @MainActor
    private func flush() {
        guard isDirty else { return }
        isDirty = false
        store.update(note)
        if note.audioFileName != nil, let name = audio.fileName, note.audioFileName != name {
            note.audioFileName = name
            store.update(note)
        }
    }

    /// Coalesces keystrokes into one write per `autosave` window so the store
    /// and Spotlight are not hammered on every keystroke.
    @MainActor
    private func autosaveLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(autosave * 1_000_000_000))
            } catch {
                return
            }
            if isDirty { flush() }
        }
    }

    // MARK: - Actions

    @MainActor
    private func export(_ format: NoteExportFormat) {
        flush()
        exportFormat = format
        exportDocument = NoteExportDocument(note: note, format: format)
        showingExporter = true
    }

    /// Lives here rather than inline in the toolbar so the toolbar struct
    /// does not have to hold `errorMessage` just to clear it.
    private func copyMarkdown() {
        Clipboard.copy(NoteExporter.markdown(for: note))
        errorMessage = nil
        store.showBanner(.success, "تم نسخ الملاحظة بصيغة Markdown")
    }

    @MainActor
    private func generateCards() {
        let generated = FlashcardGenerator.generate(from: note.content)
        guard !generated.isEmpty else {
            errorMessage = "لم أتمكن من توليد بطاقات من هذا المحتوى. أضف أسطرًا بصيغة «المفهوم: التعريف» أو أضف بطاقات يدوية."
            return
        }
        let existing = Set(note.flashcards.map(\.front))
        let fresh = generated.filter { !existing.contains($0.front) }
        note.flashcards.append(contentsOf: fresh)
        markDirty()
        if fresh.isEmpty {
            errorMessage = "البطاقات موجودة مسبقًا في هذه الملاحظة."
        } else {
            store.showBanner(.success, "تم توليد \(fresh.count) بطاقة")
        }
    }

    @MainActor
    private func importPDF(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var attachment = PDFAttachment(name: url.lastPathComponent, bookmark: nil)
            attachment.refreshBookmark(for: url)
            note.pdf = attachment
            markDirty()
        case .failure(let error):
            errorMessage = "تعذر إرفاق الملف: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func createReadOnlyLink() {
        flush()
        Task {
            do {
                let result = try await store.shareNote(note)
                shareURL = result
                if result == nil {
                    shareMessage = "تم حفظ المشاركة في CloudKit، لكن لم يُرجع النظام رابطًا بعد. أعد المحاولة لاحقًا."
                }
            } catch {
                shareMessage = "تعذر إنشاء رابط CloudKit: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Drag and drop

    @MainActor
    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !distractionFree else { return false }
        for provider in providers {
            let identifiers = provider.registeredTypeIdentifiers
            if identifiers.contains(UTType.fileURL.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    let name = provider.suggestedName ?? url.lastPathComponent
                    let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier
                    Task { @MainActor in
                        note.attachments.append(NoteAttachment(name: name, typeIdentifier: typeIdentifier, data: data))
                    }
                }
                continue
            }

            let preferredType = identifiers.first(where: {
                $0 == UTType.text.identifier || $0 == UTType.url.identifier
            }) ?? identifiers.first(where: { $0 != UTType.item.identifier })
            guard let typeIdentifier = preferredType else { continue }

            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    if typeIdentifier == UTType.text.identifier,
                       let text = String(data: data, encoding: .utf8) {
                        appendDroppedText(text)
                    } else if typeIdentifier == UTType.url.identifier,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        appendDroppedText(url.absoluteString)
                    } else {
                        let name = provider.suggestedName ?? "ملف مرفق"
                        note.attachments.append(NoteAttachment(name: name, typeIdentifier: typeIdentifier, data: data))
                    }
                }
            }
        }
        return true
    }

    @MainActor
    private func appendDroppedText(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !note.content.isEmpty, !note.content.hasSuffix("\n") {
            note.content.append("\n")
        }
        note.content.append(trimmed)
        note.content.append("\n")
    }

    // MARK: - Audio

    @MainActor
    private func toggleAudio() {
        if audio.isRecording {
            audio.stop()
            note.audioFileName = audio.fileName ?? note.audioFileName
            note.audioDuration = audio.duration
            markDirty()
        } else {
            audio.start()
        }
    }

    @MainActor
    private func addAudioAnchor() {
        let label = note.content
            .split(whereSeparator: { $0.isWhitespace })
            .suffix(6)
            .joined(separator: " ")
        note.audioAnchors.append(AudioAnchor(time: audio.duration,
                                             label: label.isEmpty ? "لحظة في المحاضرة" : label))
        markDirty()
    }

    // MARK: - PDF

    @MainActor
    private func openPDF(_ attachment: PDFAttachment) {
        guard let resolved = attachment.resolve() else {
            errorMessage = "لم يعد مسار الملف محفوظًا. أعد إرفاق الملف من جديد."
            return
        }
        guard resolved.url.startAccessingSecurityScopedResource() else {
            errorMessage = "لا يمكن فتح الملف خارج نطاق الأمان. انسخه إلى مجلد متاح للتطبيق."
            return
        }
        openURL(resolved.url)
        // The sandbox lease must be released; QuickLook reads asynchronously
        // and the file stays reachable through the resolved bookmark itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            resolved.url.stopAccessingSecurityScopedResource()
        }
        if resolved.wasStale {
            var refreshed = attachment
            refreshed.refreshBookmark(for: resolved.url)
            note.pdf = refreshed
            markDirty()
        }
    }

    // MARK: - Writing tools


    struct PaperBackground: View {
        let template: PaperTemplate
        var body: some View {
            Canvas { context, size in
                switch template {
                case .plain:
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.systemBackground)))
                case .dark:
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.88)))
                case .lined:
                    for y in stride(from: CGFloat(28), through: size.height, by: CGFloat(28)) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(.secondary.opacity(0.18)))
                    }
                case .grid:
                    for x in stride(from: CGFloat(0), through: size.width, by: CGFloat(24)) {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(.secondary.opacity(0.13)))
                    }
                    for y in stride(from: CGFloat(0), through: size.height, by: CGFloat(24)) {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(.secondary.opacity(0.13)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Manual flashcard

struct ManualFlashcardView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var front = ""
    @State private var back = ""
    let onSave: (String, String) -> Void

    private var isValid: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("السؤال") {
                    TextField("المفهوم أو السؤال", text: $front, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section("الإجابة") {
                    TextField("الشرح أو التعريف", text: $back, axis: .vertical)
                        .lineLimit(2...8)
                }
            }
            .navigationTitle("بطاقة جديدة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        onSave(front, back)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
}

// MARK: - Collaboration settings

struct CollaborationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: NotesStore
    let note: Note
    @Binding var collaboratorName: String
    let onSave: (String) -> Void

    private var trimmedName: String {
        collaboratorName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("هويتك") {
                    TextField("اسمك للمشاركة", text: $collaboratorName)
                        .onSubmit { commit() }
                    Text("سيظهر هذا الاسم للمستخدمين الآخرين عند العمل على نفس الملاحظة.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("حالة المشاركة") {
                    LabeledContent("المزامنة") {
                        Label(store.syncStatus == .cloud ? "مفعّلة" : "غير متاحة",
                              systemImage: store.syncStatus.symbolName)
                            .foregroundStyle(store.syncStatus == .cloud ? AppTheme.success : .secondary)
                    }
                    LabeledContent("الاتصال") {
                        Label(store.isOffline ? "أوفلاين" : "متصل", systemImage: store.isOffline ? "wifi.slash" : "wifi")
                            .foregroundStyle(store.isOffline ? AppTheme.warning : AppTheme.success)
                    }
                    if note.cloudShareURL != nil {
                        LabeledContent("رابط المشاركة") {
                            Label("مفعّل", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.success)
                        }
                    }
                }

                Section("المستخدمون النشطون") {
                    if store.activeCollaborators.isEmpty {
                        Text("لا يوجد مستخدمون نشطون حاليًا")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.activeCollaborators, id: \.userID) { collaborator in
                            HStack {
                                Circle()
                                    .fill(collaborator.isEditing ? AppTheme.success : Color.gray)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading) {
                                    Text(collaborator.name).font(.headline)
                                    Text(collaborator.isEditing ? "يحرر الآن" : "يشاهد فقط")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(timeAgo(collaborator.lastSeen))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let urlString = note.cloudShareURL, let url = URL(string: urlString) {
                    Section("رابط القراءة فقط") {
                        ShareLink(item: url) {
                            Label("مشاركة الرابط", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            Clipboard.copy(urlString)
                        } label: {
                            Label("نسخ الرابط", systemImage: "doc.on.doc")
                        }
                    }
                } else {
                    Section {
                        Text("لم يُنشأ رابط مشاركة لهذه الملاحظة بعد.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("المشاركة")
                    }
                }
            }
            .navigationTitle("إعدادات المشاركة")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        commit()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
    }

    private func commit() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName)
    }

    private func timeAgo(_ date: Date) -> String {
        Formatters.relative(date)
    }
}

/// The editor toolbar lives in its own ToolbarContent type rather than in
/// the body. Inline it made one expression that the type-checker could not
/// solve, and a some ToolbarContent property was ambiguous against the
/// other .toolbar overloads. A concrete struct sidesteps both problems:
/// the builder sees a plain type, and it is type-checked on its own.
/// The editor's presentation modifiers are split across three
/// `ViewModifier`s rather than chained in `body`.
///
/// They used to be one expression of roughly 130 statements: four sheets, a
/// file importer, a file exporter, four dialogs and the lifecycle hooks. The
/// type-checker walks such an expression as a single unit and ran out of budget
/// on it, reporting only `var body: some View`. Each group below is small
/// enough to check on its own, and a failure now names the group that caused
/// it instead of `body`.
private struct NoteEditorSheetsModifier: ViewModifier {
    @Binding var note: Note
    let inkColor: Color
    let penStrokeWidth: CGFloat
    let exportFilename: String
    @Binding var showingImporter: Bool
    @Binding var showingManualCard: Bool
    @Binding var showingReview: Bool
    @Binding var showingDrawing: Bool
    @Binding var showingCollaborationSettings: Bool
    @Binding var showingExporter: Bool
    @Binding var exportDocument: NoteExportDocument?
    @Binding var exportFormat: NoteExportFormat
    @Binding var collaboratorName: String
    @Binding var errorMessage: String?
    let onImportPDF: (Result<URL, Error>) -> Void
    let onMarkDirty: () -> Void
    let onSaveCollaborator: (String) -> Void
    let onExportFinished: (Error?) -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf],
                          onCompletion: onImportPDF)
            .sheet(isPresented: $showingManualCard) {
                ManualFlashcardView { front, back in
                    note.flashcards.append(Flashcard(front: front, back: back))
                    onMarkDirty()
                }
            }
            .sheet(isPresented: $showingReview) {
                FlashcardsReviewView(note: note) { updated in
                    note = updated
                    onMarkDirty()
                }
            }
            .sheet(isPresented: $showingDrawing) {
                DrawingView(
                    data: $note.drawingData,
                    inkColor: inkColor,
                    penWidth: penStrokeWidth,
                    onChange: onMarkDirty
                )
            }
            .sheet(isPresented: $showingCollaborationSettings) {
                CollaborationSettingsView(
                    note: note,
                    collaboratorName: $collaboratorName,
                    onSave: onSaveCollaborator
                )
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: exportFormat.contentType,
                defaultFilename: exportFilename
            ) { result in
                if case .failure(let error) = result {
                    onExportFinished(error)
                } else {
                    onExportFinished(nil)
                }
            }
    }
}

private struct NoteEditorDialogsModifier: ViewModifier {
    @Binding var shareMessage: String?
    @Binding var errorMessage: String?

    /// Mirrors the editor's `messageBinding`: a message is presented exactly
    /// while it is non-nil, and dismissing it clears it.
    private var shareMessagePresented: Binding<Bool> {
        Binding(get: { shareMessage != nil }, set: { if !$0 { shareMessage = nil } })
    }

    private var errorMessagePresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    func body(content: Content) -> some View {
        content
            .alert("مشاركة CloudKit", isPresented: shareMessagePresented) {
                Button("حسنًا", role: .cancel) { shareMessage = nil }
            } message: {
                Text(shareMessage ?? "")
            }
            .alert("تنبيه", isPresented: errorMessagePresented) {
                Button("حسنًا", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

/// The delete confirmations are separate from the alerts for the same
/// reason: four chained dialogs in one modifier was more than the
/// type-checker would resolve in its budget.
private struct NoteEditorDeleteModifier: ViewModifier {
    let note: Note
    @Binding var showingDeleteNote: Bool
    @Binding var attachmentToDelete: NoteAttachment?
    let onDeleteNote: () -> Void
    let onDeleteAttachment: (NoteAttachment) -> Void
    let onMarkDirty: () -> Void

    private var attachmentDeletePresented: Binding<Bool> {
        Binding(get: { attachmentToDelete != nil },
                set: { if !$0 { attachmentToDelete = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("حذف «\(note.displayTitle)»؟",
                                isPresented: $showingDeleteNote,
                                titleVisibility: .visible) {
                Button("حذف نهائي", role: .destructive, action: onDeleteNote)
                Button("إلغاء", role: .cancel) {}
            }
            .alert("حذف المرفق؟", isPresented: attachmentDeletePresented,
                   presenting: attachmentToDelete) { attachment in
                Button("حذف", role: .destructive) {
                    onDeleteAttachment(attachment)
                    attachmentToDelete = nil
                }
                Button("إلغاء", role: .cancel) { attachmentToDelete = nil }
            } message: { attachment in
                Text("سيُحذف «\(attachment.name)» من الملاحظة.")
            }
    }
}

private struct NoteEditorLifecycleModifier: ViewModifier {
    let note: Note
    let store: NotesStore
    let audio: AudioRecorder
    let distractionFree: Bool
    let onMarkDirty: () -> Void
    let onFlush: () -> Void
    let onAutosave: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if store.syncStatus == .cloud {
                    store.startCollaborating(on: note)
                }
            }
            .onDisappear {
                onFlush()
                if store.syncStatus == .cloud {
                    store.stopCollaborating(on: note)
                }
                if audio.isRecording { audio.stop() }
            }
            // Only the human-editable fields are observed. Watching the whole
            // `Note` would re-hash the drawing and every attachment blob on
            // every keystroke.
            .onChange(of: note.title) { onMarkDirty() }
            .onChange(of: note.content) { onMarkDirty() }
            .onChange(of: note.folder) { onMarkDirty() }
            .onChange(of: note.tags) { onMarkDirty() }
            .onChange(of: distractionFree) { onMarkDirty() }
            .task(id: note.id) { await onAutosave() }
    }
}

private extension View {
    func noteEditorSheets(
        note: Binding<Note>,
        inkColor: Color,
        penStrokeWidth: CGFloat,
        exportFilename: String,
        showingImporter: Binding<Bool>,
        showingManualCard: Binding<Bool>,
        showingReview: Binding<Bool>,
        showingDrawing: Binding<Bool>,
        showingCollaborationSettings: Binding<Bool>,
        showingExporter: Binding<Bool>,
        exportDocument: Binding<NoteExportDocument?>,
        exportFormat: Binding<NoteExportFormat>,
        collaboratorName: Binding<String>,
        errorMessage: Binding<String?>,
        onImportPDF: @escaping (Result<URL, Error>) -> Void,
        onMarkDirty: @escaping () -> Void,
        onSaveCollaborator: @escaping (String) -> Void,
        onExportFinished: @escaping (Error?) -> Void
    ) -> some View {
        modifier(NoteEditorSheetsModifier(
            note: note, inkColor: inkColor, penStrokeWidth: penStrokeWidth,
            exportFilename: exportFilename,
            showingImporter: showingImporter,
            showingManualCard: showingManualCard,
            showingReview: showingReview,
            showingDrawing: showingDrawing,
            showingCollaborationSettings: showingCollaborationSettings,
            showingExporter: showingExporter,
            exportDocument: exportDocument,
            exportFormat: exportFormat,
            collaboratorName: collaboratorName,
            errorMessage: errorMessage,
            onImportPDF: onImportPDF,
            onMarkDirty: onMarkDirty,
            onSaveCollaborator: onSaveCollaborator,
            onExportFinished: onExportFinished))
    }

    func noteEditorDialogs(
        shareMessage: Binding<String?>,
        errorMessage: Binding<String?>
    ) -> some View {
        modifier(NoteEditorDialogsModifier(
            shareMessage: shareMessage, errorMessage: errorMessage))
    }

    func noteEditorDelete(
        note: Note,
        showingDeleteNote: Binding<Bool>,
        attachmentToDelete: Binding<NoteAttachment?>,
        onDeleteNote: @escaping () -> Void,
        onDeleteAttachment: @escaping (NoteAttachment) -> Void,
        onMarkDirty: @escaping () -> Void
    ) -> some View {
        modifier(NoteEditorDeleteModifier(
            note: note, showingDeleteNote: showingDeleteNote,
            attachmentToDelete: attachmentToDelete,
            onDeleteNote: onDeleteNote,
            onDeleteAttachment: onDeleteAttachment, onMarkDirty: onMarkDirty))
    }

    func noteEditorLifecycle(
        note: Note,
        store: NotesStore,
        audio: AudioRecorder,
        distractionFree: Bool,
        onMarkDirty: @escaping () -> Void,
        onFlush: @escaping () -> Void,
        onAutosave: @escaping () async -> Void
    ) -> some View {
        modifier(NoteEditorLifecycleModifier(
            note: note, store: store, audio: audio,
            distractionFree: distractionFree,
            onMarkDirty: onMarkDirty, onFlush: onFlush, onAutosave: onAutosave))
    }
}

// MARK: - Writing tools
enum PaperTemplate: String, CaseIterable, Identifiable {
    case plain, lined, grid, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .plain: return "فارغ"; case .lined: return "مسطر"; case .grid: return "شبكي"; case .dark: return "ليلي" }
    }
    var icon: String {
        switch self { case .plain: return "doc"; case .lined: return "text.justify"; case .grid: return "grid"; case .dark: return "moon" }
    }
}

enum InkColor: String, CaseIterable, Identifiable {
    case indigo, black, blue, orange
    var id: String { rawValue }
    var title: String { rawValue == "indigo" ? "نيلي" : rawValue == "black" ? "أسود" : rawValue == "blue" ? "أزرق" : "برتقالي" }
    var color: Color {
        switch self { case .indigo: return .indigo; case .black: return .primary; case .blue: return .blue; case .orange: return .orange }
    }
}

enum PenWidth: String, CaseIterable, Identifiable {
    case fine, medium, bold
    var id: String { rawValue }
    var title: String { rawValue == "fine" ? "رفيع" : rawValue == "medium" ? "متوسط" : "عريض" }
    var fontSize: CGFloat { rawValue == "fine" ? 16 : rawValue == "medium" ? 18 : 21 }
    var strokeWidth: CGFloat { rawValue == "fine" ? 2.5 : rawValue == "medium" ? 4.5 : 8 }
}

private struct NoteEditorToolbar: ToolbarContent {
    let store: NotesStore
    let note: Note
    let audio: AudioRecorder
    let isDirty: Bool
    let shareURL: URL?
    @Binding var distractionFree: Bool
    @Binding var paperTemplate: PaperTemplate
    @Binding var inkColor: InkColor
    @Binding var penWidth: PenWidth
    @Binding var showingCollaborationSettings: Bool
    @Binding var showingManualCard: Bool
    @Binding var showingReview: Bool
    @Binding var showingDrawing: Bool
    @Binding var showingImporter: Bool
    let onExport: (NoteExportFormat) -> Void
    let onToggleAudio: () -> Void
    let onAddAudioAnchor: () -> Void
    let onGenerateCards: () -> Void
    let onCreateReadOnlyLink: () -> Void
    let onFlush: () -> Void
    let onCopyMarkdown: () -> Void
    let onToggleFocus: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .secondaryAction) {
            if store.syncStatus == .cloud && !store.activeCollaborators.isEmpty {
                Menu {
                    ForEach(store.activeCollaborators, id: \.userID) { collaborator in
                        Label {
                            HStack {
                                Text(collaborator.name)
                                if collaborator.isEditing {
                                    Text("(يحرر الآن)").foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: collaborator.isEditing ? "circle.fill" : "circle")
                                .foregroundStyle(collaborator.isEditing ? Color.green : Color.gray)
                        }
                    }
                } label: {
                    Label("\(store.activeCollaborators.count) متعاون", systemImage: "person.2")
                        .foregroundStyle(.green)
                }
            }
            Button { showingCollaborationSettings = true } label: {
                Label("إعدادات المشاركة", systemImage: "person.badge.plus")
            }
        }


        ToolbarItemGroup(placement: .primaryAction) {
            if !distractionFree {
                Menu {
                    Picker("قالب الورق", selection: $paperTemplate) {
                        ForEach(PaperTemplate.allCases, id: \.self) { template in
                            Label(template.title, systemImage: template.icon).tag(template)
                        }
                    }
                    Picker("سُمك القلم", selection: $penWidth) {
                        ForEach(PenWidth.allCases, id: \.self) { width in
                            Text(width.title).tag(width)
                        }
                    }
                    Picker("لون الحبر", selection: $inkColor) {
                        ForEach(InkColor.allCases, id: \.self) { color in
                            Text(color.title).tag(color)
                        }
                    }
                } label: {
                    Label("أدوات الكتابة", systemImage: "paintbrush")
                }
            }

            Menu {
                Button { showingDrawing = true } label: {
                    Label("الرسم بـ PencilKit", systemImage: "pencil.tip")
                }
                Button { showingImporter = true } label: {
                    Label("إرفاق PDF", systemImage: "doc.badge.plus")
                }
                Button { onToggleAudio() } label: {
                    Label(audio.isRecording ? "إيقاف التسجيل" : "تسجيل المحاضرة",
                          systemImage: audio.isRecording ? "stop.circle" : "mic")
                }
                if audio.isRecording {
                    Button { onAddAudioAnchor() } label: {
                        Label("تثبيت اللحظة الحالية", systemImage: "bookmark")
                    }
                }
            } label: {
                Label("الالتقاط والمرفقات", systemImage: "paperclip")
            }
            .disabled(distractionFree)

            Menu {
                Button { onGenerateCards() } label: {
                    Label("توليد بطاقات من المحتوى", systemImage: "wand.and.stars")
                }
                Button { showingManualCard = true } label: {
                    Label("بطاقة يدوية", systemImage: "plus.rectangle.on.rectangle")
                }
                Button { showingReview = true } label: {
                    Label("مراجعة البطاقات", systemImage: "play.circle")
                }
                .disabled(note.flashcards.isEmpty)
            } label: {
                Label("البطاقات", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(distractionFree)

            Menu {
                Button("تصدير Markdown") { onExport(.markdown) }
                Button("تصدير PDF") { onExport(.pdf) }
                Button("تصدير HTML (للويب)") { onExport(.html) }
                Divider()
                Button {
                    onCopyMarkdown()
                } label: {
                    Label("نسخ Markdown", systemImage: "doc.on.doc")
                }
                Divider()
                Button {
                    onCreateReadOnlyLink()
                } label: {
                    Label("إنشاء رابط قراءة فقط", systemImage: "link.badge.plus")
                }
                .disabled(store.syncStatus != .cloud)
                if let url = shareURL ?? note.cloudShareURL.flatMap(URL.init(string:)) {
                    ShareLink(item: url) {
                        Label("مشاركة الرابط", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("تصدير ومشاركة", systemImage: "square.and.arrow.up")
            }
            .disabled(distractionFree)

            Button {
                onToggleFocus()
            } label: {
                Label(distractionFree ? "إنهاء التركيز" : "وضع التركيز",
                      systemImage: distractionFree ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
            }

            Button("حفظ") { onFlush() }
                .fontWeight(.semibold)
                .disabled(!isDirty)
            }
    }
}
