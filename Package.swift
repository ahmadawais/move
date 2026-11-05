// swift-tools-version:6.2
import PackageDescription

// Swift 6 language mode, main-actor-by-default (AppKit app: hotkeys, Accessibility calls and UI live on the main thread).
let app: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Move",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MoveKit", path: "Sources/MoveKit", swiftSettings: app),
        .executableTarget(name: "Move", dependencies: ["MoveKit"], path: "Sources/Move", swiftSettings: app),
        .testTarget(name: "MoveTests", dependencies: ["MoveKit"], path: "Tests/MoveTests", swiftSettings: app),
    ]
)
