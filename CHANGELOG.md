## 0.1.0

* Initial release.
* `LocalEngine` — on-device LLM inference via llama.cpp, no API key or internet required.
  Drop-in `AiEngine` for `flutter_mind`'s `FlutterMindClient` — same `send`/`stream`/`countTokens` API as every other engine.
* `LocalConfig` — full configuration: model path, system prompt, temperature, context size, sampling parameters.
* `LocalModelType` — built-in chat templates for Qwen, Llama 3, Gemma, Phi, Mistral, DeepSeek, with auto-detection from `.gguf` metadata.
* Real token-by-token streaming via `stream()` — tokens arrive as they're generated, not all at once at the end.
* Lifecycle events via `onEvent`: `ModelLoadStarted`, `ModelReady`, `ModelFailed`, `InferenceStarted`, `InferenceCompleted`, `InferenceFailed`, `ContextCleared`, `ModelDisposed`.
* Android support via CMake + `FetchContent` (llama.cpp built from source), tested on a real device.
* iOS and macOS build files exist (Swift Package Manager) but are untested — not yet enabled in `pubspec.yaml`.
* Model loading and inference run on background isolates — UI thread never blocked.
