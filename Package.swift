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
      name: "WatteverSPI",
      path: "Sources/WatteverSPI",
      publicHeadersPath: "include",
      linkerSettings: [
        .linkedLibrary("IOReport")
      ]
    ),
    .target(
      name: "WatteverCore",
      dependencies: ["WatteverSPI"],
      path: "Sources/WatteverCore",
      linkerSettings: [
        .linkedFramework("IOKit")
      ]
    ),
    .executableTarget(
      name: "wattever",
      dependencies: ["WatteverCore"],
      path: "Sources/wattever"
    ),
    .testTarget(
      name: "WatteverCoreTests",
      dependencies: ["WatteverCore"],
      path: "Tests/WatteverCoreTests"
    ),
  ]
)
