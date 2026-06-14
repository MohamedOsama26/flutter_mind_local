// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_mind_local",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "flutter_mind_local",
            type: .dynamic,
            targets: ["flutter_mind_local"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ggerganov/llama.cpp",
            revision: "b4659"  // matches CMakeLists.txt LLAMA_CPP_TAG
        ),
    ],
    targets: [
        .target(
            name: "flutter_mind_local",
            dependencies: [
                .product(name: "llama", package: "llama.cpp")
            ],
            path: "src",
            sources: ["flutter_mind_local.cpp"],
            cxxSettings: [
                .headerSearchPath("."),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
