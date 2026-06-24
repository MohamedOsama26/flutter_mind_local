import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter_mind/flutter_mind.dart'
    show
        AiEngine,
        AiConfig,
        AiModel,
        CustomModel,
        AiResponse,
        ChatMessage,
        EngineException,
        ConfigException;
import 'package:meta/meta.dart';
import '../config/local_config.dart';
import '../events/local_engine_event.dart';

// FFI type definitions
typedef _InitParamsC =
    Int32 Function(
      Pointer<Utf8> modelPath,
      Pointer<Utf8> systemPrompt,
      Pointer<Utf8> stopSequences,
      Float temperature,
      Int32 maxTokens,
      Int32 contextSize,
      Float repeatPenalty,
      Float topP,
      Int32 topK,
      Int32 seed,
      Int32 threadCount,
      Int32 modelType,
    );
typedef _InitParamsDart =
    int Function(
      Pointer<Utf8> modelPath,
      Pointer<Utf8> systemPrompt,
      Pointer<Utf8> stopSequences,
      double temperature,
      int maxTokens,
      int contextSize,
      double repeatPenalty,
      double topP,
      int topK,
      int seed,
      int threadCount,
      int modelType,
    );

typedef _PromptC = Pointer<Utf8> Function(Pointer<Utf8> prompt);
typedef _PromptDart = Pointer<Utf8> Function(Pointer<Utf8> prompt);

typedef _PromptStartC = Int32 Function(Pointer<Utf8> prompt);
typedef _PromptStartDart = int Function(Pointer<Utf8> prompt);

typedef _PromptNextC = Pointer<Utf8> Function();
typedef _PromptNextDart = Pointer<Utf8> Function();

typedef _CleanupC = Void Function();
typedef _CleanupDart = void Function();

// Isolate helpers
//
// Isolate.run() can only call TOP-LEVEL functions — not class methods or
// lambdas that capture `this`. Everything below must live outside the class.

/// Bundles all config values needed to initialize the model.
///
/// Passed across the isolate boundary, so it must be a plain data object
/// with no references to class instances or platform channels.
class _LocalInitArgs {
  final String modelPath;
  final String systemPrompt;
  final String
  stopSequences; // \x1F-delimited e.g. "<|im_end|>\x1F<|im_start|>"
  final double temperature;
  final int maxTokens;
  final int contextSize;
  final double repeatPenalty;
  final double topP;
  final int topK;
  final int seed;
  final int threads;
  final int modelType;

  const _LocalInitArgs({
    required this.modelPath,
    required this.systemPrompt,
    required this.stopSequences,
    required this.temperature,
    required this.maxTokens,
    required this.contextSize,
    required this.repeatPenalty,
    required this.topP,
    required this.topK,
    required this.seed,
    required this.threads,
    required this.modelType,
  });
}

/// Opens the compiled native library for the current platform.
///
/// Top-level so it can be called from inside an isolate.
/// Each isolate opens its own handle — isolates don't share memory.
DynamicLibrary _openLib() {
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('libflutter_mind_local.so');
  }
  if (Platform.isIOS) return DynamicLibrary.process();
  if (Platform.isMacOS) {
    return DynamicLibrary.open('libflutter_mind_local.dylib');
  }
  throw const EngineException('LocalEngine: platform not supported.');
}

/// Loads the model inside the isolate and returns true on success.
///
/// Runs in a background isolate via [Isolate.run] — never blocks the UI thread.
/// All args come from [_LocalInitArgs] because isolates can't capture class state.
bool _runInit(_LocalInitArgs a) {
  final lib = _openLib();
  final fn = lib.lookupFunction<_InitParamsC, _InitParamsDart>(
    'flutter_mind_local_init_params',
  );
  final pathPtr = a.modelPath.toNativeUtf8();
  final sysPtr = a.systemPrompt.toNativeUtf8();
  final stopPtr = a.stopSequences.toNativeUtf8();
  final result = fn(
    pathPtr,
    sysPtr,
    stopPtr,
    a.temperature,
    a.maxTokens,
    a.contextSize,
    a.repeatPenalty,
    a.topP,
    a.topK,
    a.seed,
    a.threads,
    a.modelType,
  );
  calloc.free(pathPtr);
  calloc.free(sysPtr);
  calloc.free(stopPtr);
  return result == 0;
}

/// Runs inference inside the isolate and returns the response text.
///
/// Runs in a background isolate via [Isolate.run] — never blocks the UI thread.
/// Returns empty string if the native call returns a null pointer.
String _runPrompt(String prompt) {
  final lib = _openLib();
  final fn = lib.lookupFunction<_PromptC, _PromptDart>(
    'flutter_mind_local_prompt',
  );
  final ptr = prompt.toNativeUtf8();
  final result = fn(ptr);
  final text = result == nullptr ? '' : result.toDartString().trim();
  calloc.free(ptr);
  return text;
}

