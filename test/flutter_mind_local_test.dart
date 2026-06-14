import 'package:flutter_mind_local/flutter_mind_local.dart';
import 'package:test/test.dart';

// Convenience — avoids repeating a valid path in every test.
LocalEngine _engine({
  String path = '/models/qwen.gguf',
  LocalConfig? config,
}) =>
    LocalEngine(config: config ?? LocalConfig(modelPath: path));

void main() {
  // ─── validate() ────────────────────────────────────────────────────────────

  group('validate', () {
    test('throws ConfigException when modelPath is empty', () {
      expect(
        () => LocalEngine(config: LocalConfig(modelPath: '')),
        throwsA(isA<ConfigException>()),
      );
    });

    test('throws ConfigException when modelPath has wrong extension', () {
      expect(
        () => _engine(path: '/models/qwen.bin'),
        throwsA(isA<ConfigException>()),
      );
    });

    test('does not throw for a valid .gguf path', () {
      expect(() => _engine(), returnsNormally);
    });
  });

  // ─── model getter ──────────────────────────────────────────────────────────

  group('model', () {
    test('returns filename without directory as model name', () {
      final engine = _engine(path: '/data/user/0/files/qwen2.5-0.5b-q4.gguf');
      expect(engine.model.value, 'qwen2.5-0.5b-q4.gguf');
    });
  });

  // ─── smart defaults ────────────────────────────────────────────────────────

  group('smart defaults', () {
    late LocalConfig config;

    setUp(() => config = _engine().defaultConfig);

    test('fills temperature', () => expect(config.temperature, 0.7));
    test('fills maxOutputTokens', () => expect(config.maxOutputTokens, 512));
    test('fills contextSize', () => expect(config.contextSize, 2048));
    test('fills repeatPenalty', () => expect(config.repeatPenalty, 1.1));
    test('fills topP', () => expect(config.topP, 0.9));
    test('fills topK', () => expect(config.topK, 40));
    test('fills threads', () => expect(config.threads, 4));

    test('preserves explicitly set temperature', () {
      final engine = _engine(
        config: LocalConfig(modelPath: '/models/qwen.gguf', temperature: 1.5),
      );
      expect(engine.defaultConfig.temperature, 1.5);
    });

    test('preserves explicitly set maxOutputTokens', () {
      final engine = _engine(
        config: LocalConfig(modelPath: '/models/qwen.gguf', maxOutputTokens: 256),
      );
      expect(engine.defaultConfig.maxOutputTokens, 256);
    });
  });

  // ─── buildPrompt ───────────────────────────────────────────────────────────

  group('buildPrompt', () {
    late LocalEngine engine;
    setUp(() => engine = _engine());

    test('returns userMessage as-is when history is null', () {
      expect(engine.testBuildPrompt(userMessage: 'Hello'), 'Hello');
    });

    test('returns userMessage as-is when history is empty', () {
      expect(
        engine.testBuildPrompt(userMessage: 'Hello', history: []),
        'Hello',
      );
    });

    test('prepends history turns before the user message', () {
      final result = engine.testBuildPrompt(
        userMessage: 'And you?',
        history: [
          const ChatMessage.user('Hi'),
          const ChatMessage.model('Hello!'),
        ],
      );
      expect(result, contains('user: Hi'));
      expect(result, contains('model: Hello!'));
      expect(result, endsWith('user: And you?'));
    });

    test('trims history to maxHistoryMessages most recent turns', () {
      final history = List.generate(
        25,
        (i) => ChatMessage.user('msg $i'),
      );
      final result = engine.testBuildPrompt(
        userMessage: 'last',
        history: history,
        maxHistoryMessages: 10,
      );
      // only the last 10 of 25 should appear
      expect(result, contains('msg 15'));
      expect(result, isNot(contains('msg 14')));
    });

    test('includes all turns when history is within maxHistoryMessages', () {
      final history = List.generate(5, (i) => ChatMessage.user('msg $i'));
      final result = engine.testBuildPrompt(
        userMessage: 'end',
        history: history,
        maxHistoryMessages: 10,
      );
      expect(result, contains('msg 0'));
      expect(result, contains('msg 4'));
    });
  });

  // ─── LocalConfig.copyWith ──────────────────────────────────────────────────

  group('LocalConfig.copyWith', () {
    const base = LocalConfig(
      modelPath: '/models/qwen.gguf',
      temperature: 0.5,
      topK: 20,
    );

    test('overrides specified fields', () {
      final updated = base.copyWith(temperature: 1.0);
      expect(updated.temperature, 1.0);
    });

    test('preserves unspecified fields', () {
      final updated = base.copyWith(temperature: 1.0);
      expect(updated.modelPath, '/models/qwen.gguf');
      expect(updated.topK, 20);
    });

    test('preserves modelType default', () {
      expect(base.copyWith().modelType, LocalModelType.auto);
    });
  });
}
