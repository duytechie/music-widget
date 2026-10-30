// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AlbumArtwork",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AlbumArtwork", targets: ["AlbumArtwork"])],
    targets: [
        .target(name: "ArtworkCore"),
        .executableTarget(name: "AlbumArtwork", dependencies: ["ArtworkCore"], resources: [.copy("Scripts")]),
        .testTarget(name: "ArtworkCoreTests", dependencies: ["ArtworkCore"])
    ],
    swiftLanguageModes: [.v5]
)
