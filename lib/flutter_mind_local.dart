/// On-device LLM inference for Flutter via llama.cpp — no API key, no internet.
///
/// Add the package and import a single file:
///
/// ```dart
/// import 'package:flutter_mind_local/flutter_mind_local.dart';
/// ```
///
/// Then create a [LocalEngine] and start chatting:
///
/// ```dart
/// final engine = LocalEngine(
///   config: LocalConfig(
///     modelPath: '/path/to/model.gguf',
///     modelType: LocalModelType.qwen,
///   ),
/// );
///
/// final response = await engine.send(userMessage: 'Hello!');
/// print(response.text);
///
/// engine.dispose();
/// ```
///
/// The model is loaded lazily on the first [LocalEngine.send] call and runs
/// entirely on-device. All heavy work happens on background isolates so the
/// UI thread is never blocked.
library;

// Core abstractions re-exported so users need only one import.
export 'package:flutter_mind/flutter_mind.dart'
    show
        AiEngine,
        AiConfig,
        AiResponse,
        AiModel,
        ChatMessage,
        Prompt,
        EngineException,
        ConfigException;

// Local engine implementation.
export 'src/engine/local_engine.dart';
export 'src/config/local_config.dart';
export 'src/events/local_engine_event.dart';
