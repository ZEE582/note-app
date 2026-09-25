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
  project.yml                XcodeGen manifest — source of truth for the app target
  Info.plist                 Usage descriptions, orientations, iPad keys
  Assets.xcassets            AppIcon, AccentColor
  MyNotes.entitlements       iCloud container + CloudKit capability
  CLOUDKIT_SETUP.md          container and schema setup steps
  DEPLOYMENT.md              generating the project and installing on an iPad
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

The `.xcodeproj` is generated, not committed:

```sh
brew install xcodegen
cd MyNotesSwiftUI
xcodegen generate
open MyNotesApp.xcodeproj
```

Then set your Team and bundle identifier, add the iCloud/CloudKit capability,
and run on the iPad. `DEPLOYMENT.md` walks through it, including a first-launch
checklist. Building an iOS app requires macOS and a paid Apple Developer
account.

## Testing

The pure-logic layers (flashcard scheduling, template generation, Markdown and
HTML export) are framework-independent and can be exercised on a host without
an Apple SDK. The UI, SwiftData, CloudKit, PencilKit, and Vision layers cannot —
they need a simulator or device.

## CloudKit

See `CLOUDKIT_SETUP.md`. The app degrades to a local-only container when the
iCloud entitlement is missing, so it runs unsigned during development.
