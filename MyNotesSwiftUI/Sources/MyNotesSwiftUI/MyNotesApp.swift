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
    }
}
