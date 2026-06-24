## 0.2.0

* `LocalEngine` is now a drop-in `AiEngine` for `flutter_mind`'s `FlutterMindClient` — same `send`/`stream`/`countTokens` API as every other engine.
* Real token-by-token streaming via `stream()` — tokens arrive as they're generated, not all at once at the end.
* Fixed an `Isolate.run` bug where the whole `LocalConfig` (including the unsendable `onEvent` closure) was captured instead of just the plain init args, causing a runtime crash.
* Fixed `android/build.gradle.kts` namespace colliding with the consuming app's own namespace.
* Native build now forces `Release` optimizations regardless of Flutter build variant — debug builds were previously 10-20x slower at inference.
* Android support verified on a real device. iOS/macOS build files exist (Swift Package Manager) but remain untested — not yet enabled in `pubspec.yaml`.

## 0.1.0

* Initial release.
* `LocalEngine` — on-device LLM inference via llama.cpp, no API key or internet required.
* `LocalConfig` — full configuration: model path, system prompt, temperature, context size, sampling parameters.
* `LocalModelType` — built-in chat templates for Qwen, Llama 3, Gemma, Phi, Mistral, DeepSeek, with auto-detection from `.gguf` metadata.
* Lifecycle events via `onEvent`: `ModelLoadStarted`, `ModelReady`, `ModelFailed`, `InferenceStarted`, `InferenceCompleted`, `InferenceFailed`, `ContextCleared`, `ModelDisposed`.
* Android support via CMake + `FetchContent` (llama.cpp built from source).
* iOS and macOS support via Swift Package Manager (llama.cpp built from source).
* Model loading and inference run on background isolates — UI thread never blocked.
