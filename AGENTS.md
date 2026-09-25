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
- **Do not add a `Project.swift` or a hand-written `.xcodeproj` to the
  repository.** The app target is declared in `MyNotesSwiftUI/project.yml` and
  generated with `xcodegen generate`. The `.xcodeproj` is gitignored on purpose
  so it cannot drift from the YAML. See `DEPLOYMENT.md`.
- **The app target compiles `Sources/MyNotesSwiftUI` directly.** It does not
  link `Package.swift` as a dependency. `Package.swift` now exports a library
  product purely so `swift build` can type-check the sources with the real SDKs
  before you open Xcode; an executable product there would invite linking it
  and colliding on `@main`, which lives only in `MyNotesApp.swift`.
- **Never add XcodeGen `info:` or `entitlements:` blocks with `properties`.**
  Those blocks *generate* the file and would overwrite the committed
  `Info.plist` and `MyNotes.entitlements`, silently dropping
  `NSMicrophoneUsageDescription` — which terminates the app on first mic
  access. Both are attached through the `INFOPLIST_FILE` and
  `CODE_SIGN_ENTITLEMENTS` build settings instead.
- **CloudKit schema rule.** Every stored property on `NoteRecord` must be
  optional or carry a default value, including any property added later.
  SwiftData's CloudKit backing rejects the schema at runtime otherwise, and it
  throws on first fetch rather than failing the build.
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

# full type check against the real SDKs (macOS only)
swift build --package-path MyNotesSwiftUI
```

`swift build` type-checks but cannot run. Running anything requires a
simulator or device. For behaviour changes, build the host-compilable logic
layer and run assertions against it. Everything touching SwiftData, CloudKit,
PencilKit, Vision, AVFoundation, or SwiftUI layout can only be validated on a
simulator or device — say so rather than claiming it works.