/// Sent to [_streamPromptEntry] — bundles the prompt and the port it reports
/// back through. [Isolate.spawn] takes exactly one argument, so this wraps both.
class _StreamArgs {
  final SendPort sendPort;
  final String prompt;
  const _StreamArgs({required this.sendPort, required this.prompt});
}

/// Sent back over the port when native setup or generation fails.
/// Distinct from a `String` token and from the `null` "done" sentinel.
class _StreamError {
  final String message;
  const _StreamError(this.message);
}

/// Isolate entry point for streaming — unlike [_runPrompt]/[Isolate.run],
/// this isolate stays alive for the whole generation and sends each token
/// over [SendPort] as soon as it's produced, instead of returning one final
/// value. Sends `null` as the "done" sentinel, or a [_StreamError] on failure.
void _streamPromptEntry(_StreamArgs args) {
  final lib = _openLib();
  final start = lib.lookupFunction<_PromptStartC, _PromptStartDart>(
    'flutter_mind_local_prompt_start',
  );
  final next = lib.lookupFunction<_PromptNextC, _PromptNextDart>(
    'flutter_mind_local_prompt_next',
  );

  final promptPtr = args.prompt.toNativeUtf8();
  final startResult = start(promptPtr);
  calloc.free(promptPtr);

  if (startResult != 0) {
    args.sendPort.send(const _StreamError('LocalEngine: failed to start generation.'));
    return;
  }

  while (true) {
    // prompt_next()'s returned pointer is native-owned (valid until the next
    // call) — read it immediately, do NOT calloc.free it, that's only for
    // buffers *we* allocated via toNativeUtf8().
    final tokenPtr = next();
    if (tokenPtr == nullptr) {
      args.sendPort.send(null); // done
      return;
    }
    args.sendPort.send(tokenPtr.toDartString());
  }
}

// Engine
/// AI engine for local on-device models via llama.cpp.
///
/// Runs entirely offline — no API key, no internet required.
///
/// ```dart
/// // Minimal setup
/// final engine = LocalEngine(
///   config: LocalConfig(
///     modelPath: '/data/user/0/com.app/files/models/qwen.gguf',
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
///     modelType: LocalModelType.qwen,
///   ),
/// );
///
/// // Send a message
/// final response = await engine.send(userMessage: 'Hello!');
/// print(response.text);
///
/// // Stream response
/// engine.stream(userMessage: 'Tell me a story').listen((chunk) {
///   print(chunk);
/// });
/// ```
///
/// Always call [dispose] when done to free model memory.
class LocalEngine implements AiEngine {
  /// Creates a LocalEngine.
  ///
  /// [config] is required — must include [LocalConfig.modelPath].
  ///
  /// The model is loaded lazily on the first [send] or [stream] call.
  LocalEngine({required LocalConfig config})
    : _defaultConfig = _resolveSmartDefaults(config) {
    validate();
  }

  final LocalConfig _defaultConfig;
  bool _initialized = false;

  // nullable instead of late final — _ensureInitialized can be entered concurrently
  _CleanupDart? _ffiCleanup;

  // guards against concurrent initialization — second caller waits on this
  Completer<void>? _initCompleter;

  // guards against concurrent inference — llama_decode crashes if called from two isolates simultaneously
  Completer<void>? _inferenceCompleter;

  // AiEngine interface
  @override
  AiModel get model => CustomModel(_defaultConfig.modelPath.split('/').last);

  @override
  Future<AiResponse> send({
    required String userMessage,
    AiConfig? config,
    List<ChatMessage>? history,
    int maxHistoryMessages = 20,
  }) async {
    final resolved = _mergeConfig(config);
    await _ensureInitialized(resolved);

    // wait if another inference is already running —
    // llama_decode crashes if called from two isolates simultaneously
    if (_inferenceCompleter != null) {
      await _inferenceCompleter!.future;
    }

    _inferenceCompleter = Completer<void>();

    resolved.onEvent?.call(InferenceStarted(userMessage: userMessage));
    final inferenceWatch = Stopwatch()..start();

    final prompt = _buildPrompt(
      userMessage: userMessage,
      history: history,
      maxHistoryMessages: maxHistoryMessages,
    );

    try {
      // run inference in background — does NOT block the UI thread
      final raw = await Isolate.run(() => _runPrompt(prompt));
      final text = _cleanResponse(raw, resolved.stopSequences ?? []);
      inferenceWatch.stop();
      resolved.onEvent?.call(
        InferenceCompleted(
          response: text,
          inferenceTime: inferenceWatch.elapsed,
        ),
      );
      _inferenceCompleter!.complete();
      _inferenceCompleter = null;
      return AiResponse(text: text, model: model);
    } catch (e) {
      resolved.onEvent?.call(InferenceFailed(error: e.toString()));
      _inferenceCompleter!.completeError(e);
      _inferenceCompleter = null;
      rethrow;
    }
  }

