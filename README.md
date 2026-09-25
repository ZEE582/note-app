# MyNotes — iPad notes app

A native SwiftUI + SwiftData notes app for iPad. Arabic-first (RTL), with
CloudKit sync, PencilKit drawing, audio attachments, flashcards, and a study
template catalogue.

## Requirements

- Xcode 15 or newer
- iOS / iPadOS 17.0 or newer
- An Apple Developer account for CloudKit and Spotlight

The package targets iOS only. There is no macOS build.

## Layout

```
MyNotesSwiftUI/
  Package.swift              Swift package manifest (iOS 17+)
  MyNotes.entitlements       iCloud container + CloudKit capability
  CLOUDKIT_SETUP.md          container and schema setup steps
  Sources/MyNotesSwiftUI/
    MyNotesApp.swift         App entry point, Spotlight deep links
    NotesStore.swift         SwiftData stack, CloudKit fallback, autosave
    Models.swift             Note, folder, attachment, bookmark models
    NotesLibraryView.swift   Library + detail columns
    NoteEditorView.swift     Editor, attachments, collaboration settings
    NoteExporting.swift      Markdown, HTML, PDF generation
    StudyTemplates.swift     Template catalogue and TemplateStore
    TemplateStoreView.swift  Template browsing and downloads
    FlashcardLogic.swift     Spaced-repetition scheduling
    FlashcardsReviewView.swift Review session UI
    CloudKitCollaboration.swift  Shared-zone collaboration
    NativeFeatures.swift     AVFoundation recording, PencilKit canvas
    SpotlightIndexer.swift   CoreSpotlight + Vision handwriting search
    DesignSystem.swift       Shared palette, typography, formatters
```

## Build

Open `MyNotesSwiftUI` as a Swift package in Xcode, or:

```sh
swift build -Xswiftc "-sdk" -Xswiftc "$(xcrun --show-sdk-path --sdk iphoneos)"
```

An `.xcodeproj` is not checked in. Create one in Xcode if you need a runnable
app target with the entitlements attached — the package alone does not carry
`MyNotes.entitlements`.

## Testing

The pure-logic layers (flashcard scheduling, template generation, Markdown and
HTML export) are framework-independent and can be exercised on a host without
an Apple SDK. The UI, SwiftData, CloudKit, PencilKit, and Vision layers cannot —
they need a simulator or device.

## CloudKit

See `CLOUDKIT_SETUP.md`. The app degrades to a local-only container when the
iCloud entitlement is missing, so it runs unsigned during development.
