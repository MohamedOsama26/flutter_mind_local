# flutter_mind_local

On-device LLM inference for Flutter — powered by [llama.cpp](https://github.com/ggerganov/llama.cpp).  
No API key. No internet. No server. Runs entirely on the user's device.

A companion package to [flutter_mind](https://pub.dev/packages/flutter_mind) that implements
`LocalEngine`, a drop-in `AiEngine` for running quantized `.gguf` models locally.

---

## Features

- **Offline inference** — model runs fully on-device after the first download
- **Any GGUF model** — Qwen, Llama 3, Gemma, Phi, Mistral, DeepSeek, and more
- **Non-blocking** — model loading and inference run on background isolates
- **Lifecycle events** — know exactly when the model is loading, ready, or thinking
- **Auto chat template** — detects the correct prompt format from `.gguf` metadata
- **Android + iOS + macOS** — single package, no per-platform boilerplate

---

## Installation

```yaml
dependencies:
  flutter_mind_local: ^0.1.0
```

```dart
import 'package:flutter_mind_local/flutter_mind_local.dart';
```

One import gives you `LocalEngine`, `LocalConfig`, `LocalModelType`, all lifecycle
events, and the shared `AiEngine` interface from `flutter_mind`.

---

## Getting a model

Download any quantized GGUF model from [HuggingFace](https://huggingface.co/models?library=gguf).
Good starting points for mobile:

| Model | Size | HuggingFace |
|-------|------|-------------|
| Qwen 2.5 0.5B Q4 | ~400 MB | `Qwen/Qwen2.5-0.5B-Instruct-GGUF` |
| Qwen 2.5 1.5B Q4 | ~1 GB | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` |
| Llama 3.2 1B Q4 | ~700 MB | `meta-llama/Llama-3.2-1B-Instruct-GGUF` |
| Gemma 3 1B Q4 | ~700 MB | `google/gemma-3-1b-it-GGUF` |

Save the `.gguf` file to the device's app documents directory, then pass its
absolute path to `LocalConfig.modelPath`.

---

## Quick start

```dart
import 'package:flutter_mind_local/flutter_mind_local.dart';

final engine = LocalEngine(
  config: LocalConfig(
    modelPath: '/data/user/0/com.example.app/files/qwen.gguf',
  ),
);

// The model loads on the first send() call — no explicit init needed.
final response = await engine.send(userMessage: 'Hello! Who are you?');
print(response.text);

// Always dispose when done to free RAM.
engine.dispose();
```

---

## Configuration

All parameters except `modelPath` are optional — sensible defaults are applied automatically.

```dart
LocalConfig(
  // Required
  modelPath: '/path/to/model.gguf',

  // Recommended
  systemPrompt: Prompt(role: 'helpful assistant'),
  modelType: LocalModelType.qwen,      // or .auto to detect from metadata
  stopSequences: ['<|im_end|>'],        // model-specific stop tokens

  // Generation quality
  temperature: 0.7,       // 0.0 = deterministic, 2.0 = very creative
  maxOutputTokens: 512,   // max tokens to generate per response
  topP: 0.9,              // nucleus sampling threshold
  topK: 40,               // top-K sampling pool

  // Memory & performance
  contextSize: 2048,      // KV-cache size in tokens — limits conversation memory
  threads: 4,             // CPU threads — 4 is a safe default for mobile

  // Reproducibility
  seed: -1,               // -1 = random, any other value = reproducible output
  repeatPenalty: 1.1,     // penalise repeated tokens — 1.0 = off

  // Events
  onEvent: (event) => print(event),
)
```

### Model types

Set `modelType` to get the correct chat template applied automatically.
Use `LocalModelType.auto` (default) to detect from `.gguf` metadata.

| Value | Models |
|-------|--------|
| `LocalModelType.auto` | Auto-detect from metadata (recommended) |
| `LocalModelType.qwen` | Qwen 2, 2.5 family |
| `LocalModelType.llama3` | Llama 3, 3.2 family |
| `LocalModelType.gemma` | Gemma 1, 2, 3 family |
| `LocalModelType.phi` | Phi 2, 3, 4 family |
| `LocalModelType.mistral` | Mistral family |
| `LocalModelType.deepSeek` | DeepSeek family |

---

## Lifecycle events

Pass `onEvent` to `LocalConfig` to track what the engine is doing:

```dart
LocalConfig(
  modelPath: '/path/to/model.gguf',
  onEvent: (event) => switch (event) {
    ModelLoadStarted()                        => setState(() => _loading = true),
    ModelReady(:final loadTime)               => setState(() => _loading = false),
    ModelFailed(:final error)                 => setState(() => _error = error),
    InferenceStarted(:final userMessage)      => setState(() => _thinking = true),
    InferenceCompleted(:final inferenceTime)  => setState(() => _thinking = false),
    InferenceFailed(:final error)             => setState(() => _error = error),
    ContextCleared()                          => debugPrint('memory reset'),
    ModelDisposed()                           => null,
  },
)
```

| Event | When it fires |
|-------|--------------|
| `ModelLoadStarted` | `send()` called for the first time — model begins loading |
| `ModelReady` | Model fully loaded, includes `loadTime` |
| `ModelFailed` | Model failed to load, includes `error` |
| `InferenceStarted` | Generation begins, includes `userMessage` |
| `InferenceCompleted` | Response ready, includes `inferenceTime` |
| `InferenceFailed` | Generation failed, includes `error` |
| `ContextCleared` | KV-cache was reset due to context overflow |
| `ModelDisposed` | `dispose()` was called, model unloaded from RAM |

---

## Conversation history

Pass previous messages to maintain context across turns:

```dart
final history = <ChatMessage>[];

final response = await engine.send(
  userMessage: 'What did I just say?',
  history: history,
  maxHistoryMessages: 20, // keep last N turns to avoid context overflow
);

history.add(ChatMessage.user('What did I just say?'));
history.add(ChatMessage.model(response.text));
```

---

## Per-call config override

Override any config field for a specific call without changing the engine default:

```dart
final creative = await engine.send(
  userMessage: 'Write me a poem.',
  config: LocalConfig(
    modelPath: engine.defaultConfig.modelPath,
    temperature: 1.4,
    maxOutputTokens: 200,
  ),
);
```

---

## Thread safety

`LocalEngine` is **not thread-safe**. If two `send()` calls are made concurrently,
the second waits for the first to finish before starting. Use one engine instance
per screen or isolate it behind a queue.

---

## Platform notes

| Platform | Build system | Status |
|----------|-------------|--------|
| Android | CMake + FetchContent | ✅ |
| iOS | Swift Package Manager | ✅ |
| macOS | Swift Package Manager | ✅ |
| Linux | Not yet supported | — |
| Windows | Not yet supported | — |

llama.cpp is downloaded and compiled from source at build time — no pre-built
binaries, no manual setup required.