  @override
  Stream<String> stream({
    required String userMessage,
    AiConfig? config,
    List<ChatMessage>? history,
    int maxHistoryMessages = 20,
  }) async* {
    final resolved = _mergeConfig(config);
    await _ensureInitialized(resolved);

    // same concurrency guard as send() — both share the native engine's
    // global generation state, so only one can run at a time.
    if (_inferenceCompleter != null) {
      await _inferenceCompleter!.future;
    }
    _inferenceCompleter = Completer<void>();

    resolved.onEvent?.call(InferenceStarted(userMessage: userMessage));
    final inferenceWatch = Stopwatch()..start();

    final prompt = _buildPrompt(
      userMessage: userMessage,
      history: history,
      maxHistoryMessages: maxHistoryMessages,
    );

    final receivePort = ReceivePort();
    final buffer = StringBuffer();

    try {
      await Isolate.spawn(
        _streamPromptEntry,
        _StreamArgs(sendPort: receivePort.sendPort, prompt: prompt),
      );

      await for (final message in receivePort) {
        if (message == null) break; // done sentinel
        if (message is _StreamError) {
          throw EngineException(message.message);
        }
        final chunk = message as String;
        buffer.write(chunk);
        yield chunk;
      }

      inferenceWatch.stop();
      resolved.onEvent?.call(
        InferenceCompleted(
          response: buffer.toString(),
          inferenceTime: inferenceWatch.elapsed,
        ),
      );
      _inferenceCompleter!.complete();
      _inferenceCompleter = null;
    } catch (e) {
      resolved.onEvent?.call(InferenceFailed(error: e.toString()));
      _inferenceCompleter!.completeError(e);
      _inferenceCompleter = null;
      rethrow;
    } finally {
      receivePort.close();
    }
  }

  @override
  Future<int> countTokens({
    required String userMessage,
    AiConfig? config,
  }) async {
    // rough estimate: 1 token ≈ 4 characters
    return (userMessage.length / 4).ceil();
  }

  @override
  Future<bool> isAvailable() async {
    // check model file exists on device
    return File(_defaultConfig.modelPath).existsSync();
  }

  @override
  void validate() {
    if (_defaultConfig.modelPath.isEmpty) {
      throw const ConfigException(
        'LocalEngine: modelPath cannot be empty. '
        'Provide a path to a .gguf model file.',
      );
    }
    if (!_defaultConfig.modelPath.endsWith('.gguf')) {
      throw const ConfigException(
        'LocalEngine: modelPath must point to a .gguf file. '
        'Download a quantized model from HuggingFace.',
      );
    }
  }

  @override
  void dispose() {
    if (_initialized) {
      _ffiCleanup?.call();
      _initialized = false;
      _defaultConfig.onEvent?.call(ModelDisposed());
    }
  }

  // ─── Response cleaning ────────────────────────────────────────────────────

  /// Cuts the response at the first stop sequence found.
  ///
  /// Dart-side safety net for tokens C++ missed. Uses substring not replaceAll
  /// so everything after the stop token (leaked next turn) is also removed:
  /// "Hello!<|im_end|><|im_start|>user: ..." → "Hello!"
  ///
  /// Also handles partial stop sequences at the end — e.g. "<|im_end|" missing
  /// the closing ">" because the token was cut at the context boundary.
  ///
  /// Uses only the developer's configured [stopSequences] — nothing hardcoded.
  String _cleanResponse(String text, List<String> stopSequences) {
    String result = text;
    for (final stop in stopSequences) {
      // full occurrence — cut here and everything after
      final index = result.indexOf(stop);
      if (index != -1) {
        result = result.substring(0, index);
        continue;
      }
      // partial occurrence at end — e.g. "<|im_end|" without closing ">"
      for (int len = stop.length - 1; len > 0; len--) {
        if (result.endsWith(stop.substring(0, len))) {
          result = result.substring(0, result.length - len);
          break;
        }
      }
    }
    return result.trim();
  }

  // ─── Test helpers ─────────────────────────────────────────────────────────
  // These expose internals for unit tests only — do not use in production code.

  /// Exposes the resolved default config for unit tests.
  @visibleForTesting
  LocalConfig get defaultConfig => _defaultConfig;

