// swift-tools-version:5.9
// Unit tests for the pure logic files of DayDayUp (FSRS, queue, answer check, CSV, pack diff).
// The CI copies DayDayUp/Logic/*.swift and DayDayUp/Models/PackModels.swift into Sources/DDULogic
// before running `swift test`, so the app and the tests always use the same source files.
import PackageDescription

let package = Package(
    name: "DDULogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DDULogic", path: "Sources/DDULogic"),
        .testTarget(
            name: "DDULogicTests",
            dependencies: ["DDULogic"],
            path: "Tests/DDULogicTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
