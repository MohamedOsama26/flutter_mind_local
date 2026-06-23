/// Events emitted by [LocalEngine] at each stage of the model lifecycle.
///
/// Pass an [onEvent] handler to [LocalConfig] to receive these events:
///
/// ```dart
/// LocalConfig(
///   modelPath: '/path/to/model.gguf',
///   onEvent: (event) => switch (event) {
///     ModelLoadStarted()                       => setState(() => _loading = true),
///     ModelReady(:final loadTime)              => setState(() => _ready = true),
///     ModelFailed(:final error)                => setState(() => _error = error),
///     InferenceStarted()                       => setState(() => _thinking = true),
///     InferenceCompleted(:final inferenceTime) => setState(() => _thinking = false),
///     InferenceFailed(:final error)            => setState(() => _error = error),
///     ContextCleared()                         => debugPrint('context reset'),
///     ModelDisposed()                          => null,
///   },
/// )
/// ```
///
/// The sealed keyword gives exhaustiveness checking — if a new event is added
/// in a future version, the compiler warns you that your switch is incomplete.
sealed class LocalEngineEvent {}

/// Fired when model loading begins.
///
/// Use this to show a loading indicator. Loading typically takes 5–30 seconds
/// depending on model size and device speed.
final class ModelLoadStarted extends LocalEngineEvent {}

/// Fired when the model is fully loaded and ready to accept messages.
///
/// [loadTime] is the total time from [ModelLoadStarted] to ready.
final class ModelReady extends LocalEngineEvent {
  /// How long the model took to load.
  final Duration loadTime;

  /// Creates a [ModelReady] event.
  ModelReady({required this.loadTime});
}

/// Fired when the model fails to load.
///
/// [error] contains the underlying exception message.
/// After this event, [LocalEngine] resets so the next [send] will retry.
final class ModelFailed extends LocalEngineEvent {
  /// The error that caused the load to fail.
  final String error;

  /// Creates a [ModelFailed] event.
  ModelFailed({required this.error});
}

/// Fired when inference begins — i.e. the model starts generating a response.
///
/// Use this to show a "thinking..." indicator.
/// [userMessage] is the message that triggered this inference.
final class InferenceStarted extends LocalEngineEvent {
  /// The user message that triggered this inference.
  final String userMessage;

  /// Creates an [InferenceStarted] event.
  InferenceStarted({required this.userMessage});
}

/// Fired when inference completes successfully.
///
/// [inferenceTime] is the time from [InferenceStarted] to response returned.
/// [response] is the final cleaned response text.
final class InferenceCompleted extends LocalEngineEvent {
  /// The generated response text.
  final String response;

  /// How long the model took to generate the response.
  final Duration inferenceTime;

  /// Creates an [InferenceCompleted] event.
  InferenceCompleted({required this.response, required this.inferenceTime});
}

/// Fired when inference fails.
///
/// [error] contains the underlying exception message.
final class InferenceFailed extends LocalEngineEvent {
  /// The error that caused inference to fail.
  final String error;

  /// Creates an [InferenceFailed] event.
  InferenceFailed({required this.error});
}

/// Fired when the KV cache is cleared due to context overflow.
///
/// This means the conversation history the model holds internally has been
/// reset. The model will respond as if starting a fresh conversation.
/// Consider prompting the user: "Memory was reset — the model forgot earlier messages."
final class ContextCleared extends LocalEngineEvent {}

/// Fired when [LocalEngine.dispose] is called and the model is unloaded from RAM.
final class ModelDisposed extends LocalEngineEvent {}
