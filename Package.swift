// swift-tools-version:5.9
import PackageDescription

// The GitHub organization of the suite's repositories: the one name to change should it be renamed (the
// suite repository's scripts/rename-organization.sh does it in every repository).
let organization = "love-suite"

// Desktop: the suite's desktop in place of Finder's, as an app of its own (it was part of Explorer until
// 2026-11-24). Its arrangement stays UI-free and tested in DesktopCore; its settings are a library of their
// own, which Suite Settings reads for its Desktop tab. Finder's desktop, which it hides, is put back by
// Suite Guard should it vanish.
let suiteCore = Target.Dependency.product(name: "SuiteCore", package: "suite-core")
let finderGuard = Target.Dependency.product(name: "FinderGuard", package: "suite-guard")
let filesCore = Target.Dependency.product(name: "SuiteFilesCore", package: "suite-files")
let filesUI = Target.Dependency.product(name: "SuiteFilesUI", package: "suite-files")

let package = Package(
    name: "Desktop",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DesktopSettings", targets: ["DesktopSettings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/\(organization)/suite-core", .upToNextMinor(from: "27.1.0-dev.1")),
        .package(url: "https://github.com/\(organization)/suite-guard", .upToNextMinor(from: "27.1.0-dev.1")),
        .package(url: "https://github.com/\(organization)/suite-files", .upToNextMinor(from: "27.1.0-dev.1")),
    ],
    targets: [
        // The desktop's settings as Desktop and Suite Settings read and write them, and the messages between
        // them. No UI.
        .target(name: "DesktopSettings", dependencies: [filesCore]),
        // What the desktop shows and where: entries, the grid, stacks, overflow (no UI, unit-tested).
        .target(name: "DesktopCore", dependencies: ["DesktopSettings", filesCore]),
        .testTarget(name: "DesktopCoreTests", dependencies: ["DesktopCore", "DesktopSettings", filesCore]),
        // The app: the desktop window, its icons, drag and drop, stacks, its menu bar, Finder's desktop.
        .executableTarget(
            name: "Desktop",
            dependencies: ["DesktopCore", "DesktopSettings", suiteCore, filesCore, filesUI, finderGuard],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("Quartz"), .linkedFramework("ServiceManagement")]
        ),
    ]
)
