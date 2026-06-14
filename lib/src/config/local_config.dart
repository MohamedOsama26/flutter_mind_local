import 'package:flutter_mind/flutter_mind.dart' show AiConfig, Prompt;
import '../events/local_engine_event.dart';

/// Configuration for local on-device AI models.
///
/// Runs entirely offline using llama.cpp engine.
/// No API key needed — just a path to a .gguf model file.
///
/// ```dart
/// // Minimal setup
/// final engine = LocalEngine(
///   config: LocalConfig(
///     modelPath: '/path/to/model.gguf',
///   ),
/// );
///
/// // Full setup
/// final engine = LocalEngine(
///   config: LocalConfig(
///     modelPath: '/path/to/model.gguf',
///     systemPrompt: Prompt(role: 'compassionate therapist'),
///     temperature: 0.8,
///     maxOutputTokens: 500,
///   ),
/// );
/// ```
/// ## Parameter reference
///
/// | Parameter         | What it controls                        | Most apps need it?   |
/// |-------------------|-----------------------------------------|----------------------|
/// | [modelPath]       | Path to the .gguf model file on device  | ✅ Always            |
/// | [systemPrompt]    | AI persona and instructions             | ✅ Always            |
/// | [temperature]     | Creativity level                        | ✅ Always            |
/// | [maxOutputTokens] | Max response length in tokens           | ✅ Recommended       |
/// | [stopSequences]   | Strings that stop generation immediately| ✅ Recommended       |
/// | [modelType]       | Chat template format for the model      | ✅ Recommended       |
/// | [contextSize]     | Conversation memory window in tokens    | ⚠️ Sometimes        |
/// | [repeatPenalty]   | Reduce repeated words in output         | ⚠️ Sometimes        |
/// | [topP]            | Creativity control (advanced)           | ❌ Leave default     |
/// | [topK]            | Creativity control (advanced)           | ❌ Leave default     |
/// | [threads]         | CPU threads for inference               | ❌ Leave default     |
/// | [seed]            | Reproducible output for testing         | ❌ Testing only      |
class LocalConfig extends AiConfig {
  /// Creates a local model configuration.
  ///
  /// Only [modelPath] is required. All other parameters fall back to
  /// safe defaults tuned for mobile performance.
  ///
  /// ```dart
  /// // Minimal — just the model path
  /// LocalConfig(modelPath: '/data/user/0/com.app/files/qwen.gguf')
  ///
  /// // With persona and stop sequences for Qwen
  /// LocalConfig(
  ///   modelPath: '/path/to/qwen.gguf',
  ///   systemPrompt: Prompt(role: 'helpful assistant'),
  ///   stopSequences: ['<|im_end|>', '<|im_start|>'],
  ///   modelType: LocalModelType.qwen,
  /// )
  /// ```
  const LocalConfig({
    required this.modelPath,
    super.systemPrompt,
    super.temperature,
    super.maxOutputTokens,
    super.stopSequences,
    super.topP,
    this.topK,
    this.contextSize,
    this.repeatPenalty,
    this.seed,
    this.threads,
    this.modelType = LocalModelType.auto,
    this.onEvent,
  });

  /// Path to the .gguf model file on device.
  ///
  /// Example: '/data/user/0/com.app/files/models/qwen.gguf'
  final String modelPath;

  /// Advanced creativity control — limits token pool size.
  ///
  /// Range: 1 – 100. Default: 40.
  final int? topK;

  /// How many tokens of conversation to remember.
  ///
  /// Larger = better memory but more RAM usage.
  /// Default: 2048
  final int? contextSize;

  /// Penalizes repeated words to reduce loops.
  ///
  /// Range: 1.0 – 2.0. Default: 1.1
  final double? repeatPenalty;

  /// Fixed seed for reproducible output.
  ///
  /// Useful for testing. Default: -1 (random)
  final int? seed;

  /// Number of CPU threads for inference.
  ///
  /// Default: 4 — targets the performance cores on most phones without
  /// saturating the efficiency cores, which keeps the OS responsive.
  ///
  /// Only change this if you have profiled your target device and confirmed
  /// a different value is faster.
  final int? threads;

  /// Chat template format for the model.
  ///
  /// Use [LocalModelType.auto] to detect from .gguf metadata.
  final LocalModelType modelType;


  /// Called whenever the engine transitions to a new lifecycle state.
  ///
  /// See [LocalEngineEvent] for the full list of events and their fields.
  final void Function(LocalEngineEvent event)? onEvent;

  /// Creates a copy with updated fields.
  LocalConfig copyWith({
    String? modelPath,
    Prompt? systemPrompt,
    double? temperature,
    int? maxOutputTokens,
    List<String>? stopSequences,
    double? topP,
    int? topK,
    int? contextSize,
    double? repeatPenalty,
    int? seed,
    int? threads,
    LocalModelType? modelType,
    void Function(LocalEngineEvent event)? onEvent,
  }) {
    return LocalConfig(
      modelPath: modelPath ?? this.modelPath,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      stopSequences: stopSequences ?? this.stopSequences,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      contextSize: contextSize ?? this.contextSize,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      seed: seed ?? this.seed,
      threads: threads ?? this.threads,
      modelType: modelType ?? this.modelType,
      onEvent: onEvent ?? this.onEvent,
    );
  }
}

/// Chat template format for local models.
enum LocalModelType {
  /// Auto-detect from .gguf metadata (recommended)
  auto,
  /// Qwen 2, 2.5 family
  qwen,
  /// Llama 3, 3.2 family
  llama3,
  /// Gemma 1, 2, 3 family
  gemma,
  /// Phi 2, 3, 4 family
  phi,
  /// Mistral family
  mistral,
  /// DeepSeek family
  deepSeek,
}