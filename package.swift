// swift-tools-version: 5.9
//
// SwiftPM build for iOS/macOS — the Android equivalent of src/CMakeLists.txt.
// Flutter 3.24+ uses SwiftPM by default for ffiPlugin targets instead of
// CocoaPods, so this file (not a .podspec) is what gets picked up.
//
// NOTE: untested on a real device/simulator — not yet enabled in pubspec.yaml's
// `flutter.plugin.platforms`. If you test this and it works, please report back.
import PackageDescription

let package = Package(
    name: "flutter_mind_local",
    // Minimum OS versions llama.cpp's Swift package itself requires.
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "flutter_mind_local",
            // dynamic, not static — Dart FFI opens this as a runtime library via
            // DynamicLibrary.process() (iOS) / DynamicLibrary.open() (macOS), it
            // can't link against a static archive the way Swift/ObjC code can.
            type: .dynamic,
            targets: ["flutter_mind_local"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ggerganov/llama.cpp",
            revision: "b4659"  // matches CMakeLists.txt LLAMA_CPP_TAG — keep both in sync
        ),
    ],
    targets: [
        .target(
            name: "flutter_mind_local",
            dependencies: [
                // "llama" is the product name llama.cpp's own Package.swift exposes —
                // not a name we chose. Renaming this without checking upstream breaks resolution.
                .product(name: "llama", package: "llama.cpp")
            ],
            path: "src",
            sources: ["flutter_mind_local.cpp"],
            cxxSettings: [
                // lets flutter_mind_local.cpp find flutter_mind_local.h via
                // #include "flutter_mind_local.h" without a path prefix.
                .headerSearchPath("."),
            ]
        ),
    ],
    // must match CMAKE_CXX_STANDARD in src/CMakeLists.txt — both compile the
    // same .cpp file against the same llama.cpp headers, so a mismatch in
    // language standard could compile cleanly on one platform and fail on the other.
    cxxLanguageStandard: .cxx17
)
