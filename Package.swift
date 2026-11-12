// swift-tools-version: 5.10
import PackageDescription

// PrivateInterfaces/ holds a hand-written interface for the non-public WidgetKit
// types that decode Live Activity archives. It shadows the SDK's WidgetKit module
// at compile time only; the real system framework is linked at run time.
let privateInterfaces = Context.packageDirectory + "/PrivateInterfaces"

let package = Package(
    name: "NotchLive",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/MrKai77/DynamicNotchKit", from: "1.1.0"),
    ],
    targets: [
        .target(name: "CShim"),
        .executableTarget(
            name: "NotchLive",
            dependencies: ["CShim", .product(name: "DynamicNotchKit", package: "DynamicNotchKit")],
            swiftSettings: [.unsafeFlags(["-I", privateInterfaces])],
            linkerSettings: [.linkedFramework("WidgetKit")]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
