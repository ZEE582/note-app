import SwiftUI
#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

@main
@MainActor
struct MyNotesApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            NotesLibraryView()
                .environmentObject(store)
                .modelContainer(store.modelContainer)
                .environment(\.layoutDirection, .rightToLeft)
                #if canImport(CoreSpotlight)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let noteID = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let id = UUID(uuidString: noteID) else { return }
                    // Selecting through the store (rather than assigning the
                    // id directly) keeps the detail column and the library list
                    // in agreement when Spotlight opens the app cold.
                    store.selectedNoteID = id
                    if !store.notes.contains(where: { $0.id == id }) {
                        store.showBanner(.info, "الملاحظة غير موجودة على هذا الجهاز بعد.")
                    }
                }
                #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("ملاحظة جديدة") { store.createNote() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(after: .toolbar) {
                Button("Quick Note") { store.createNote(folder: "ملاحظات سريعة") }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("تصدير Note Markdown المحدد") { exportSelectedAsMarkdown() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(store.selectedNote == nil)
            }
        }
        #endif
    }

    #if os(macOS)
    private func exportSelectedAsMarkdown() {
        guard let note = store.selectedNote else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(note.displayTitle).md")
        do {
            try Data(NoteExporter.markdown(for: note).utf8).write(to: url, options: .atomic)
            store.showBanner(.success, "تم حفظ «\(url.lastPathComponent)» في مجلد المستندات")
        } catch {
            store.showBanner(.failure, "تعذر حفظ الملف: \(error.localizedDescription)")
        }
    }
    #endif
}
