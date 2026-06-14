// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwimWorkoutKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
    ],
    products: [
        .library(name: "SwimWorkoutKit", targets: ["SwimWorkoutKit"]),
        .library(name: "SwimWorkoutKitUI", targets: ["SwimWorkoutKitUI"]),
        .executable(name: "swimtext", targets: ["SwimTextTool"]),
        .executable(name: "swimocr", targets: ["SwimOCRTool"]),
        .executable(name: "swimclaude", targets: ["SwimClaudeTool"]),
    ],
    targets: [
        .target(name: "SwimWorkoutKit"),
        // SwiftUI/UIKit layer: SwimText syntax highlighting (SwimTextView,
        // SwimTextEditor, SwimTextLabel). Kept separate so the core stays UI-free.
        .target(name: "SwimWorkoutKitUI", dependencies: ["SwimWorkoutKit"]),
        .executableTarget(name: "SwimTextTool", dependencies: ["SwimWorkoutKit"]),
        .executableTarget(name: "SwimOCRTool", dependencies: ["SwimWorkoutKit"]),
        .executableTarget(name: "SwimClaudeTool", dependencies: ["SwimWorkoutKit"]),
        .testTarget(
            name: "SwimWorkoutKitTests",
            dependencies: ["SwimWorkoutKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
