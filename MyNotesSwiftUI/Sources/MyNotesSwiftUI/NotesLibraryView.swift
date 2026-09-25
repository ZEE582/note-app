import SwiftUI

// MARK: - Library filters

enum LibraryFilter: Hashable, Identifiable {
    case all
    case pinned
    case archive
    case folder(String)
    case tag(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .pinned: return "pinned"
        case .archive: return "archive"
        case .folder(let name): return "folder:\(name)"
        case .tag(let name): return "tag:\(name)"
        }
    }

    var title: String {
        switch self {
        case .all: return "كل الملاحظات"
        case .pinned: return "المثبّتة"
        case .archive: return "الأرشيف"
        case .folder(let name): return name
        case .tag(let name): return "#\(name)"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "note.text"
        case .pinned: return "pin.fill"
        case .archive: return "archivebox"
        case .folder: return "folder"
        case .tag: return "tag"
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case updated = "الأحدث تعديلًا"
    case created = "الأحدث إنشاءً"
    case title = "العنوان"
    case folder = "المجلد"

    var id: String { rawValue }
}

struct NotesLibraryView: View {
    @EnvironmentObject private var store: NotesStore
    @State private var search = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .updated
    @State private var showingQuickNote = false
    @State private var showingTemplateStore = false
    @State private var secondaryNoteID: UUID?
    @State private var deleteTarget: Note?
    @State private var reviewTarget: Note?
    @State private var newFolderName = ""
    @State private var showingNewFolder = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentColumn
        } detail: {
            detailColumn
        }
        .sheet(isPresented: $showingQuickNote) {
            QuickNoteView { title, content, folder in
                store.createNote(title: title, content: content, folder: folder)
            }
        }
        .sheet(isPresented: $showingTemplateStore) {
            TemplateStoreView()
        }
        .sheet(item: $reviewTarget) { note in
            FlashcardsReviewView(note: note) { updated in
                store.update(updated)
            }
        }
        .alert("حذف الملاحظة نهائيًا؟", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        ), presenting: deleteTarget) { note in
            Button("حذف نهائي", role: .destructive) { store.delete(note) }
            Button("إلغاء", role: .cancel) {}
        } message: { note in
            Text("سيُحذف «\(note.displayTitle)» ومحتواها نهائيًا، ولا يمكن استعادته.")
        }
        .alert("مجلد جديد", isPresented: $showingNewFolder) {
            TextField("اسم المجلد", text: $newFolderName)
            Button("إنشاء") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                store.createNote(folder: name)
                filter = .folder(name)
                newFolderName = ""
            }
            Button("إلغاء", role: .cancel) { newFolderName = "" }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $filter) {
            Section("المكتبة") {
                sidebarRow(.all, count: store.activeNotes.count)
                sidebarRow(.pinned, count: store.pinnedNotes.count)
                sidebarRow(.archive, count: store.archivedNotes.count)
            }

            Section {
                ForEach(store.folders, id: \.self) { folder in
                    sidebarRow(.folder(folder), count: store.count(in: folder))
                }
                Button {
                    showingNewFolder = true
                } label: {
                    Label("مجلد جديد", systemImage: "folder.badge.plus")
                }
            } header: {
                HStack {
                    Text("مجلداتي")
                    Spacer()
                    if store.totalDueCards > 0 {
                        Text("\(store.totalDueCards) بطاقة مستحقة")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            if !store.tags.isEmpty {
                Section("الوسوم") {
                    ForEach(store.tags, id: \.self) { tag in
                        sidebarRow(.tag(tag), count: store.count(forTag: tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MyNotes")
        .toolbar { sidebarToolbar }
        .safeAreaInset(edge: .bottom) { syncFooter }
    }

    private func sidebarRow(_ target: LibraryFilter, count: Int) -> some View {
        Label {
            HStack {
                Text(target.title)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: target.symbolName)
        }
        .tag(target)
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { store.createNote() } label: {
                    Label("ملاحظة فارغة", systemImage: "doc")
                }
                Button { showingTemplateStore = true } label: {
                    Label("من قالب", systemImage: "doc.text")
                }
                Button { showingQuickNote = true } label: {
                    Label("Quick Note", systemImage: "bolt.fill")
                }
            } label: {
                Label("ملاحظة جديدة", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { showingTemplateStore = true } label: {
                Label("متجر القوالب", systemImage: "square.grid.2x2")
            }
        }
    }

    private var syncFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isOffline ? "wifi.slash" : store.syncStatus.symbolName)
                .foregroundStyle(store.isOffline ? AppTheme.warning : (store.syncStatus == .cloud ? AppTheme.success : .secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.isOffline ? "أوفلاين · محفوظ محليًا" : store.syncStatus.label)
                    .font(.caption.weight(.bold))
                if store.hasUnsyncedChanges {
                    Text("بانتظار المزامنة")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Content

    private var visibleNotes: [Note] {
        let base: [Note]
        switch filter {
        case .all: base = store.activeNotes
        case .pinned: base = store.pinnedNotes
        case .archive: base = store.archivedNotes
        case .folder(let name): base = store.notes(inFolder: name)
        case .tag(let name): base = store.notes(withTag: name)
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = query.isEmpty ? base : base.filter { $0.searchHaystack.contains(query) }

        switch sort {
        case .updated: return matched.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.updatedAt > rhs.updatedAt
        }
        case .created: return matched.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.createdAt > rhs.createdAt
        }
        case .title: return matched.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
        }
        case .folder: return matched.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.folder != rhs.folder { return lhs.folder < rhs.folder }
            return lhs.updatedAt > rhs.updatedAt
        }
        }
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            if let banner = store.banner {
                BannerView(banner: banner) { store.clearBanner() }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            searchBar
            Divider()

            if visibleNotes.isEmpty {
                ScrollView {
                    if search.isEmpty {
                        EmptyStateCard(
                            title: "لا توجد ملاحظات هنا",
                            message: "أنشئ ملاحظتك الأولى أو استورد قالبًا جاهزًا من المتجر.",
                            icon: "square.and.pencil",
                            actionTitle: "ملاحظة جديدة",
                            action: { store.createNote() }
                        )
                    } else {
                        EmptyStateCard(
                            title: "لا توجد نتائج",
                            message: "جرّب كلمة بحث مختلفة أو امسح مربع البحث.",
                            icon: "magnifyingglass",
                            actionTitle: "مسح البحث",
                            action: { search = "" }
                        )
                    }
                }
            } else {
                List(selection: $store.selectedNoteID) {
                    ForEach(visibleNotes) { note in
                        NoteCard(note: note)
                            .tag(note.id)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteTarget = note } label: {
                                    Label("حذف", systemImage: "trash")
                                }
                                if !note.isArchived {
                                    Button { store.setArchived(true, for: note) } label: {
                                        Label("أرشفة", systemImage: "archivebox")
                                    }
                                    .tint(AppTheme.brand)
                                } else {
                                    Button { store.setArchived(false, for: note) } label: {
                                        Label("استرجاع", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(AppTheme.success)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { store.togglePin(note) } label: {
                                    Label(note.isPinned ? "إلغاء التثبيت" : "تثبيت", systemImage: note.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(AppTheme.warning)
                            }
                            .contextMenu { contextMenu(for: note) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(filter.title)
        .toolbar { contentToolbar }
        .animation(.snappy, value: store.banner)
    }

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingQuickNote = true } label: {
                Label("Quick Note", systemImage: "bolt.fill")
            }
        }
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Picker("الترتيب", selection: $sort) {
                    ForEach(LibrarySort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Label("ترتيب", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for note: Note) -> some View {
        Button { store.togglePin(note) } label: {
            Label(note.isPinned ? "إلغاء التثبيت" : "تثبيت", systemImage: note.isPinned ? "pin.slash" : "pin")
        }
        if !note.flashcards.isEmpty {
            Button { reviewTarget = note } label: {
                Label("مراجعة البطاقات", systemImage: "rectangle.stack")
            }
        }
        Button {
            guard note.id != store.selectedNoteID else { return }
            secondaryNoteID = note.id
        } label: {
            Label("فتح جنبًا إلى جنب", systemImage: "rectangle.split.2x1")
        }
        Button { store.setArchived(!note.isArchived, for: note) } label: {
            Label(note.isArchived ? "إلغاء الأرشفة" : "أرشفة", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
        }
        Divider()
        Button(role: .destructive) { deleteTarget = note } label: {
            Label("حذف نهائي", systemImage: "trash")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ابحث في العناوين والمحتوى والمجلدات والوسوم", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppTheme.neutralFill, in: RoundedRectangle(cornerRadius: AppTheme.Metrics.pillRadius, style: .continuous))

            Text("\(visibleNotes.count)")
                .font(.caption.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(AppTheme.brand)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.brandSoft, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Detail

    private var detailColumn: some View {
        Group {
            if let note = store.selectedNote {
                HStack(spacing: 0) {
                    NoteEditorView(note: note)
                        .id(note.id)
                    if let secondaryNoteID,
                       let secondaryNote = store.notes.first(where: { $0.id == secondaryNoteID }),
                       secondaryNote.id != note.id {
                        Divider()
                        NoteEditorView(note: secondaryNote)
                            .id(secondaryNote.id)
                    }
                }
            } else {
                ContentUnavailableView(
                    "اختر ملاحظة",
                    systemImage: "note.text",
                    description: Text("اختر ملاحظة من القائمة أو أنشئ واحدة جديدة.")
                )
            }
        }
    }
}

// MARK: - Banner

private struct BannerView: View {
    let banner: NotesStore.Banner
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.symbolName)
                .foregroundStyle(banner.tint)
            Text(banner.message)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(banner.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.Metrics.chipRadius, style: .continuous))
    }
}

// MARK: - Note card

struct NoteCard: View {
    let note: Note

    private var accent: Color { AppTheme.accent(for: note.folder) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [accent, accent.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                .frame(width: 5)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(note.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.warning)
                    }
                    Spacer(minLength: 0)
                    if note.isArchived {
                        Image(systemName: "archivebox.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(note.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    TagChip(text: note.folder, tint: accent)
                    ForEach(note.tags.prefix(2), id: \.self) { tag in
                        TagChip(text: "#\(tag)", tint: .secondary)
                    }
                    Spacer(minLength: 0)
                    attachmentBadges
                }
            }
        }
        .cardSurface(padding: 14, radius: AppTheme.Metrics.cardRadius)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var attachmentBadges: some View {
        HStack(spacing: 8) {
            if !note.flashcards.isEmpty {
                Label("\(note.flashcards.count)", systemImage: "rectangle.stack")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(note.dueFlashcards.isEmpty ? .secondary : AppTheme.brand)
            }
            if note.audioFileName != nil {
                Image(systemName: "waveform").font(.caption2).foregroundStyle(.secondary)
            }
            if note.pdf != nil {
                Image(systemName: "doc.richtext").font(.caption2).foregroundStyle(.secondary)
            }
            if !note.attachments.isEmpty {
                Image(systemName: "paperclip").font(.caption2).foregroundStyle(.secondary)
            }
            if note.drawingData != nil {
                Image(systemName: "pencil.tip").font(.caption2).foregroundStyle(.secondary)
            }
            Text(Formatters.relative(note.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Quick note

struct QuickNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var folder = "ملاحظات سريعة"
    let onSave: (String, String, String) -> Void

    private var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الملاحظة") {
                    TextField("عنوان اختياري", text: $title)
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                        .font(.body)
                    HStack {
                        Text("\(trimmedContent.count) حرف")
                        Spacer()
                        Text("\(trimmedContent.split(whereSeparator: \.isWhitespace).count) كلمة")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section {
                    TextField("المجلد", text: $folder)
                } header: {
                    Text("التنظيم")
                } footer: {
                    Text("تُحفظ الملاحظة فورًا في المجلد المحدد ويمكن إكمال تحريرها لاحقًا.")
                }
            }
            .navigationTitle("Quick Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        onSave(title, content, folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ملاحظات سريعة" : folder)
                        dismiss()
                    }
                    .disabled(trimmedContent.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
