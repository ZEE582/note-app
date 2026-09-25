# Getting this onto an iPad

The Swift package has no `.xcodeproj` committed. An app target needs one, and
it is generated from `project.yml` so the project file never drifts from source
control and never produces merge conflicts.

Everything in this file runs on the **Mac**. Nothing here can be done from
Windows: building an iOS app requires Xcode, which requires macOS.

## 1. Move the sources to the Mac

The repository is the only thing that needs to travel. Clone it, or copy the
folder across. Ignore `.build/` if it came along — it holds Windows artifacts
(`x86_64-unknown-windows-msvc`) that Xcode will not use.

## 2. Install XcodeGen and generate the project

```sh
brew install xcodegen
cd MyNotesSwiftUI
xcodegen generate
open MyNotesApp.xcodeproj
```

`xcodegen generate` produces `MyNotesApp.xcodeproj` next to `project.yml`.

If you would rather not install XcodeGen, create the target by hand in Xcode:
new iOS App target, interface **SwiftUI**, language **Swift**, then drag
`Sources/MyNotesSwiftUI` into it and attach `Info.plist` and
`MyNotes.entitlements`. Do not add a second `@main`.

## 3. Set the bundle identifier and team

`project.yml` ships `com.mynotes.app`, which is likely already taken by another
developer's App Store record. Open the target's **Signing & Capabilities** tab
and:

- set **Team** to your Apple Developer account
- change the **Bundle Identifier** to something unique, e.g.
  `com.yourname.mynotes`
- add the **iCloud** capability, then tick **CloudKit**

Then follow `CLOUDKIT_SETUP.md` to create the matching container and deploy the
schema. The identifier appears in two places, listed in that file.

## 4. Pick a target device

The project is iPad-only: `TARGETED_DEVICE_FAMILY` is `2`. To run on an iPad:

1. Plug the iPad in, or pair it with **Window → Devices and Simulators**.
2. Trust this Mac if prompted.
3. In Xcode choose the iPad as the run destination.
4. Hit **Run** (⌘R). Xcode signs and installs automatically with your team.

Signing for a device requires a **paid** Apple Developer account. A free
personal team can run on the iPad but expires after seven days and cannot use
iCloud entitlements.

## 5. Install manually instead

If you would rather not run from Xcode, use **Product → Archive** with
**Any iOS Device (arm64)** selected, then in the Organizer choose **Distribute
App** → **Ad Hoc** or **Development**, and export an `.ipa` to install through
Apple Configurator or a signing service.

## First launch checklist

- [ ] Banner reads `مزامنة iCloud مفعلة`, not `تخزين محلي`
- [ ] A note saves and survives an app restart
- [ ] Recording an audio attachment asks for the microphone, then records
- [ ] **إنشاء رابط قراءة فقط** produces a share link instead of failing
- [ ] Spotlight finds a note by title
- [ ] Handwriting drawn in the editor is searchable

Recording needs `NSMicrophoneUsageDescription`, which is in `Info.plist`. If a
build ever lacks it, the app terminates on first mic access.

## If the build fails

- **`@main` is ambiguous / duplicate** — the package and the app target both
  define an entry point. Only the app target should compile
  `Sources/MyNotesSwiftUI`; check that the target has not also added the
  package as a dependency.
- **`CKContainer` raises at runtime** — the container in
  `CLOUDKIT_SETUP.md` is missing or the schema was never deployed.
- **SwiftData store throws on load** — the CloudKit schema requires every
  stored property to be optional or defaulted. That is already the case in
  `NoteRecord`; if you add a property, give it a default.
- **Signing fails** — bundle identifier collision, expired profile, or a
  missing capability for the container being used.
