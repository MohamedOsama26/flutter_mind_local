plugins {
    id("com.android.library")
}

android {
    // Must be unique across every module in the consuming app's Gradle build —
    // AGP errors out if this collides with the host app's own namespace
    // (e.g. the example app's applicationId), which is why this isn't just
    // "dev.bedaya.flutter_mind_local_example" or similar.
    namespace = "dev.bedaya.flutter_mind_local"
    compileSdk = 35

    defaultConfig {
        minSdk = 24  // minimum Android version llama.cpp's NDK build supports

        // arm64-v8a covers real devices; x86_64 covers the emulator.
        // armeabi-v7a (32-bit) is deliberately excluded — llama.cpp's
        // performance on 32-bit ARM isn't worth maintaining for this plugin.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Points Gradle at the CMake build that actually compiles
    // flutter_mind_local.cpp against llama.cpp. See CMakeLists.txt (this
    // directory) and src/CMakeLists.txt for the real build logic.
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}