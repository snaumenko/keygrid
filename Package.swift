// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyGrid",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: parsing, config, geometry. Imports no framework at all; fully unit-tested.
        .target(name: "KeyGridCore"),
        // The app: menu bar, hotkeys, Accessibility, Dock, overlay.
        .executableTarget(
            name: "KeyGrid",
            dependencies: ["KeyGridCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "KeyGridCoreTests", dependencies: ["KeyGridCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
