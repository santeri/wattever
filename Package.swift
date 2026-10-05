// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "wattever",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "wattever", targets: ["wattever"])
  ],
  targets: [
    .target(
      name: "JouleSPI",
      path: "Sources/JouleSPI",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedLibrary("IOReport")
      ]
    ),
    .target(
      name: "JouleCore",
      dependencies: ["JouleSPI"],
      path: "Sources/JouleCore",
      linkerSettings: [
        .linkedFramework("IOKit")
      ]
    ),
    .executableTarget(
      name: "wattever",
      dependencies: ["JouleCore"],
      path: "Sources/wattever"
    ),
    .testTarget(
      name: "JouleCoreTests",
      dependencies: ["JouleCore"],
      path: "Tests/JouleCoreTests"
    ),
  ]
)
