cmake_minimum_required(VERSION 3.18)
project(flutter_mind_local CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# llama.cpp is CPU-bound (matrix multiply heavy) — an unoptimized debug build
# can be 10-20x slower at inference. Gradle passes -DCMAKE_BUILD_TYPE=Debug on
# the command line for debug builds, which sets the cache entry BEFORE this
# script runs — `if(NOT CMAKE_BUILD_TYPE)` would see it as already set and
# skip overriding it, so FORCE is applied unconditionally instead.
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)

# Pulls llama.cpp's source straight from GitHub at configure time and builds
# it as part of this project — no prebuilt binaries to maintain per-ABI.
include(FetchContent)

# Pin to a specific llama.cpp release tag for reproducible builds.
# Keep this in sync with package.swift's `revision:` (iOS/macOS build).
# Find the latest release at: https://github.com/ggerganov/llama.cpp/releases
set(LLAMA_CPP_TAG "b4659" CACHE STRING "llama.cpp release tag")

FetchContent_Declare(
    llama_cpp
    GIT_REPOSITORY https://github.com/ggerganov/llama.cpp.git
    GIT_TAG        ${LLAMA_CPP_TAG}
    GIT_SHALLOW    TRUE
)

# Disable everything we don't need — significantly speeds up the build.
# We only need the `llama` library target, not its CLI tools/tests/server.
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
# OFF, not ON: GGML_NATIVE=ON means "-march=native", which targets the
# *build host's* CPU (e.g. an x86_64 desktop). Cross-compiling for Android
# ARM with that flag would either fail or emit illegal instructions for the
# target device. NEON is the AArch64 baseline anyway, so arm64-v8a still
# gets vectorized kernels without it.
set(GGML_NATIVE          OFF CACHE BOOL "" FORCE)

FetchContent_MakeAvailable(llama_cpp)

# The actual plugin glue — FFI entry points + chat template formatting.
# See flutter_mind_local.cpp's file header for the design rationale.
add_library(flutter_mind_local SHARED
    flutter_mind_local.cpp
)

target_include_directories(flutter_mind_local
    PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}
)

# "llama" is the target name llama.cpp's own CMakeLists.txt exposes —
# not a name we chose.
target_link_libraries(flutter_mind_local
    PRIVATE llama
)
