// swift-tools-version: 5.9
import PackageDescription

// This package is NOT the shipping build. The app is built by the XcodeGen
// target in project.yml, which compiles Sources/MyNotesSwiftUI directly so
// that Info.plist and MyNotes.entitlements stay attached to the app.
//
// What this package is for is a host-side type check: `swift build` compiles
// every source with the real SDKs, which catches type errors before you open
// Xcode. The UI layers still need a simulator or device to run.
let package = Package(
    name: "MyNotesSwiftUI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // A library rather than an executable on purpose. The `@main` App
        // struct lives in these sources for the Xcode app target; exposing an
        // executable product would invite someone to link the package as a
        // dependency and collide on the entry point.
        .library(name: "MyNotesSwiftUI", targets: ["MyNotesSwiftUI"])
    ],
    targets: [
        .target(name: "MyNotesSwiftUI")
    ]
)
