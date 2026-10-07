// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Quby",
    platforms: [.iOS(.v26)],
    products: [.library(name: "Quby", targets: ["Quby"])],
    targets: [
        .target(
            name: "Quby", path: "Quby",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release))])
    ],
    swiftLanguageModes: [.v5]
)
