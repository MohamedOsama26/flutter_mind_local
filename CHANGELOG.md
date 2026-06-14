## 0.1.0

* Initial release.
* `LocalEngine` — on-device LLM inference via llama.cpp, no API key or internet required.
* `LocalConfig` — full configuration: model path, system prompt, temperature, context size, sampling parameters.
* `LocalModelType` — built-in chat templates for Qwen, Llama 3, Gemma, Phi, Mistral, DeepSeek, with auto-detection from `.gguf` metadata.
* Lifecycle events via `onEvent`: `ModelLoadStarted`, `ModelReady`, `ModelFailed`, `InferenceStarted`, `InferenceCompleted`, `InferenceFailed`, `ContextCleared`, `ModelDisposed`.
* Android support via CMake + `FetchContent` (llama.cpp built from source).
* iOS and macOS support via Swift Package Manager (llama.cpp built from source).
* Model loading and inference run on background isolates — UI thread never blocked.
