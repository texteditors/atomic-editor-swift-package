// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "AtomicEditorSwiftPackage",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AtomicEditor", targets: ["AtomicEditor"])
    ],
    targets: [
        .target(
            name: "AtomicEditor",
            resources: [
                .process("Resources/CodeMirrorAtomic")
            ]
        )
    ]
)
