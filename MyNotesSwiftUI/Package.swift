// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyNotesSwiftUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MyNotesSwiftUI", targets: ["MyNotesSwiftUI"])
    ],
    targets: [
        .executableTarget(name: "MyNotesSwiftUI")
    ]
)
