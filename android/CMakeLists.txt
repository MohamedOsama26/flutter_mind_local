cmake_minimum_required(VERSION 3.18)

# Thin wrapper so Gradle (configured via android/build.gradle.kts'
# externalNativeBuild.cmake.path) has a CMakeLists.txt to point at, while the
# actual build logic lives in one place: src/CMakeLists.txt. That file is
# also reused as-is by the example app and is the single source of truth for
# how flutter_mind_local.cpp gets compiled against llama.cpp.
#
# "flutter_mind_local_build" is just the binary directory name CMake uses
# internally for this subdirectory — it isn't referenced anywhere else.
add_subdirectory(../src flutter_mind_local_build)
