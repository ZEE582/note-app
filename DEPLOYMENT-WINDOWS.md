# Installing on the iPad from Windows

This is the route that does not need a Mac. A GitHub Actions macOS runner
builds an unsigned `.ipa`, and Sideloadly re-signs it with your Apple ID and
installs it over USB. The `macos-15` runner is used because iOS toolchains do
not exist anywhere else.

## What this gives you, and what it does not

| | Works | Why |
| --- | --- | --- |
| Install and run on the iPad | yes | Sideloadly re-signs with your Apple ID |
| Notes, editor, templates, flashcards | yes | pure Swift + SwiftData |
| Microphone attachments | yes | `NSMicrophoneUsageDescription` is in the committed `Info.plist` |
| Drawing with PencilKit | yes | device capability |
| iCloud sync and note sharing | **no** | the unsigned build carries no iCloud entitlement |

Without iCloud the app falls back to its local store and the banner reads
`تخزين محلي`. That is expected here, not a defect. `NotesStore` degrades to
local storage by design when the entitlement is absent.

A free Apple ID re-signs every **7 days**, after which you reinstall through
Sideloadly to keep launching it. A paid Apple Developer account lasts a year,
but iCloud still needs a Mac and the real signing build in `DEPLOYMENT.md`.

## One-time setup

1. **Put the repository on GitHub.** The workflow runs from GitHub, so the
   project needs a repo. A private repo is fine and keeps the source private;
   note that private repos draw macOS runner minutes from your monthly quota at
   a 10x weight.

   ```sh
   cd MyNotesApp
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```

2. **Install Sideloadly** on this Windows machine from
   <https://sideloadly.io>. It is what re-signs the `.ipa`.

3. **Connect the iPad** by USB, tap **Trust** on it, and in Sideloadly pick the
   device from the dropdown.

## Build and install

1. Push any change, or go to the **Actions** tab and run **Build unsigned IPA**
   manually.
2. When it finishes, download the `MyNotes-unsigned-ipa` artifact and unzip it
   to get `MyNotes-unsigned.ipa`.
3. In Sideloadly, drag that `.ipa` onto the window, enter your Apple ID, and
   press **Start**. Use an app-specific password if you have two-factor
   authentication enabled.
4. The app installs and launches on the iPad.

## Continuing to develop

The workflow is additive: it builds the same `project.yml` target Xcode uses, so
nothing about local development changes. Keep editing, verify what you can on
this machine, and push to get a fresh `.ipa`.

```sh
# what is verifiable on Windows
swiftc -parse -swift-version 5 MyNotesSwiftUI/Sources/MyNotesSwiftUI/<File>.swift

git log --oneline
```

The logic layer (flashcard scheduling, template generation, Markdown and HTML
export) is covered by a host-compilable harness; the UI, SwiftData, CloudKit,
PencilKit and Vision layers can only be checked on a device, which is what this
install is for.

## If the build fails

- **`No profiles for 'com.mynotes.app'`** — the bundle identifier belongs to
  another team. Change `PRODUCT_BUNDLE_IDENTIFIER` in `MyNotesSwiftUI/project.yml`.
- **No `.app` produced** — the build step logs the real error above it; read the
  full log rather than the summary.
- **XcodeGen rejects `project.yml`** — report it with the message; do not add an
  `info:` or `entitlements:` block as a workaround, that regenerates the
  committed `Info.plist` and drops the microphone usage string.