  /// Exposes [_buildPrompt] for unit tests.
  @visibleForTesting
  String testBuildPrompt({
    required String userMessage,
    List<ChatMessage>? history,
    int maxHistoryMessages = 20,
  }) => _buildPrompt(
    userMessage: userMessage,
    history: history,
    maxHistoryMessages: maxHistoryMessages,
  );

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Initializes the model on first call.
  ///
  /// Uses a [Completer] so concurrent calls (e.g. two messages sent before
  /// the model finishes loading) wait on the same initialization instead of
  /// re-entering and crashing. Loading runs in a background isolate so the
  /// UI stays responsive. Typically takes 5–30 seconds depending on model size.
  Future<void> _ensureInitialized(LocalConfig config) async {
    if (_initialized) return;

    if (_initCompleter != null) {
      // another call is already initializing — wait for it to finish
      await _initCompleter!.future;
      return;
    }

    _initCompleter = Completer<void>();

    try {
      // bind cleanup on main thread — dispose() calls it directly
      final lib = _openLib();
      _ffiCleanup = lib.lookupFunction<_CleanupC, _CleanupDart>(
        'flutter_mind_local_cleanup',
      );

      if (!await isAvailable()) {
        throw EngineException(
          'LocalEngine: model file not found at "${config.modelPath}". '
          'Download the model first.',
        );
      }

      config.onEvent?.call(ModelLoadStarted());
      final loadWatch = Stopwatch()..start();

      // build the sendable args BEFORE entering the isolate closure — if we
      // reference `config` directly inside the closure, Isolate.run captures
      // the whole LocalConfig (including the unsendable `onEvent` closure,
      // which holds a reference back to this LocalEngine and its Completers)
      final initArgs = _LocalInitArgs(
        modelPath: config.modelPath,
        systemPrompt: config.systemPrompt?.build(userMessage: '') ?? '',
        stopSequences: (config.stopSequences ?? []).join('\x1F'),
        temperature: config.temperature ?? 0.7,
        maxTokens: config.maxOutputTokens ?? 512,
        contextSize: config.contextSize ?? 2048,
        repeatPenalty: config.repeatPenalty ?? 1.1,
        topP: config.topP ?? 0.9,
        topK: config.topK ?? 40,
        seed: config.seed ?? -1,
        threads: config.threads ?? 4,
        modelType: config.modelType.index,
      );

      // load model in background — does NOT block the UI thread
      final ok = await Isolate.run(() => _runInit(initArgs));

      if (!ok) {
        throw EngineException(
          'LocalEngine: failed to load model at "${config.modelPath}". '
          'Make sure the file is a valid .gguf model.',
        );
      }

      loadWatch.stop();
      _initialized = true;
      _initCompleter!.complete();
      config.onEvent?.call(ModelReady(loadTime: loadWatch.elapsed));
    } catch (e) {
      config.onEvent?.call(ModelFailed(error: e.toString()));
      final completer = _initCompleter!;
      _initCompleter = null;
      // Must call ignore() before completeError — registers a dummy handler so
      // Dart does not report "unhandled Future error" when no concurrent caller
      // is awaiting the completer. Callers that ARE waiting have their own
      // listener already attached and still receive the error normally.
      completer.future.ignore();
      completer.completeError(e);
      rethrow;
    }
  }

  /// Builds a conversation-aware prompt string.
  ///
  /// Includes history turns so the model remembers context.
  String _buildPrompt({
    required String userMessage,
    List<ChatMessage>? history,
    int maxHistoryMessages = 20,
  }) {
    if (history == null || history.isEmpty) return userMessage;

    // trim history to max
    final trimmed = history.length > maxHistoryMessages
        ? history.sublist(history.length - maxHistoryMessages)
        : history;

    // build conversation string
    final buffer = StringBuffer();
    for (final msg in trimmed) {
      buffer.writeln('${msg.role}: ${msg.text}');
    }
    buffer.write('user: $userMessage');

    return buffer.toString();
  }

  /// Merges a per-call config override with the stored default config.
  LocalConfig _mergeConfig(AiConfig? override) {
    if (override == null) return _defaultConfig;
    if (override is! LocalConfig) {
      throw ConfigException(
        'LocalEngine received ${override.runtimeType} — '
        'expected LocalConfig.',
      );
    }
    return _defaultConfig.copyWith(
      modelPath: override.modelPath,
      systemPrompt: override.systemPrompt,
      temperature: override.temperature,
      maxOutputTokens: override.maxOutputTokens,
      stopSequences: override.stopSequences,
      topP: override.topP,
      topK: override.topK,
      contextSize: override.contextSize,
      repeatPenalty: override.repeatPenalty,
      seed: override.seed,
      threads: override.threads,
      modelType: override.modelType,
    );
  }

  /// Applies smart defaults based on config.
  static LocalConfig _resolveSmartDefaults(LocalConfig config) {
    return config.copyWith(
      temperature: config.temperature ?? 0.7,
      maxOutputTokens: config.maxOutputTokens ?? 512,
      contextSize: config.contextSize ?? 2048,
      repeatPenalty: config.repeatPenalty ?? 1.1,
      topP: config.topP ?? 0.9,
      topK: config.topK ?? 40,
      threads: config.threads ?? 4,
    );
  }
}
