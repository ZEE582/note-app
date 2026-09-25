# CloudKit setup

The app uses SwiftData with `cloudKitDatabase: .automatic`, which keeps notes
local-first and synchronizes through iCloud when the user is signed in. There is
no application login.

## The container identifier appears in two places

Changing it means editing **both**, or the app will launch and then fail the
first time a note is shared:

| Location | Form |
| --- | --- |
| `MyNotes.entitlements` | `com.apple.developer.icloud-container-identifiers` |
| `Sources/MyNotesSwiftUI/CloudKitCollaboration.swift` | `CKContainer(identifier:)` in the `database` property |

It defaults to `iCloud.com.mynotes.app`, which matches the bundle identifier in
`project.yml` (`com.mynotes.app`).

## Setup on macOS

1. Generate the project: `xcodeproj generate` (or `brew install xcodegen`
   first). See `DEPLOYMENT.md`.
2. Select the `MyNotes` target → **Signing & Capabilities** → add **iCloud**,
   then tick **CloudKit**.
3. Create the container in the
   [CloudKit Dashboard](https://icloud.developer.apple.com/) under the same
   identifier used in the two locations above.
4. Set your **Team** under Signing. The bundle identifier must be unique to
   your team; rename it in `project.yml` if `com.mynotes.app` is taken.
5. Deploy the schema: **Schema → Development → Deploy Schema**. Without this
   the container has no record types and every write fails.
6. Build and run on the device. Confirm the banner reads
   `مزامنة iCloud مفعلة` rather than `تخزين محلي`.

## Behaviour when CloudKit is unavailable

`NotesStore` falls back to a persistent local SwiftData store and reports
`تخزين محلي`, so notes are still saved and readable. Two caveats:

- The fallback only covers the **SwiftData** store. `CloudKitCollaboration`
  resolves its container lazily, so a missing capability no longer crashes the
  app at launch, but **sharing a note will still fail** until the container is
  provisioned.
- With the entitlement present but the container not yet created, SwiftData
  still builds its container successfully, so the app falls back silently and
  sync errors appear at runtime rather than as a clear configuration error.
  Deploying the schema first avoids this.

## Read-only sharing and collaboration

From the note toolbar, **إنشاء رابط قراءة فقط** writes a `SharedNoteSnapshot`
record and a `readOnly` `CKShare`, then surfaces the CloudKit link through
`ShareLink`. This is not a hosted HTTP link and needs no backend. The original
note stays in local SwiftData; on save, a previously shared note also attempts
to update its snapshot, and a CloudKit failure does not block the local save.

This is a deliberately thin CloudKit layer. Sharing SwiftData directly
(`CKShare` on a `ModelContainer`) varies across Xcode/SDK versions and needs a
deployed schema plus invite-acceptance testing. What exists is a read-only
link, not character-level live co-editing. Do not describe it to users as a
backend or as web hosting.

## Export

The note toolbar exports to Markdown, HTML, or PDF via `FileDocument` and the
system share sheet. Export does not flatten an imported PDF or modify the
source; the file bookmark stays separate.

## Spotlight

The app indexes note titles, typed content, folders, tags, and iPad handwriting
recognized through Vision. Results carry the note UUID and open the matching
note. This can only be verified on a real iOS/iPadOS device or simulator.
