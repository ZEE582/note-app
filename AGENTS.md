# Working in this repository

## What this is

A native **iPad-only** SwiftUI + SwiftData notes app. `MyNotesSwiftUI/` holds the
entire project. Nothing else in the repo is live code.

## Rules

- **iOS / iPadOS 17+ only.** There is no macOS target. `Package.swift` declares
  `.iOS(.v17)` and nothing else. Do not reintroduce `.macOS(...)`.
- **The UI is Arabic-first and right-to-left.** The root view sets
  `.environment(\.layoutDirection, .rightToLeft)`. User-facing strings are
  Arabic; keep it that way and keep the RTL assumption when adding views.
- **Do not add a `Project.swift` or an `.xcodeproj` to the package directory.**
  The app target is created in Xcode from the package.
- **Keep the pure-logic layer free of UIKit and SwiftUI.** `FlashcardLogic`,
  `StudyTemplates`, and the text portion of `NoteExporting` are the parts that
  can be compiled and tested on a plain host. Anything added to them has to stay
  buildable without an Apple SDK.
- **`#if canImport(...)` guards are deliberate.** They are what let the logic
  layer be built and tested off-Mac. They are always-true on iOS and cost
  nothing there. Do not "clean them up".
- **`#if os(macOS)` is gone for good.** It was removed along with the macOS
  target; do not bring it back.

## CloudKit

`MyNotes.entitlements` and `CLOUDKIT_SETUP.md` describe the container
(`iCloud.com.mynotes.app`). The store falls back to a local-only container when
the entitlement is absent, so local development needs no provisioning. Read
`CLOUDKIT_SETUP.md` before changing any schema or the container identifier.

## Verifying changes

There is no Apple SDK on Windows or Linux, so a full build is not possible off
a Mac. What *is* possible:

```sh
# syntax check every file
swiftc -parse -swift-version 5 Sources/MyNotesSwiftUI/<File>.swift
```

For behaviour changes, build the host-compilable logic layer and run assertions
against it. Everything touching SwiftData, CloudKit, PencilKit, Vision, AVFoundation,
or SwiftUI layout can only be validated on a simulator or device — say so rather
than claiming it works.
